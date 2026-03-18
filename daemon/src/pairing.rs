use furlay_shared::messages::ControlMessage;
use tokio::sync::mpsc;

use crate::crypto::{self, CryptoState};
use crate::messages::AppMessage;

/// Runs the pairing flow with X25519 key exchange.
/// Returns a CryptoState with the derived AES-256-GCM key.
pub async fn run_pairing(
    relay_url: &str,
    _device_id: &str,
    relay_tx: &mpsc::UnboundedSender<String>,
    incoming_rx: &mut mpsc::UnboundedReceiver<String>,
) -> Result<CryptoState, String> {
    // Generate X25519 keypair for this pairing session
    let (secret, public_key) = crypto::generate_keypair();
    let public_key_b64 = crypto::encode_public_key(&public_key);

    // Request pairing code
    let msg = ControlMessage::CreatePairingCode;
    let json = serde_json::to_string(&msg).unwrap();
    relay_tx
        .send(json)
        .map_err(|e| format!("Failed to send to relay: {e}"))?;

    // Wait for pairing code response
    let code = loop {
        let raw = incoming_rx
            .recv()
            .await
            .ok_or_else(|| "Relay connection closed".to_string())?;

        match serde_json::from_str::<ControlMessage>(&raw) {
            Ok(ControlMessage::PairingCode { code }) => break code,
            Ok(ControlMessage::Error { message }) => {
                return Err(format!("Relay error: {message}"));
            }
            _ => continue,
        }
    };

    // Display QR code with public key
    display_qr(relay_url, &code, &public_key_b64);

    // Wait for paired confirmation
    tracing::info!("Waiting for phone to scan QR code...");
    loop {
        let raw = incoming_rx
            .recv()
            .await
            .ok_or_else(|| "Relay connection closed".to_string())?;

        match serde_json::from_str::<ControlMessage>(&raw) {
            Ok(ControlMessage::Paired { paired_with }) => {
                tracing::info!(paired_with = %paired_with, "Pairing complete!");
                println!("\nPaired successfully with device {paired_with}");
                break;
            }
            Ok(ControlMessage::Error { message }) => {
                return Err(format!("Pairing failed: {message}"));
            }
            _ => continue,
        }
    }

    // Wait for key_exchange message from app (sent as unencrypted relay payload)
    tracing::info!("Waiting for key exchange from app...");
    let peer_public = loop {
        let raw = incoming_rx
            .recv()
            .await
            .ok_or_else(|| "Relay connection closed during key exchange".to_string())?;

        // The relay forwards the payload as a raw JSON string
        if let Ok(AppMessage::KeyExchange { public_key }) = serde_json::from_str::<AppMessage>(&raw)
        {
            let peer_pk = crypto::decode_public_key(&public_key)
                .map_err(|e| format!("Invalid peer public key: {e}"))?;
            break peer_pk;
        }
        // Ignore other messages during key exchange
        continue;
    };

    // Derive shared secret via X25519 ECDH
    let shared_secret = secret.diffie_hellman(&peer_public);
    let crypto_state = CryptoState::from_shared_secret(shared_secret.as_bytes());

    // Persist derived key
    if let Err(e) = crypto_state.save_key() {
        tracing::warn!(error = %e, "Failed to save encryption key (non-fatal)");
    }

    tracing::info!("E2E encryption established");
    println!("E2E encryption established");

    Ok(crypto_state)
}

fn display_qr(relay_url: &str, code: &str, public_key: &str) {
    let data = serde_json::json!({
        "relay": relay_url,
        "code": code,
        "pk": public_key,
    });
    let qr_data = serde_json::to_string(&data).unwrap();

    println!();
    if let Err(e) = qr2term::print_qr(&qr_data) {
        tracing::warn!(error = %e, "Failed to display QR code");
    }
    println!("\nPairing code: {code}");
    println!("Scan with Ferlay app or enter code manually");
}
