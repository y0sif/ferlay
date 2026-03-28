use std::path::PathBuf;
use std::process::Command;

use dialoguer::{Confirm, Input};

use crate::config;

const SERVICE_NAME: &str = "ferlay";

/// Interactive setup wizard: configure relay, pair, install background service.
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

    // Step 3: Background service
    println!();
    if Confirm::new()
        .with_prompt("Enable Ferlay daemon to start automatically on login?")
        .default(true)
        .interact()
        .unwrap()
    {
        install_background_service();
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
    use ferlay_shared::messages::ControlMessage;
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

// ── Platform-specific background service installation ──

fn daemon_binary_path() -> PathBuf {
    // Prefer the installed location, fall back to current binary
    let installed = dirs::home_dir().unwrap().join(".local/bin/ferlay");
    if installed.exists() {
        return installed;
    }

    #[cfg(target_os = "windows")]
    {
        let win_installed = PathBuf::from(std::env::var("LOCALAPPDATA").unwrap_or_default())
            .join("Ferlay")
            .join("ferlay.exe");
        if win_installed.exists() {
            return win_installed;
        }
    }

    std::env::current_exe().unwrap_or_else(|_| PathBuf::from("ferlay"))
}

fn install_background_service() {
    #[cfg(target_os = "linux")]
    install_systemd_service();

    #[cfg(target_os = "macos")]
    install_launchd_service();

    #[cfg(target_os = "windows")]
    install_windows_task();
}

#[cfg(target_os = "linux")]
fn install_systemd_service() {
    let dir = dirs::home_dir()
        .unwrap()
        .join(".config/systemd/user");

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
            println!("Daemon enabled and started.");
        }
        _ => {
            eprintln!("Failed to enable service. Start manually:");
            eprintln!("  systemctl --user enable --now {SERVICE_NAME}.service");
        }
    }
}

#[cfg(target_os = "macos")]
fn install_launchd_service() {
    let bin = daemon_binary_path();
    let plist_content = format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>dev.ferlay.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>{bin}</string>
        <string>daemon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>NetworkState</key>
        <true/>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/ferlay-daemon.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/ferlay-daemon.log</string>
</dict>
</plist>"#,
        bin = bin.display()
    );

    let launch_agents = dirs::home_dir().unwrap().join("Library/LaunchAgents");
    std::fs::create_dir_all(&launch_agents).ok();
    let plist_path = launch_agents.join("dev.ferlay.daemon.plist");

    if let Err(e) = std::fs::write(&plist_path, &plist_content) {
        eprintln!("Failed to write plist: {e}");
        return;
    }
    println!("Installed plist: {}", plist_path.display());

    let status = Command::new("launchctl")
        .args(["load", &plist_path.to_string_lossy()])
        .status();

    match status {
        Ok(s) if s.success() => {
            println!("Daemon loaded and will start on login.");
        }
        _ => {
            eprintln!("Failed to load service. Start manually:");
            eprintln!("  launchctl load {}", plist_path.display());
        }
    }
}

#[cfg(target_os = "windows")]
fn install_windows_task() {
    let bin = daemon_binary_path();
    let status = Command::new("schtasks")
        .args([
            "/Create",
            "/SC", "ONLOGON",
            "/TN", "Ferlay",
            "/TR", &format!("\"{}\" daemon", bin.display()),
            "/F",
        ])
        .status();

    match status {
        Ok(s) if s.success() => {
            println!("Scheduled task created. Daemon will start on login.");
            // Start it now
            let _ = Command::new("schtasks")
                .args(["/Run", "/TN", "Ferlay"])
                .status();
            println!("Daemon started.");
        }
        _ => {
            eprintln!("Failed to create scheduled task. Start manually:");
            eprintln!("  ferlay daemon");
        }
    }
}

fn stop_service() -> bool {
    #[cfg(target_os = "linux")]
    {
        let status = Command::new("systemctl")
            .args(["--user", "is-active", "--quiet", &format!("{SERVICE_NAME}.service")])
            .status();

        let was_running = status.map(|s| s.success()).unwrap_or(false);

        if was_running {
            println!("Stopping daemon service...");
            let _ = Command::new("systemctl")
                .args(["--user", "stop", &format!("{SERVICE_NAME}.service")])
                .status();
            std::thread::sleep(std::time::Duration::from_secs(1));
        }

        was_running
    }

    #[cfg(target_os = "macos")]
    {
        let plist_path = dirs::home_dir()
            .unwrap()
            .join("Library/LaunchAgents/dev.ferlay.daemon.plist");

        if plist_path.exists() {
            println!("Unloading daemon service...");
            let _ = Command::new("launchctl")
                .args(["unload", &plist_path.to_string_lossy()])
                .status();
            std::thread::sleep(std::time::Duration::from_secs(1));
            true
        } else {
            false
        }
    }

    #[cfg(target_os = "windows")]
    {
        let output = Command::new("schtasks")
            .args(["/Query", "/TN", "Ferlay"])
            .output();

        let was_running = output.map(|o| o.status.success()).unwrap_or(false);

        if was_running {
            println!("Stopping daemon task...");
            let _ = Command::new("schtasks")
                .args(["/End", "/TN", "Ferlay"])
                .status();
            std::thread::sleep(std::time::Duration::from_secs(1));
        }

        was_running
    }
}

fn start_service() {
    #[cfg(target_os = "linux")]
    {
        let _ = Command::new("systemctl")
            .args(["--user", "start", &format!("{SERVICE_NAME}.service")])
            .status();
        println!("Daemon service started.");
    }

    #[cfg(target_os = "macos")]
    {
        let plist_path = dirs::home_dir()
            .unwrap()
            .join("Library/LaunchAgents/dev.ferlay.daemon.plist");
        let _ = Command::new("launchctl")
            .args(["load", &plist_path.to_string_lossy()])
            .status();
        println!("Daemon service started.");
    }

    #[cfg(target_os = "windows")]
    {
        let _ = Command::new("schtasks")
            .args(["/Run", "/TN", "Ferlay"])
            .status();
        println!("Daemon task started.");
    }
}
