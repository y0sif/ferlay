```
  __          _
 / _| ___ _ _| | __ _ _  _
|  _|/ -_) '_| |/ _` | || |
|_|  \___|_| |_|\__,_|\_, |
                       |__/

  your ai agent, always within reach.
```

# Ferlay

[![Release](https://img.shields.io/github/v/release/y0sif/ferlay?label=release)](https://github.com/y0sif/ferlay/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/y0sif/ferlay/release.yml?label=CI)](https://github.com/y0sif/ferlay/actions)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Remote control for Claude Code from your phone.** Start, manage, and approve AI coding sessions from anywhere — all end-to-end encrypted.

Install the daemon on your computer, scan a QR code with the mobile app, and you're in control. No port forwarding, no SSH tunnels, no VPN.

---

## Quick Start

```sh
# Install the daemon
curl -sSL https://raw.githubusercontent.com/y0sif/ferlay/main/scripts/install.sh | sh

# Start it
ferlay daemon

# Scan the QR code with the Ferlay app → start coding from your phone
```

---

## Installation

### Linux / macOS

```sh
curl -sSL https://raw.githubusercontent.com/y0sif/ferlay/main/scripts/install.sh | sh
```

<details>
<summary><b>What the installer does</b></summary>

1. Detects your OS (Linux/macOS) and architecture (x86_64/aarch64)
2. Downloads the latest release binary from GitHub
3. Installs to `~/.local/bin/ferlay`
4. Adds to PATH if needed
5. Prints next steps for background service setup

</details>

### Windows

```powershell
irm https://raw.githubusercontent.com/y0sif/ferlay/main/scripts/install.ps1 | iex
```

<details>
<summary><b>What the installer does</b></summary>

1. Detects architecture (x64/ARM64)
2. Downloads the latest release from GitHub
3. Installs to `%LOCALAPPDATA%\Ferlay\ferlay.exe`
4. Adds to user PATH

</details>

### From source

```sh
cargo install --path daemon
```

Requires Rust toolchain. See [rustup.rs](https://rustup.rs) if you don't have it.

---

## Running as a Background Service

The daemon needs to be running for remote control to work. You can run it manually (`ferlay daemon`) or set it up as a background service:

<details>
<summary><b>Linux (systemd)</b></summary>

```sh
# Download the service file
mkdir -p ~/.config/systemd/user
curl -sSL https://raw.githubusercontent.com/y0sif/ferlay/main/deploy/ferlay-daemon.service \
  -o ~/.config/systemd/user/ferlay.service

# Enable and start
systemctl --user daemon-reload
systemctl --user enable --now ferlay

# Check status
systemctl --user status ferlay
```

</details>

<details>
<summary><b>macOS (launchd)</b></summary>

```sh
# Symlink the binary to the standard macOS path (plist expects /usr/local/bin)
sudo ln -sf ~/.local/bin/ferlay /usr/local/bin/ferlay

# Download the plist
curl -sSL https://raw.githubusercontent.com/y0sif/ferlay/main/deploy/dev.ferlay.daemon.plist \
  -o ~/Library/LaunchAgents/dev.ferlay.daemon.plist

# Load and start
launchctl load ~/Library/LaunchAgents/dev.ferlay.daemon.plist

# Check status
launchctl list | grep ferlay
```

> If you installed ferlay elsewhere, edit the plist to update the binary path before loading.

</details>

<details>
<summary><b>Windows (Task Scheduler)</b></summary>

```powershell
# Create a scheduled task that starts ferlay on login
$Action = New-ScheduledTaskAction -Execute "$env:LOCALAPPDATA\Ferlay\ferlay.exe" -Argument "daemon"
$Trigger = New-ScheduledTaskTrigger -AtLogon
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0
Register-ScheduledTask -TaskName "Ferlay" -Action $Action -Trigger $Trigger -Settings $Settings -Description "Ferlay Daemon"

# Start it now
Start-ScheduledTask -TaskName "Ferlay"
```

</details>

---

## How It Works

```
📱 Phone App  ←→  🔄 Relay Server  ←→  🖥️ Daemon  ←→  Claude Code
                  (relay.ferlay.dev)    (your machine)
```

1. **Daemon** runs on your computer, manages Claude Code sessions
2. **Relay** routes encrypted messages between your phone and daemon
3. **App** on your phone — scan QR to pair, tap to start sessions

All communication is **end-to-end encrypted** (X25519 + AES-256-GCM). The relay server cannot read your messages — it only forwards opaque ciphertext.

---

## Deployment Modes

### Default: Hosted Relay

Zero config. Install the daemon, scan the QR code, done. Uses the public relay at `relay.ferlay.dev`.

```sh
ferlay daemon
```

### Self-Hosted Relay

Run your own relay for full infrastructure control. No database, no external dependencies.

```sh
# Option 1: Docker (recommended)
docker run -d -p 8080:8080 ghcr.io/y0sif/ferlay-relay:latest

# Option 2: From source
cargo run -p furlay-relay
```

Then point your daemon at it:

```sh
ferlay config set relay-url wss://your-relay.example.com/ws
```

<details>
<summary><b>Production setup with TLS</b></summary>

The relay needs TLS (`wss://`) in production. Options:

- **Cloudflare Tunnel** — expose `localhost:8080` via a tunnel, Cloudflare handles TLS
- **Caddy reverse proxy** — `deploy/Caddyfile` and `deploy/docker-compose.caddy.yml` provide a ready-made setup with auto-TLS via Let's Encrypt
- **nginx** — example config in `deploy/nginx.conf`

```sh
# Using the Docker Compose setup on your server
git clone https://github.com/y0sif/ferlay
cd ferlay/deploy
docker compose up -d
```

</details>

### Local Mode

For development or same-network use. Starts a local relay and daemon together — no external server needed.

```sh
ferlay daemon --local
```

Or use the dev script which builds and runs everything:

```sh
./scripts/ferlay-local.sh        # Linux/macOS
./scripts/ferlay-local.ps1       # Windows
```

---

## CLI Reference

```
ferlay daemon [--local] [--relay <URL>] [--re-pair]    Start the daemon
ferlay setup                                           Interactive setup
ferlay pair                                            Re-pair with a new phone
ferlay status                                          Check daemon health
ferlay config show                                     Show current configuration
ferlay config set relay-url <URL>                      Change relay server
ferlay config reset                                    Reset to defaults
```

---

## Project Structure

```
ferlay/
├── daemon/       Rust CLI daemon — manages Claude Code sessions
├── relay/        Rust WebSocket relay server
├── app/          Flutter mobile app (Android, iOS)
├── shared/       Shared message types and protocol definitions
├── scripts/      Install scripts (Linux, macOS, Windows)
├── deploy/       Service files (systemd, launchd, Docker, Caddy)
└── site/         Project website (ferlay.dev)
```

---

## Development

```sh
# Build everything
cargo build

# Run tests
cargo test

# Lint
cargo clippy --all-targets -- -D warnings

# Run relay locally with debug logging
RUST_LOG=furlay_relay=debug cargo run -p furlay-relay

# Run daemon + local relay together
./scripts/ferlay-local.sh
```

Flutter app:

```sh
cd app
flutter pub get
flutter run
```

---

## Contributing

The biggest ways to help right now:

1. **Test the daemon** on your OS — Linux distros, macOS versions, Windows. Report what works and what doesn't.
2. **Test the app** — pairing flow, session management, connection stability.
3. **Bug reports** — if pairing fails, sessions don't start, or connections drop, open an issue.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and guidelines.

---

## License

[MIT](LICENSE)
