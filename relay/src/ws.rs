use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        State,
    },
    response::IntoResponse,
};
use futures_util::{SinkExt, StreamExt};
use std::sync::Arc;
use tokio::sync::mpsc;

use furlay_shared::messages::ControlMessage;
use crate::router;
use crate::state::AppState;

pub async fn ws_handler(
    ws: WebSocketUpgrade,
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_socket(socket, state))
}

async fn handle_socket(socket: WebSocket, state: Arc<AppState>) {
    let (mut ws_sender, mut ws_receiver) = socket.split();
    let (tx, mut rx) = mpsc::unbounded_channel::<String>();
    let mut device_id: Option<String> = None;

    // Task: forward messages from mpsc channel → WebSocket
    let send_task = tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            if ws_sender.send(Message::Text(msg.into())).await.is_err() {
                break;
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
            Message::Close(_) => break,
            _ => {} // ignore binary, ping, pong
        }
    }

    // Cleanup on disconnect
    if let Some(id) = &device_id {
        tracing::info!(device_id = %id, "Device disconnected");
        state.devices.remove(id);
    }
    send_task.abort();
}
