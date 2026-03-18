use axum::{routing::get, Json, Router};
use tokio::sync::mpsc;

use furlay_shared::messages::ControlMessage;

use crate::config::Config;
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

    // Run pairing flow on this connection (reuses the daemon's relay registration)
    tracing::info!("Starting pairing flow...");
    match pairing::run_pairing(&relay_url, &config.device_id, &outgoing_tx, &mut incoming_rx).await
    {
        Ok(()) => {
            tracing::info!("Pairing complete, entering main loop");
        }
        Err(e) => {
            tracing::error!(error = %e, "Pairing failed");
            return;
        }
    }

    // Main message loop
    let mut session_manager = SessionManager::new(outgoing_tx.clone());

    tracing::info!("Daemon running. Waiting for commands...");

    while let Some(raw) = incoming_rx.recv().await {
        // Try as ControlMessage first (pairing, etc.)
        if let Ok(ctrl) = serde_json::from_str::<ControlMessage>(&raw) {
            match ctrl {
                ControlMessage::Paired { paired_with } => {
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

        // Try as AppMessage (commands from phone, delivered as relay payload)
        match serde_json::from_str::<AppMessage>(&raw) {
            Ok(app_msg) => {
                handle_app_message(&mut session_manager, app_msg, &health_sessions).await;
            }
            Err(e) => {
                tracing::debug!(error = %e, raw = %raw, "Unhandled message");
            }
        }
    }

    tracing::info!("Relay connection lost. Daemon exiting.");
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
        // These are outgoing messages — ignore if received
        AppMessage::SessionReady { .. }
        | AppMessage::SessionStatus { .. }
        | AppMessage::SessionsList { .. } => {}
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
