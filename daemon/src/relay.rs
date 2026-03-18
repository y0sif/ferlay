use futures_util::{SinkExt, StreamExt};
use tokio::sync::mpsc;
use tokio_tungstenite::{connect_async, tungstenite::Message};

/// Runs the persistent WebSocket connection to the relay server.
/// Automatically reconnects with exponential backoff on disconnection.
///
/// - `outgoing_rx`: messages to send to the relay (from daemon logic)
/// - `incoming_tx`: messages received from the relay (to daemon logic)
pub async fn connection_loop(
    url: String,
    mut outgoing_rx: mpsc::UnboundedReceiver<String>,
    incoming_tx: mpsc::UnboundedSender<String>,
) {
    let mut backoff = 1u64;

    loop {
        tracing::info!(url = %url, "Connecting to relay...");

        match connect_async(&url).await {
            Ok((ws_stream, _)) => {
                tracing::info!("Connected to relay");
                backoff = 1;
                let (mut write, mut read) = ws_stream.split();

                loop {
                    tokio::select! {
                        msg = read.next() => {
                            match msg {
                                Some(Ok(Message::Text(text))) => {
                                    let _ = incoming_tx.send(text.to_string());
                                }
                                Some(Ok(Message::Ping(data))) => {
                                    let _ = write.send(Message::Pong(data)).await;
                                }
                                Some(Ok(Message::Close(_))) | None => {
                                    tracing::warn!("Relay connection closed");
                                    break;
                                }
                                Some(Err(e)) => {
                                    tracing::error!(error = %e, "Relay error");
                                    break;
                                }
                                _ => {}
                            }
                        }
                        Some(msg) = outgoing_rx.recv() => {
                            if write.send(Message::Text(msg.into())).await.is_err() {
                                tracing::error!("Failed to send to relay");
                                break;
                            }
                        }
                    }
                }
            }
            Err(e) => {
                tracing::error!(error = %e, "Failed to connect to relay");
            }
        }

        tracing::info!(seconds = backoff, "Reconnecting in...");
        tokio::time::sleep(std::time::Duration::from_secs(backoff)).await;
        backoff = (backoff * 2).min(30);
    }
}
