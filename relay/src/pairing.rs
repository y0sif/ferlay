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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pairing_code_is_six_digits() {
        let code = generate_pairing_code();
        assert_eq!(code.len(), 6);
        assert!(code.chars().all(|c| c.is_ascii_digit()));
    }

    #[test]
    fn create_and_validate_pairing_code() {
        let state = AppState::new();
        let code = create_pairing_code(&state, "device-1");
        let result = validate_pairing_code(&state, &code);
        assert_eq!(result, Some("device-1".to_string()));
    }

    #[test]
    fn pairing_code_consumed_after_validation() {
        let state = AppState::new();
        let code = create_pairing_code(&state, "device-1");
        let _ = validate_pairing_code(&state, &code);
        // Second validation should fail — code was consumed
        assert_eq!(validate_pairing_code(&state, &code), None);
    }

    #[test]
    fn invalid_code_returns_none() {
        let state = AppState::new();
        assert_eq!(validate_pairing_code(&state, "BADCODE"), None);
    }

    #[test]
    fn expired_code_returns_none() {
        let state = AppState::new();
        // Insert a code that's already expired
        state.pairing_codes.insert(
            "expired".to_string(),
            PairingEntry {
                device_id: "dev".to_string(),
                expires_at: Instant::now() - Duration::from_secs(1),
            },
        );
        assert_eq!(validate_pairing_code(&state, "expired"), None);
    }
}
