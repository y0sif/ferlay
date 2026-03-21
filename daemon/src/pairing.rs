use furlay_shared::messages::ControlMessage;
use tokio::sync::mpsc;

use crate::crypto::{self, CryptoState};
use crate::messages::AppMessage;

/// Runs the pairing flow with X25519 key exchange.
///
/// Two key exchange paths:
/// 1. **QR scan**: App's public key arrives inside the `Paired` control message
///    (forwarded by the relay from the `PairWithCode` message) — atomic with pairing.
/// 2. **Manual code entry**: App pairs without a public key. Daemon sends its
///    public key via a `KeyExchange` relay message, app responds with its own
///    `KeyExchange` — one extra round-trip but still gets encryption.
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
            Ok(ControlMessage::Error { code, message }) => {
                return Err(format!("Relay error [{code}]: {message}"));
            }
            _ => continue,
        }
    };

    // Display QR code with public key
    display_qr(relay_url, &code, &public_key_b64);

    // Wait for paired confirmation — the app's public key may or may not be included
    tracing::info!("Waiting for phone to scan QR code...");
    let peer_public = loop {
        let raw = incoming_rx
            .recv()
            .await
            .ok_or_else(|| "Relay connection closed".to_string())?;

        match serde_json::from_str::<ControlMessage>(&raw) {
            Ok(ControlMessage::Paired {
                paired_with,
                public_key: peer_pk_opt,
            }) => {
                tracing::info!(paired_with = %paired_with, has_key = peer_pk_opt.is_some(), "Pairing complete!");
                println!("\nPaired successfully with device {paired_with}");

                // Persist the paired device ID for relay re-pairing on reconnect
                crate::config::set_paired_device_id(&paired_with);

                match peer_pk_opt {
                    Some(pk_b64) => {
                        // QR path: peer included their public key
                        let peer_pk = crypto::decode_public_key(&pk_b64)
                            .map_err(|e| format!("Invalid peer public key: {e}"))?;
                        break peer_pk;
                    }
                    None => {
                        // Manual path: need to exchange keys over relay
                        tracing::info!("No peer key in pairing — starting KeyExchange flow");
                        let peer_pk =
                            key_exchange_flow(&public_key_b64, relay_tx, incoming_rx).await?;
                        break peer_pk;
                    }
                }
            }
            Ok(ControlMessage::Error { message, .. }) => {
                return Err(format!("Pairing failed: {message}"));
            }
            _ => continue,
        }
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

/// Exchanges public keys over relay for manual pairing (no QR).
/// Daemon sends its key first, then waits for the app's key.
async fn key_exchange_flow(
    my_public_key_b64: &str,
    relay_tx: &mpsc::UnboundedSender<String>,
    incoming_rx: &mut mpsc::UnboundedReceiver<String>,
) -> Result<x25519_dalek::PublicKey, String> {
    // Send our public key via relay (unencrypted — encryption not yet established)
    let key_msg = AppMessage::KeyExchange {
        public_key: my_public_key_b64.to_string(),
    };
    let payload = serde_json::to_value(&key_msg).unwrap();
    let control = ControlMessage::Relay { payload };
    relay_tx
        .send(serde_json::to_string(&control).unwrap())
        .map_err(|e| format!("Failed to send KeyExchange: {e}"))?;

    tracing::info!("Sent KeyExchange, waiting for app's public key...");

    // Wait for the app's KeyExchange response with timeout
    let timeout = tokio::time::Duration::from_secs(30);
    let result = tokio::time::timeout(timeout, async {
        loop {
            let raw = incoming_rx
                .recv()
                .await
                .ok_or_else(|| "Relay connection closed".to_string())?;

            // The app's KeyExchange comes as an unencrypted relay payload
            if let Ok(app_msg) = serde_json::from_str::<AppMessage>(&raw) {
                if let AppMessage::KeyExchange { public_key } = app_msg {
                    let peer_pk = crypto::decode_public_key(&public_key)
                        .map_err(|e| format!("Invalid peer public key: {e}"))?;
                    return Ok(peer_pk);
                }
            }

            // Also try parsing as a relay-wrapped message
            if let Ok(ControlMessage::Relay { payload }) =
                serde_json::from_str::<ControlMessage>(&raw)
            {
                if let Ok(app_msg) =
                    serde_json::from_value::<AppMessage>(payload)
                {
                    if let AppMessage::KeyExchange { public_key } = app_msg {
                        let peer_pk = crypto::decode_public_key(&public_key)
                            .map_err(|e| format!("Invalid peer public key: {e}"))?;
                        return Ok(peer_pk);
                    }
                }
            }
        }
    })
    .await;

    match result {
        Ok(inner) => inner,
        Err(_) => Err("KeyExchange timed out after 30s".to_string()),
    }
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
