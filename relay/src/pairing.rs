use crate::state::{AppState, PairingEntry};
use rand::Rng;
use std::time::{Duration, Instant};

const PAIRING_CODE_TTL: Duration = Duration::from_secs(300); // 5 minutes

pub fn generate_pairing_code() -> String {
    let mut rng = rand::rng();
    let code: u32 = rng.random_range(100_000..1_000_000);
    code.to_string()
}

pub fn create_pairing_code(state: &AppState, device_id: &str) -> String {
    let code = generate_pairing_code();
    state.pairing_codes.insert(
        code.clone(),
        PairingEntry {
            device_id: device_id.to_string(),
            expires_at: Instant::now() + PAIRING_CODE_TTL,
        },
    );
    code
}

/// Validates a pairing code and returns the device_id that created it, if valid.
pub fn validate_pairing_code(state: &AppState, code: &str) -> Option<String> {
    let entry = state.pairing_codes.remove(code)?;
    let (_key, entry) = entry;
    if entry.expires_at > Instant::now() {
        Some(entry.device_id)
    } else {
        None
    }
}
