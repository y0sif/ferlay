# Contributing to Ferlay

Thanks for considering a contribution. This document covers the basics.

## Ways to Contribute

### Testing

The most impactful thing you can do right now is test Ferlay on your setup and report what works and what doesn't.

**Daemon — platforms that need testing:**
- Linux: Ubuntu, Fedora, Debian, NixOS, Arch
- macOS: Intel and Apple Silicon
- Windows: 10 and 11

**App — areas that need testing:**
- QR code pairing reliability
- Session start/stop lifecycle
- Reconnection after network interruptions
- Background behavior (does the connection stay alive?)

When reporting, include:
- OS + version
- Architecture (x86_64 / aarch64)
- How you installed (script, source, etc.)
- What worked, what didn't
- Daemon logs (`RUST_LOG=debug ferlay daemon`)

### Bug Reports

Open an issue with:
- Steps to reproduce
- Expected vs actual behavior
- Daemon logs
- Your environment (OS, architecture, install method)

### Code Contributions

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/my-thing`)
3. Make your changes
4. Run the checks: `cargo fmt`, `cargo clippy --all-targets -- -D warnings`, `cargo test`
5. Commit with a clear message
6. Open a PR

## Development Setup

### Prerequisites

- [Rust toolchain](https://rustup.rs) (stable)
- [Flutter](https://flutter.dev/docs/get-started/install) (for the mobile app)

### Build and Test

```sh
# Build all Rust crates
cargo build

# Run tests
cargo test

# Lint
cargo clippy --all-targets -- -D warnings
cargo fmt --check
```

### Running Locally

```sh
# Terminal 1: start local relay
RUST_LOG=furlay_relay=debug cargo run -p furlay-relay

# Terminal 2: start daemon pointing to local relay
RUST_LOG=furlay_daemon=debug cargo run -p furlay-daemon -- daemon --relay ws://localhost:8080/ws

# Or use the convenience script that does both:
./scripts/ferlay-local.sh
```

### Project Structure

```
daemon/src/
  main.rs        CLI entry point (clap)
  daemon.rs      Main daemon loop (relay connection, session management)
  config.rs      Configuration (~/.config/ferlay/)
  session.rs     SessionManager (spawn/stop/monitor Claude CLI)
  pairing.rs     X25519 key exchange + QR code display
  relay.rs       WebSocket connection to relay
  crypto.rs      AES-256-GCM encryption/decryption
  messages.rs    App message types

relay/src/
  main.rs        WebSocket server (axum)
  ws.rs          WebSocket handler
  router.rs      Message routing (pairing, relay)
  state.rs       In-memory device registry

shared/src/
  messages.rs    ControlMessage enum (wire protocol)

app/lib/
  providers/     Riverpod state management
  services/      Crypto, relay, storage
  screens/       UI screens
```

## Code Style

- Use `tracing` for all logging (not `println!` or `log`)
- Run `cargo fmt` before committing
- No warnings from `cargo clippy --all-targets -- -D warnings`
- Keep dependencies minimal

## Commit Messages

Keep them concise. First line is a summary (imperative mood), then a blank line, then details if needed.

```
Add Windows Task Scheduler setup to install script

Detects Windows and creates a scheduled task for auto-start.
Tested on Windows 11.
```
