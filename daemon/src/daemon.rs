use axum::{routing::get, Json, Router};
use std::sync::Arc;
use tokio::sync::mpsc;

use ferlay_shared::messages::ControlMessage;

use crate::config::Config;
use crate::crypto::CryptoState;
use crate::messages::AppMessage;
use crate::session::SessionManager;
use crate::{pairing, relay};

/// Runs the main daemon loop: connects to relay, handles commands, manages sessions.
/// If not yet paired (or --re-pair is set), runs the pairing flow first.
/// Otherwise, reuses saved encryption key and skips pairing.
pub async fn run(config: Config, relay_url: String, re_pair: bool) {
    // Channels bridging relay WebSocket ↔ daemon logic
    let (outgoing_tx, outgoing_rx) = mpsc::unbounded_channel::<String>();
    let (incoming_tx, mut incoming_rx) = mpsc::unbounded_channel::<String>();

    // Spawn relay connection in background
    let relay_url_clone = relay_url.clone();
    tokio::spawn(async move {
        relay::connection_loop(relay_url_clone, outgoing_rx, incoming_tx).await;
    });

    // Register with relay (include paired device ID to restore pairing after relay restart)
    let register = ControlMessage::Register {
        device_id: config.device_id.clone(),
        fcm_token: None,
        paired_device_id: config.paired_device_id.clone(),
    };
    let _ = outgoing_tx.send(serde_json::to_string(&register).unwrap());

    // Spawn local health server
    let health_sessions = std::sync::Arc::new(tokio::sync::Mutex::new(Vec::new()));
    let health_sessions_clone = health_sessions.clone();
    tokio::spawn(async move {
        run_health_server(health_sessions_clone).await;
    });

    // Wait for registration confirmation
    tracing::info!("Waiting for relay registration...");
    loop {
        let Some(raw) = incoming_rx.recv().await else {
            tracing::error!("Relay connection closed before registration");
            return;
        };
        match serde_json::from_str::<ControlMessage>(&raw) {
            Ok(ControlMessage::Registered { device_id }) => {
                tracing::info!(device_id = %device_id, "Registered with relay");
                break;
            }
            Ok(ControlMessage::Error { code, message }) => {
                tracing::error!(code = %code, error = %message, "Registration failed");
                return;
            }
            _ => continue,
        }
    }

    // Try to load saved encryption key (skip pairing if valid key exists)
    let need_pairing = re_pair || CryptoState::load_key().is_none();

    let crypto = if !need_pairing {
        let saved_crypto = CryptoState::load_key().unwrap();
        tracing::info!("Loaded saved encryption key, skipping pairing flow");
        println!("Using saved encryption key (use --re-pair to force new pairing)");
        Arc::new(saved_crypto)
    } else {
        if re_pair {
            tracing::info!("--re-pair flag set, forcing new pairing");
            println!("Forcing new pairing...");
        } else {
            tracing::info!("No saved encryption key found, starting pairing flow");
        }

        // Run pairing flow with key exchange (encryption is mandatory)
        match pairing::run_pairing(&relay_url, &config.device_id, &outgoing_tx, &mut incoming_rx).await
        {
            Ok(crypto) => {
                tracing::info!("Pairing complete with E2E encryption");
                Arc::new(crypto)
            }
            Err(e) => {
                tracing::error!(error = %e, "Pairing failed");
                return;
            }
        }
    };

    // Run encryption verification if we just paired (not when using saved key)
    if need_pairing {
        if let Err(e) = verify_encryption(&crypto, &outgoing_tx, &mut incoming_rx).await {
            tracing::error!(error = %e, "Encryption verification failed");
            return;
        }
        tracing::info!("Encryption verified successfully");
    }

    let crypto = Some(crypto);

    // Main message loop
    let mut session_manager = SessionManager::new(outgoing_tx.clone(), crypto.clone());

    tracing::info!("Daemon running. Waiting for commands...");

    while let Some(raw) = incoming_rx.recv().await {
        // Handle reconnection sentinel from relay connection loop
        if raw == relay::RECONNECTED_SENTINEL {
            tracing::info!("Relay reconnected, re-registering...");
            let register = ControlMessage::Register {
                device_id: config.device_id.clone(),
                fcm_token: None,
                paired_device_id: config.paired_device_id.clone(),
            };
            let _ = outgoing_tx.send(serde_json::to_string(&register).unwrap());

            // Wait for registration confirmation before resuming
            loop {
                let Some(reg_raw) = incoming_rx.recv().await else {
                    tracing::error!("Relay connection closed during re-registration");
                    continue;
                };
                match serde_json::from_str::<ControlMessage>(&reg_raw) {
                    Ok(ControlMessage::Registered { device_id }) => {
                        tracing::info!(device_id = %device_id, "Re-registered with relay after reconnect");
                        // Re-send current session states so the app knows what's running
                        let sessions = session_manager.list();
                        session_manager.send_sessions_list(sessions);
                        break;
                    }
                    Ok(ControlMessage::Error { code, message }) => {
                        tracing::error!(code = %code, error = %message, "Re-registration failed");
                        break;
                    }
                    _ => continue,
                }
            }
            continue;
        }

        // Try as ControlMessage first (pairing, etc. — never encrypted)
        if let Ok(ctrl) = serde_json::from_str::<ControlMessage>(&raw) {
            match ctrl {
                ControlMessage::Paired { paired_with, .. } => {
                    tracing::info!(paired_with = %paired_with, "Device paired");
                    continue;
                }
                ControlMessage::Error { code, message } => {
                    tracing::warn!(code = %code, error = %message, "Relay error");
                    continue;
                }
                _ => {}
            }
        }

        // All relay messages must be encrypted — no plaintext fallback
        if let Some(ref crypto) = crypto {
            if let Ok(serde_json::Value::String(encrypted)) =
                serde_json::from_str::<serde_json::Value>(&raw)
            {
                match crypto.decrypt(&encrypted) {
                    Ok(plaintext) => {
                        let plaintext_str = String::from_utf8_lossy(&plaintext);
                        match serde_json::from_str::<AppMessage>(&plaintext_str) {
                            Ok(app_msg) => {
                                handle_app_message(
                                    &mut session_manager,
                                    app_msg,
                                    &health_sessions,
                                )
                                .await;
                                continue;
                            }
                            Err(e) => {
                                tracing::warn!(error = %e, "Decrypted payload is not a valid AppMessage, dropping");
                            }
                        }
                    }
                    Err(e) => {
                        tracing::warn!(error = %e, "Decryption failed, dropping message (no plaintext fallback)");
                    }
                }
            } else {
                tracing::debug!(raw = %raw, "Unhandled non-string message");
            }
        } else {
            tracing::warn!("Received relay message but no encryption key established, dropping");
        }
    }

    tracing::info!("Relay connection permanently lost. Daemon exiting.");
}

/// Sends an encrypted challenge and waits for the app to echo it back.
/// This verifies both sides derived the same AES key.
pub async fn verify_encryption(
    crypto: &CryptoState,
    outgoing_tx: &mpsc::UnboundedSender<String>,
    incoming_rx: &mut mpsc::UnboundedReceiver<String>,
) -> Result<(), String> {
    // Generate random challenge
    let mut challenge_bytes = [0u8; 32];
    rand::fill(&mut challenge_bytes);
    let challenge: String = challenge_bytes.iter().map(|b| format!("{:02x}", b)).collect();

    // Send encrypted challenge
    let msg = AppMessage::EncryptionVerify {
        challenge: challenge.clone(),
    };
    let plaintext = serde_json::to_string(&msg).unwrap();
    let encrypted = crypto
        .encrypt(plaintext.as_bytes())
        .map_err(|e| format!("Failed to encrypt challenge: {e}"))?;

    let control = ferlay_shared::messages::ControlMessage::Relay {
        payload: serde_json::Value::String(encrypted),
    };
    outgoing_tx
        .send(serde_json::to_string(&control).unwrap())
        .map_err(|e| format!("Failed to send challenge: {e}"))?;

    tracing::info!("Sent encryption verification challenge, waiting for ack...");

    // Wait for ack with timeout
    let timeout = tokio::time::Duration::from_secs(30);
    let result = tokio::time::timeout(timeout, async {
        loop {
            let raw = incoming_rx
                .recv()
                .await
                .ok_or_else(|| "Relay connection closed".to_string())?;

            // Try to decrypt as encrypted payload
            if let Ok(serde_json::Value::String(encrypted)) =
                serde_json::from_str::<serde_json::Value>(&raw)
            {
                if let Ok(plaintext_bytes) = crypto.decrypt(&encrypted) {
                    let plaintext_str = String::from_utf8_lossy(&plaintext_bytes);
                    if let Ok(AppMessage::EncryptionVerifyAck {
                        challenge: ack_challenge,
                    }) = serde_json::from_str::<AppMessage>(&plaintext_str)
                    {
                        if ack_challenge == challenge {
                            return Ok(());
                        } else {
                            return Err("Challenge mismatch — keys differ".to_string());
                        }
                    }
                }
            }
            // Ignore non-matching messages (e.g. control messages during verification)
        }
    })
    .await;

    match result {
        Ok(inner) => inner,
        Err(_) => Err("Encryption verification timed out after 30s".to_string()),
    }
}

async fn handle_app_message(
    session_manager: &mut SessionManager,
    msg: AppMessage,
    health_sessions: &std::sync::Arc<tokio::sync::Mutex<Vec<crate::messages::SessionInfo>>>,
) {
    match msg {
        AppMessage::StartSession { directory, name, permission_mode, worktree } => {
            session_manager.start(directory, name, permission_mode, worktree).await;
        }
        AppMessage::StopSession { session_id } => {
            session_manager.stop(&session_id).await;
        }
        AppMessage::ListSessions => {
            let sessions = session_manager.list();
            // Update health endpoint data
            *health_sessions.lock().await = sessions.clone();
            // Send list back via relay
            session_manager.send_sessions_list(sessions);
        }
        AppMessage::Ping { timestamp } => {
            // Respond with Pong carrying the same timestamp
            session_manager.send_message(&AppMessage::Pong { timestamp });
        }
        // These are outgoing messages or handled elsewhere — ignore if received
        AppMessage::SessionReady { .. }
        | AppMessage::SessionStatus { .. }
        | AppMessage::SessionsList { .. }
        | AppMessage::KeyExchange { .. }
        | AppMessage::EncryptionVerify { .. }
        | AppMessage::EncryptionVerifyAck { .. }
        | AppMessage::Pong { .. } => {}
    }
}

async fn run_health_server(
    sessions: std::sync::Arc<tokio::sync::Mutex<Vec<crate::messages::SessionInfo>>>,
) {
    let app = Router::new()
        .route("/health", get(|| async { "ok" }))
        .route(
            "/sessions",
            get(move || {
                let sessions = sessions.clone();
                async move {
                    let list = sessions.lock().await.clone();
                    Json(list)
                }
            }),
        );

    let addr = "127.0.0.1:9876";
    match tokio::net::TcpListener::bind(addr).await {
        Ok(listener) => {
            tracing::info!(addr = addr, "Health server listening");
            axum::serve(listener, app).await.ok();
        }
        Err(e) => {
            tracing::warn!(error = %e, "Failed to start health server (port 9876 may be in use)");
        }
    }
}
