use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        State,
    },
    response::IntoResponse,
};
use futures_util::{SinkExt, StreamExt};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::mpsc;

use furlay_shared::messages::ControlMessage;
use crate::router;
use crate::state::AppState;

const PING_INTERVAL: Duration = Duration::from_secs(30);
const PONG_TIMEOUT: Duration = Duration::from_secs(10);

pub async fn ws_handler(
    ws: WebSocketUpgrade,
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_socket(socket, state))
}

async fn handle_socket(socket: WebSocket, state: Arc<AppState>) {
    let (mut ws_sender, mut ws_receiver) = socket.split();
    let (tx, mut rx) = mpsc::unbounded_channel::<String>();
    // Channel for signaling pong received
    let (pong_tx, mut pong_rx) = mpsc::unbounded_channel::<()>();
    let mut device_id: Option<String> = None;

    // Task: forward messages from mpsc channel → WebSocket, and send periodic pings
    let send_task = tokio::spawn(async move {
        let mut ping_interval = tokio::time::interval(PING_INTERVAL);
        // Skip the first immediate tick
        ping_interval.tick().await;

        loop {
            tokio::select! {
                msg = rx.recv() => {
                    match msg {
                        Some(msg) => {
                            if ws_sender.send(Message::Text(msg.into())).await.is_err() {
                                break;
                            }
                        }
                        None => break,
                    }
                }
                _ = ping_interval.tick() => {
                    let ping_data = b"ferlay-ping".to_vec();
                    if ws_sender.send(Message::Ping(ping_data.into())).await.is_err() {
                        tracing::debug!("Failed to send ping, connection dead");
                        break;
                    }

                    // Wait for pong within timeout
                    match tokio::time::timeout(PONG_TIMEOUT, pong_rx.recv()).await {
                        Ok(Some(())) => {
                            // Pong received, all good
                        }
                        _ => {
                            tracing::warn!("No pong received within timeout, closing connection");
                            let _ = ws_sender.send(Message::Close(None)).await;
                            break;
                        }
                    }
                }
            }
        }
    });

    // Main loop: receive messages from WebSocket → dispatch
    while let Some(Ok(msg)) = ws_receiver.next().await {
        match msg {
            Message::Text(text) => {
                let text = text.to_string();
                tracing::debug!(raw = %text, "WS received");
                match serde_json::from_str::<ControlMessage>(&text) {
                    Ok(ctrl_msg) => {
                        router::handle_message(&state, &tx, &mut device_id, &ctrl_msg);
                    }
                    Err(e) => {
                        tracing::warn!(error = %e, "Invalid message received");
                        let err = ControlMessage::Error {
                            code: "invalid_message".to_string(),
                            message: format!("invalid message: {e}"),
                        };
                        let _ = tx.send(serde_json::to_string(&err).unwrap());
                    }
                }
            }
            Message::Pong(_) => {
                // Signal that pong was received
                let _ = pong_tx.send(());
            }
            Message::Close(_) => break,
            _ => {} // ignore binary, ping (handled by axum automatically)
        }
    }

    // Cleanup on disconnect: remove from connections but keep pairing data
    if let Some(id) = &device_id {
        tracing::info!(device_id = %id, "Device disconnected");
        // Record disconnect time for stale pairing cleanup
        state.record_disconnect(id);
        // Remove device connection (but pairing info stays in paired_with of the partner)
        state.devices.remove(id);
    }
    send_task.abort();
}
