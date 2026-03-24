use std::path::PathBuf;
use std::process::Command;

use dialoguer::{Confirm, Input};

use crate::config;

const SERVICE_NAME: &str = "ferlay";

/// Interactive setup wizard: configure relay, pair, install systemd service.
pub async fn run_setup() {
    println!("── Ferlay Setup ──\n");

    // Step 1: Relay URL
    let current_cfg = config::load();
    let relay_url: String = Input::new()
        .with_prompt("Relay server URL")
        .default(current_cfg.relay_url.clone())
        .interact_text()
        .unwrap();

    config::set_relay_url(&relay_url);
    println!();

    // Step 2: Pairing
    println!("Starting pairing flow — scan the QR code with the Ferlay app.\n");
    run_pairing_flow(&relay_url).await;

    // Step 3: Systemd service
    println!();
    if Confirm::new()
        .with_prompt("Enable Ferlay daemon to start automatically on login?")
        .default(true)
        .interact()
        .unwrap()
    {
        install_systemd_service();
    }

    println!("\nSetup complete!");
}

/// Re-pair: stop service, run pairing, restart service.
pub async fn run_pair() {
    let cfg = config::load();

    // Stop the service if running so we can bind to the same ports
    let was_running = stop_service();

    println!("Starting pairing flow — scan the QR code with the Ferlay app.\n");
    run_pairing_flow(&cfg.relay_url).await;

    // Restart service if it was running
    if was_running {
        println!("\nRestarting daemon service...");
        start_service();
    }
}

async fn run_pairing_flow(relay_url: &str) {
    let cfg = config::load();

    // Run the full daemon pairing sequence (reuses the existing daemon::run logic
    // but only the pairing part, then exits)
    use tokio::sync::mpsc;
    use furlay_shared::messages::ControlMessage;
    use crate::{pairing, relay};

    let (outgoing_tx, outgoing_rx) = mpsc::unbounded_channel::<String>();
    let (incoming_tx, mut incoming_rx) = mpsc::unbounded_channel::<String>();

    let relay_url_clone = relay_url.to_string();
    tokio::spawn(async move {
        relay::connection_loop(relay_url_clone, outgoing_rx, incoming_tx).await;
    });

    // Register
    let register = ControlMessage::Register {
        device_id: cfg.device_id.clone(),
        fcm_token: None,
        paired_device_id: cfg.paired_device_id.clone(),
    };
    let _ = outgoing_tx.send(serde_json::to_string(&register).unwrap());

    // Wait for registration
    loop {
        let Some(raw) = incoming_rx.recv().await else {
            eprintln!("Error: relay connection closed before registration");
            return;
        };
        match serde_json::from_str::<ControlMessage>(&raw) {
            Ok(ControlMessage::Registered { device_id }) => {
                tracing::info!(device_id = %device_id, "Registered with relay");
                break;
            }
            Ok(ControlMessage::Error { code, message }) => {
                eprintln!("Registration failed [{code}]: {message}");
                return;
            }
            _ => continue,
        }
    }

    // Run pairing
    match pairing::run_pairing(relay_url, &cfg.device_id, &outgoing_tx, &mut incoming_rx).await {
        Ok(crypto) => {
            // Verify encryption
            if let Err(e) = crate::daemon::verify_encryption(&crypto, &outgoing_tx, &mut incoming_rx).await {
                eprintln!("Encryption verification failed: {e}");
                return;
            }
            println!("Pairing and encryption verified successfully!");
        }
        Err(e) => {
            eprintln!("Pairing failed: {e}");
        }
    }
}

fn service_dir() -> PathBuf {
    dirs::home_dir()
        .unwrap()
        .join(".config/systemd/user")
}

fn daemon_binary_path() -> PathBuf {
    // Prefer the installed location, fall back to current binary
    let installed = dirs::home_dir().unwrap().join(".local/bin/ferlay");
    if installed.exists() {
        installed
    } else {
        std::env::current_exe().unwrap_or_else(|_| PathBuf::from("ferlay"))
    }
}

fn install_systemd_service() {
    let dir = service_dir();
    if let Err(e) = std::fs::create_dir_all(&dir) {
        eprintln!("Failed to create systemd user dir: {e}");
        return;
    }

    let bin = daemon_binary_path();
    let service_content = format!(
        r#"[Unit]
Description=Ferlay Daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart={bin} daemon
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
"#,
        bin = bin.display()
    );

    let service_path = dir.join(format!("{SERVICE_NAME}.service"));
    if let Err(e) = std::fs::write(&service_path, &service_content) {
        eprintln!("Failed to write service file: {e}");
        return;
    }
    println!("Installed service: {}", service_path.display());

    // Reload and enable
    let _ = Command::new("systemctl")
        .args(["--user", "daemon-reload"])
        .status();

    let status = Command::new("systemctl")
        .args(["--user", "enable", "--now", &format!("{SERVICE_NAME}.service")])
        .status();

    match status {
        Ok(s) if s.success() => {
            println!("Daemon service enabled and started.");
        }
        _ => {
            eprintln!("Failed to enable service. You can start it manually:");
            eprintln!("  systemctl --user enable --now {SERVICE_NAME}.service");
        }
    }
}

fn stop_service() -> bool {
    let status = Command::new("systemctl")
        .args(["--user", "is-active", "--quiet", &format!("{SERVICE_NAME}.service")])
        .status();

    let was_running = status.map(|s| s.success()).unwrap_or(false);

    if was_running {
        println!("Stopping daemon service...");
        let _ = Command::new("systemctl")
            .args(["--user", "stop", &format!("{SERVICE_NAME}.service")])
            .status();
        // Give it a moment to release ports
        std::thread::sleep(std::time::Duration::from_secs(1));
    }

    was_running
}

fn start_service() {
    let _ = Command::new("systemctl")
        .args(["--user", "start", &format!("{SERVICE_NAME}.service")])
        .status();
    println!("Daemon service started.");
}
