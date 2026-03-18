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
}

impl AppState {
    pub fn new() -> Self {
        Self {
            devices: DashMap::new(),
            pairing_codes: DashMap::new(),
            message_buffer: DashMap::new(),
        }
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
