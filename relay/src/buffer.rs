use crate::state::{AppState, BufferedMessage};
use std::sync::Arc;
use std::time::{Duration, Instant};

const BUFFER_TTL: Duration = Duration::from_secs(3600); // 1 hour
const CLEANUP_INTERVAL: Duration = Duration::from_secs(60);

/// Buffers a message for an offline device.
pub fn buffer_message(state: &AppState, device_id: &str, data: String) {
    state
        .message_buffer
        .entry(device_id.to_string())
        .or_default()
        .push(BufferedMessage {
            data,
            timestamp: Instant::now(),
        });
}

/// Drains buffered messages for a device that just came online.
pub fn drain_buffered_messages(state: &AppState, device_id: &str) -> Vec<String> {
    state
        .message_buffer
        .remove(device_id)
        .map(|(_, msgs)| msgs.into_iter().map(|m| m.data).collect())
        .unwrap_or_default()
}

/// Background task that cleans up expired pairing codes and buffered messages.
pub async fn cleanup_task(state: Arc<AppState>) {
    let mut interval = tokio::time::interval(CLEANUP_INTERVAL);
    loop {
        interval.tick().await;
        let now = Instant::now();

        // Remove expired pairing codes
        state.pairing_codes.retain(|_, entry| entry.expires_at > now);

        // Remove expired buffered messages
        for mut entry in state.message_buffer.iter_mut() {
            entry
                .value_mut()
                .retain(|m| now.duration_since(m.timestamp) < BUFFER_TTL);
        }
        state.message_buffer.retain(|_, msgs| !msgs.is_empty());
    }
}
