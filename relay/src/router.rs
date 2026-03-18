use crate::buffer::{buffer_message, drain_buffered_messages};
use furlay_shared::messages::ControlMessage;
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
        } => {
            tracing::info!(device_id = %id, "Device registered");

            state.devices.insert(
                id.clone(),
                DeviceConnection {
                    device_id: id.clone(),
                    paired_with: None,
                    fcm_token: fcm_token.clone(),
                    tx: tx.clone(),
                },
            );
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
                    message: "not registered".to_string(),
                });
                return;
            };
            let code = create_pairing_code(state, id);
            tracing::info!(device_id = %id, code = %code, "Pairing code created");
            send_to(tx, &ControlMessage::PairingCode { code });
        }

        ControlMessage::PairWithCode { code } => {
            let Some(my_id) = device_id.as_ref() else {
                send_to(tx, &ControlMessage::Error {
                    message: "not registered".to_string(),
                });
                return;
            };

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

                    // Notify both sides
                    send_to(tx, &ControlMessage::Paired {
                        paired_with: other_id.clone(),
                    });
                    send_to_device(state, &other_id, &ControlMessage::Paired {
                        paired_with: my_id.clone(),
                    });
                }
                None => {
                    send_to(tx, &ControlMessage::Error {
                        message: "invalid or expired pairing code".to_string(),
                    });
                }
            }
        }

        ControlMessage::Relay { payload } => {
            let Some(my_id) = device_id.as_ref() else {
                send_to(tx, &ControlMessage::Error {
                    message: "not registered".to_string(),
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
                        buffer_message(state, &target_id, payload_str);
                    }
                }
                None => {
                    send_to(tx, &ControlMessage::Error {
                        message: "not paired with any device".to_string(),
                    });
                }
            }
        }

        // Server-to-client messages — ignore if received from client
        ControlMessage::Registered { .. }
        | ControlMessage::PairingCode { .. }
        | ControlMessage::Paired { .. }
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
