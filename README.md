# Ferlay

Mobile-native remote control for Claude Code. Start and manage coding sessions from your phone, anywhere. Install the daemon on your computer, scan a QR code with the app, and control Claude Code sessions remotely.

## Quick Start

```sh
# 1. Install the daemon
curl -sSL https://get.ferlay.dev | sh

# 2. Start the daemon
ferlay daemon

# 3. Scan the QR code with the Ferlay app

# 4. Tap "New Session" in the app and start coding!
```

See the full [Quick Start Guide](docs/quick-start.md) for background service setup and configuration.

## How It Works

Ferlay has three components:

- **Daemon** (`daemon/`) -- Runs on your computer. Manages Claude Code sessions and connects to the relay.
- **Relay** (`relay/`) -- WebSocket server that routes encrypted messages between daemon and app.
- **App** (`app/`) -- Flutter mobile app for starting and controlling sessions from your phone.

All communication is end-to-end encrypted (X25519 key exchange + AES-256-GCM).

## Deployment Modes

| Mode | Setup | Use Case |
|------|-------|----------|
| **Hosted relay** (default) | Install daemon, scan QR | Most users -- zero config |
| **Self-hosted relay** | Run your own relay server | Full control over infrastructure |
| **Local mode** | `ferlay daemon --local` | Development, same LAN |

## Install

### Linux / macOS

```sh
curl -sSL https://get.ferlay.dev | sh
```

### Windows (PowerShell)

```powershell
irm https://get.ferlay.dev/windows | iex
```

### From source

```sh
cargo install --path daemon
```

## Architecture

```
Phone (App)  <-->  Relay (WebSocket)  <-->  Daemon (your machine)
                                               |
                                          Claude Code
```

All Rust crates share types via the `shared/` library.

## Project Structure

```
ferlay/
├── daemon/           # CLI daemon (connects to relay, spawns sessions)
├── relay/            # WebSocket relay server
├── app/              # Flutter mobile app
├── shared/           # Shared message types and protocol definitions
├── scripts/          # Install scripts (install.sh, install.ps1)
├── deploy/           # Service files (systemd, launchd)
└── docs/             # Documentation
```

## Self-Hosting the Relay

```sh
# Docker
docker build -t ferlay-relay relay/
docker run -d -p 8080:8080 ferlay-relay

# Binary
cargo run -p furlay-relay
```

Then point the daemon at your relay:

```sh
ferlay config set relay-url wss://my-relay.example.com/ws
```

No database, no external dependencies -- just the binary.

## Development

```sh
# Build everything
cargo build

# Run tests
cargo test

# Run relay in debug mode
RUST_LOG=furlay_relay=debug cargo run -p furlay-relay

# Run daemon in local mode (with local relay)
./scripts/ferlay-local.sh
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run `cargo test` and `cargo clippy`
5. Submit a pull request

## License

TBD
