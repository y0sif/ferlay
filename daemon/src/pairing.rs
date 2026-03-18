use furlay_shared::messages::ControlMessage;
use tokio::sync::mpsc;

/// Runs the pairing flow: requests a pairing code from relay and displays it as QR.
pub async fn run_pairing(
    relay_url: &str,
    _device_id: &str,
    relay_tx: &mpsc::UnboundedSender<String>,
    incoming_rx: &mut mpsc::UnboundedReceiver<String>,
) -> Result<(), String> {
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

    // Display QR code
    display_qr(relay_url, &code);

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
                return Ok(());
            }
            Ok(ControlMessage::Error { message }) => {
                return Err(format!("Pairing failed: {message}"));
            }
            _ => continue,
        }
    }
}

fn display_qr(relay_url: &str, code: &str) {
    let data = serde_json::json!({
        "relay": relay_url,
        "code": code,
    });
    let qr_data = serde_json::to_string(&data).unwrap();

    println!();
    if let Err(e) = qr2term::print_qr(&qr_data) {
        tracing::warn!(error = %e, "Failed to display QR code");
    }
    println!("\nPairing code: {code}");
    println!("Scan with Ferlay app or enter code manually");
}
