use axum::{routing::get, Json, Router};
use std::sync::Arc;
use tokio::sync::mpsc;

use furlay_shared::messages::ControlMessage;

use crate::config::Config;
use crate::crypto::CryptoState;
use crate::messages::AppMessage;
use crate::session::SessionManager;
use crate::{pairing, relay};

/// Runs the main daemon loop: connects to relay, handles commands, manages sessions.
/// If not yet paired, runs the pairing flow first on the same connection.
pub async fn run(config: Config, relay_url: String) {
    // Channels bridging relay WebSocket ↔ daemon logic
    let (outgoing_tx, outgoing_rx) = mpsc::unbounded_channel::<String>();
    let (incoming_tx, mut incoming_rx) = mpsc::unbounded_channel::<String>();

    // Spawn relay connection in background
    let relay_url_clone = relay_url.clone();
    tokio::spawn(async move {
        relay::connection_loop(relay_url_clone, outgoing_rx, incoming_tx).await;
    });

    // Register with relay
    let register = ControlMessage::Register {
        device_id: config.device_id.clone(),
        fcm_token: None,
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
            Ok(ControlMessage::Error { message }) => {
                tracing::error!(error = %message, "Registration failed");
                return;
            }
            _ => continue,
        }
    }

    // Run pairing flow with key exchange (encryption is mandatory)
    tracing::info!("Starting pairing flow...");
    let crypto = match pairing::run_pairing(&relay_url, &config.device_id, &outgoing_tx, &mut incoming_rx).await
    {
        Ok(crypto) => {
            tracing::info!("Pairing complete with E2E encryption");
            Arc::new(crypto)
        }
        Err(e) => {
            tracing::error!(error = %e, "Pairing failed");
            return;
        }
    };

    // Encryption verification handshake
    if let Err(e) = verify_encryption(&crypto, &outgoing_tx, &mut incoming_rx).await {
        tracing::error!(error = %e, "Encryption verification failed");
        return;
    }
    tracing::info!("Encryption verified successfully");

    let crypto = Some(crypto);

    // Main message loop
    let mut session_manager = SessionManager::new(outgoing_tx.clone(), crypto.clone());

    tracing::info!("Daemon running. Waiting for commands...");

    while let Some(raw) = incoming_rx.recv().await {
        // Try as ControlMessage first (pairing, etc. — never encrypted)
        if let Ok(ctrl) = serde_json::from_str::<ControlMessage>(&raw) {
            match ctrl {
                ControlMessage::Paired { paired_with, .. } => {
                    tracing::info!(paired_with = %paired_with, "Device paired");
                    continue;
                }
                ControlMessage::Error { message } => {
                    tracing::warn!(error = %message, "Relay error");
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

    tracing::info!("Relay connection lost. Daemon exiting.");
}

/// Sends an encrypted challenge and waits for the app to echo it back.
/// This verifies both sides derived the same AES key.
async fn verify_encryption(
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

    let control = furlay_shared::messages::ControlMessage::Relay {
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
        AppMessage::StartSession { directory, name } => {
            session_manager.start(directory, name).await;
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
        // These are outgoing messages or handled elsewhere — ignore if received
        AppMessage::SessionReady { .. }
        | AppMessage::SessionStatus { .. }
        | AppMessage::SessionsList { .. }
        | AppMessage::KeyExchange { .. }
        | AppMessage::EncryptionVerify { .. }
        | AppMessage::EncryptionVerifyAck { .. } => {}
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
