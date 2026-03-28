use crate::buffer::{buffer_message, drain_buffered_messages};
use ferlay_shared::messages::ControlMessage;
use crate::pairing::{create_pairing_code, validate_pairing_code};
use crate::state::{AppState, DeviceConnection};
use tokio::sync::mpsc;

/// Handles an incoming control message from a WebSocket client.
pub fn handle_message(
    state: &AppState,
    tx: &mpsc::UnboundedSender<String>,
    device_id: &mut Option<String>,
    msg: &ControlMessage,
) {
    match msg {
        ControlMessage::Register {
            device_id: id,
            fcm_token,
            paired_device_id,
        } => {
            // Determine pairing: prefer existing in-memory pairing, then
            // fall back to the paired_device_id sent by the client (survives relay restarts).
            let existing_pairing = state
                .devices
                .get(id.as_str())
                .and_then(|d| d.paired_with.clone());
            let effective_pairing = existing_pairing.or(paired_device_id.clone());

            if effective_pairing.is_some() {
                tracing::info!(device_id = %id, paired_with = ?effective_pairing, "Device registered (pairing active)");
            } else {
                tracing::info!(device_id = %id, "Device registered (no pairing)");
            }

            // Clear disconnect time on reconnect
            state.clear_disconnect(id);

            state.devices.insert(
                id.clone(),
                DeviceConnection {
                    device_id: id.clone(),
                    paired_with: effective_pairing.clone(),
                    fcm_token: fcm_token.clone(),
                    tx: tx.clone(),
                },
            );

            // If re-establishing pairing from client hint, also update the partner
            if let Some(ref partner_id) = effective_pairing {
                if let Some(mut partner) = state.devices.get_mut(partner_id) {
                    if partner.paired_with.is_none() {
                        partner.paired_with = Some(id.clone());
                        tracing::info!(device_id = %partner_id, paired_with = %id, "Partner pairing restored");
                    }
                }
            }
            *device_id = Some(id.clone());

            // Send registration confirmation
            send_to(tx, &ControlMessage::Registered {
                device_id: id.clone(),
            });

            // Deliver any buffered messages
            let buffered = drain_buffered_messages(state, id);
            for data in buffered {
                let _ = tx.send(data);
            }
        }

        ControlMessage::CreatePairingCode => {
            let Some(id) = device_id.as_ref() else {
                send_to(tx, &ControlMessage::Error {
                    code: "not_registered".to_string(),
                    message: "Not registered. Send a Register message first.".to_string(),
                });
                return;
            };
            let code = create_pairing_code(state, id);
            tracing::info!(device_id = %id, code = %code, "Pairing code created");
            send_to(tx, &ControlMessage::PairingCode { code });
        }

        ControlMessage::PairWithCode { code, public_key } => {
            tracing::info!(has_public_key = public_key.is_some(), "PairWithCode received");
            let Some(my_id) = device_id.as_ref() else {
                send_to(tx, &ControlMessage::Error {
                    code: "not_registered".to_string(),
                    message: "Not registered. Send a Register message first.".to_string(),
                });
                return;
            };

            // Check if code exists before consuming it (to distinguish invalid vs expired)
            let code_exists = state.pairing_codes.contains_key(code.as_str());

            match validate_pairing_code(state, code) {
                Some(other_id) => {
                    tracing::info!(device_a = %my_id, device_b = %other_id, "Devices paired");

                    // Link both devices
                    if let Some(mut d) = state.devices.get_mut(my_id) {
                        d.paired_with = Some(other_id.clone());
                    }
                    if let Some(mut d) = state.devices.get_mut(&other_id) {
                        d.paired_with = Some(my_id.clone());
                    }

                    // Notify the pairing initiator (app) — no key needed, app has daemon's key from QR
                    send_to(tx, &ControlMessage::Paired {
                        paired_with: other_id.clone(),
                        public_key: None,
                    });
                    // Notify the code creator (daemon) — forward the app's public key
                    send_to_device(state, &other_id, &ControlMessage::Paired {
                        paired_with: my_id.clone(),
                        public_key: public_key.clone(),
                    });
                }
                None => {
                    if code_exists {
                        // Code existed but was expired
                        send_to(tx, &ControlMessage::Error {
                            code: "pairing_expired".to_string(),
                            message: "Pairing code expired. Generate a new one.".to_string(),
                        });
                    } else {
                        send_to(tx, &ControlMessage::Error {
                            code: "pairing_invalid".to_string(),
                            message: "Invalid pairing code.".to_string(),
                        });
                    }
                }
            }
        }

        ControlMessage::Relay { payload } => {
            let Some(my_id) = device_id.as_ref() else {
                send_to(tx, &ControlMessage::Error {
                    code: "not_registered".to_string(),
                    message: "Not registered. Send a Register message first.".to_string(),
                });
                return;
            };

            // Look up paired device
            let target_id = state
                .devices
                .get(my_id)
                .and_then(|d| d.paired_with.clone());

            match target_id {
                Some(target_id) => {
                    let payload_str = serde_json::to_string(payload).unwrap();

                    // Try to send directly; buffer if offline
                    let sent = state
                        .devices
                        .get(&target_id)
                        .map(|d| d.tx.send(payload_str.clone()).is_ok())
                        .unwrap_or(false);

                    if !sent {
                        tracing::debug!(
                            target = %target_id,
                            "Target offline, buffering message"
                        );
                        let buffer_was_full = buffer_message(state, &target_id, payload_str);
                        if buffer_was_full {
                            send_to(tx, &ControlMessage::Error {
                                code: "buffer_full".to_string(),
                                message: "Message buffer full. Some older messages may be lost.".to_string(),
                            });
                        } else {
                            send_to(tx, &ControlMessage::Error {
                                code: "peer_offline".to_string(),
                                message: "Paired device is offline. Message buffered.".to_string(),
                            });
                        }
                    }
                }
                None => {
                    send_to(tx, &ControlMessage::Error {
                        code: "not_paired".to_string(),
                        message: "No paired device. Re-pair to continue.".to_string(),
                    });
                }
            }
        }

        // Server-to-client messages — ignore if received from client
        ControlMessage::Registered { .. }
        | ControlMessage::PairingCode { .. }
        | ControlMessage::Paired { .. }
        | ControlMessage::KeyExchange { .. }
        | ControlMessage::Error { .. } => {}
    }
}

fn send_to(tx: &mpsc::UnboundedSender<String>, msg: &ControlMessage) {
    let json = serde_json::to_string(msg).unwrap();
    let _ = tx.send(json);
}

fn send_to_device(state: &AppState, device_id: &str, msg: &ControlMessage) {
    let json = serde_json::to_string(msg).unwrap();
    if let Some(device) = state.devices.get(device_id) {
        let _ = device.tx.send(json);
    }
}
