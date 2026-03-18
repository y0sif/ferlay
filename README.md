# Furlay

Mobile-native remote control for CLI AI agents. Start and manage coding sessions from your phone, anywhere.

## Architecture

Furlay has three components:

- **Relay** (`relay/`) — Rust WebSocket server that routes messages between daemon and mobile app
- **Daemon** (`daemon/`) — Rust CLI that runs on your machine, manages Claude Code sessions
- **App** (`app/`) — Flutter mobile app for starting and controlling sessions from your phone

All Rust crates share types via the `shared/` library.

## Project Structure

```
furlay/
├── Cargo.toml        # Workspace: relay, daemon, shared
├── shared/           # Shared message types and protocol definitions
├── relay/            # WebSocket relay server
├── daemon/           # CLI daemon (connects to relay, spawns sessions)
├── app/              # Flutter mobile app
└── README.md
```

## Quick Start

### Relay Server

```sh
cargo run -p furlay-relay
```

The relay listens on `0.0.0.0:8080` by default. Configure with environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8080` | Listen port |
| `RUST_LOG` | `furlay_relay=info` | Log level |
| `FCM_SERVER_KEY` | — | Optional, for push notifications |

### Health Check

```sh
curl http://localhost:8080/health
```

## Self-Hosting

The relay is designed to be self-hostable:

```sh
# Binary
cargo install furlay-relay

# Docker
docker build -t furlay-relay relay/
docker run -d -p 8080:8080 furlay-relay
```

No database, no external dependencies — just the binary.

## Development

```sh
# Build everything
cargo build

# Run tests
cargo test

# Run relay in debug mode
RUST_LOG=furlay_relay=debug cargo run -p furlay-relay
```

## License

TBD
