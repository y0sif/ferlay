use crate::state::{AppState, BufferedMessage};
use std::sync::Arc;
use std::time::{Duration, Instant};

const BUFFER_TTL: Duration = Duration::from_secs(3600); // 1 hour
const CLEANUP_INTERVAL: Duration = Duration::from_secs(60);
const MAX_BUFFER_PER_DEVICE: usize = 100;

/// Buffers a message for an offline device.
/// Returns `true` if buffer was full and oldest message was dropped.
pub fn buffer_message(state: &AppState, device_id: &str, data: String) -> bool {
    let mut entry = state
        .message_buffer
        .entry(device_id.to_string())
        .or_default();
    let buf = entry.value_mut();

    let was_full = buf.len() >= MAX_BUFFER_PER_DEVICE;
    if was_full {
        // Drop oldest message to make room
        buf.remove(0);
        tracing::warn!(
            device_id = %device_id,
            "Buffer full ({MAX_BUFFER_PER_DEVICE}), dropped oldest message"
        );
    }

    buf.push(BufferedMessage {
        data,
        timestamp: Instant::now(),
    });

    was_full
}

/// Drains buffered messages for a device that just came online.
/// Expired messages (older than TTL) are filtered out before delivery.
pub fn drain_buffered_messages(state: &AppState, device_id: &str) -> Vec<String> {
    let now = Instant::now();
    state
        .message_buffer
        .remove(device_id)
        .map(|(_, msgs)| {
            let valid: Vec<String> = msgs
                .into_iter()
                .filter(|m| now.duration_since(m.timestamp) < BUFFER_TTL)
                .map(|m| m.data)
                .collect();
            if !valid.is_empty() {
                tracing::info!(
                    device_id = %device_id,
                    count = valid.len(),
                    "Delivered buffered messages"
                );
            }
            valid
        })
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn buffer_and_drain() {
        let state = AppState::new();
        buffer_message(&state, "dev-1", "msg-1".to_string());
        buffer_message(&state, "dev-1", "msg-2".to_string());

        let msgs = drain_buffered_messages(&state, "dev-1");
        assert_eq!(msgs, vec!["msg-1", "msg-2"]);

        // Buffer should be empty after draining
        let msgs = drain_buffered_messages(&state, "dev-1");
        assert!(msgs.is_empty());
    }

    #[test]
    fn drain_nonexistent_device_returns_empty() {
        let state = AppState::new();
        let msgs = drain_buffered_messages(&state, "ghost");
        assert!(msgs.is_empty());
    }

    #[test]
    fn buffers_are_per_device() {
        let state = AppState::new();
        buffer_message(&state, "dev-1", "a".to_string());
        buffer_message(&state, "dev-2", "b".to_string());

        let msgs1 = drain_buffered_messages(&state, "dev-1");
        assert_eq!(msgs1, vec!["a"]);

        let msgs2 = drain_buffered_messages(&state, "dev-2");
        assert_eq!(msgs2, vec!["b"]);
    }

    #[test]
    fn buffer_limit_drops_oldest() {
        let state = AppState::new();

        // Fill buffer to max
        for i in 0..MAX_BUFFER_PER_DEVICE {
            let was_full = buffer_message(&state, "dev-1", format!("msg-{i}"));
            assert!(!was_full);
        }

        // Next message should drop oldest
        let was_full = buffer_message(&state, "dev-1", "overflow".to_string());
        assert!(was_full);

        let msgs = drain_buffered_messages(&state, "dev-1");
        assert_eq!(msgs.len(), MAX_BUFFER_PER_DEVICE);
        // First message should be msg-1 (msg-0 was dropped)
        assert_eq!(msgs[0], "msg-1");
        // Last message should be the overflow message
        assert_eq!(msgs[msgs.len() - 1], "overflow");
    }

    #[test]
    fn expired_messages_filtered_on_drain() {
        let state = AppState::new();

        // Insert an already-expired message by manipulating the buffer directly
        state
            .message_buffer
            .entry("dev-1".to_string())
            .or_default()
            .push(BufferedMessage {
                data: "old".to_string(),
                timestamp: Instant::now() - Duration::from_secs(7200), // 2 hours ago
            });

        // Insert a fresh message
        buffer_message(&state, "dev-1", "fresh".to_string());

        let msgs = drain_buffered_messages(&state, "dev-1");
        assert_eq!(msgs, vec!["fresh"]);
    }
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
