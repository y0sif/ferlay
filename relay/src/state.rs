use dashmap::DashMap;
use std::time::Instant;
use tokio::sync::mpsc;

pub struct AppState {
    /// device_id → sender channel (to push messages to that device's WS)
    pub devices: DashMap<String, DeviceConnection>,
    /// pairing_code → PairingEntry
    pub pairing_codes: DashMap<String, PairingEntry>,
    /// device_id → Vec<BufferedMessage> (for offline delivery)
    pub message_buffer: DashMap<String, Vec<BufferedMessage>>,
    /// device_id → last disconnect time (for stale pairing cleanup)
    pub disconnect_times: DashMap<String, Instant>,
    /// When the server was started
    pub start_time: Instant,
}

impl AppState {
    pub fn new() -> Self {
        Self {
            devices: DashMap::new(),
            pairing_codes: DashMap::new(),
            message_buffer: DashMap::new(),
            disconnect_times: DashMap::new(),
            start_time: Instant::now(),
        }
    }

    /// Records when a device disconnects (for stale pairing TTL).
    pub fn record_disconnect(&self, device_id: &str) {
        self.disconnect_times.insert(device_id.to_string(), Instant::now());
    }

    /// Clears disconnect time when a device reconnects.
    pub fn clear_disconnect(&self, device_id: &str) {
        self.disconnect_times.remove(device_id);
    }
}

#[allow(dead_code)]
pub struct DeviceConnection {
    pub device_id: String,
    pub paired_with: Option<String>,
    pub fcm_token: Option<String>,
    pub tx: mpsc::UnboundedSender<String>,
}

pub struct PairingEntry {
    pub device_id: String,
    pub expires_at: Instant,
}

pub struct BufferedMessage {
    pub data: String,
    pub timestamp: Instant,
}
