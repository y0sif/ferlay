<p align="center">
  <img src="assets/ferlay_logo.png" alt="Ferlay" width="128">
</p>

<h3 align="center">Your AI agent, always within reach.</h3>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
</p>

---

**Remote control for Claude Code from your phone.** Start, manage, and approve AI coding sessions from anywhere, all end-to-end encrypted.

One command to install, pair, and start running. No port forwarding, no SSH tunnels, no VPN.

## Install

### Linux / macOS

```sh
curl -sSL https://ferlay.dev/install.sh | sh
```

### Windows

```powershell
irm https://ferlay.dev/install.ps1 | iex
```

### From source

```sh
cargo install --path daemon
ferlay setup
```

The installer downloads the daemon, then runs `ferlay setup` which walks you through:
1. **Relay configuration** - uses the hosted relay by default, or enter your own URL
2. **Pairing** - displays a QR code, scan it with the Ferlay app
3. **Background service** - installs and starts the daemon (systemd on Linux, launchd on macOS, Task Scheduler on Windows)

After setup, the daemon runs in the background and starts automatically on login. That's it.

---

## How It Works

```
Phone App  <-->  Relay Server  <-->  Daemon  <-->  Claude Code
                 (relay.ferlay.dev)  (your machine)
```

1. **Daemon** runs on your computer, manages Claude Code sessions
2. **Relay** routes encrypted messages between your phone and daemon
3. **App** on your phone - scan QR to pair, tap to start sessions

All communication is **end-to-end encrypted** (X25519 + AES-256-GCM). The relay only forwards opaque ciphertext.

---

<details>
<summary><b>Self-hosted relay</b></summary>

Run your own relay for full infrastructure control. No database, no external dependencies.

```sh
# Docker
docker run -d -p 8080:8080 ghcr.io/y0sif/ferlay-relay:latest

# Or from source
cargo run -p furlay-relay
```

Point your daemon at it:

```sh
ferlay config set relay-url wss://your-relay.example.com/ws
```

For production TLS, the `deploy/` directory has ready-made configs for Cloudflare Tunnel, Caddy (auto-TLS), and nginx.

</details>

<details>
<summary><b>Local mode</b></summary>

For development or same-network use. Runs a local relay and daemon together, no external server.

```sh
ferlay daemon --local
```

Or use the dev script:

```sh
./scripts/ferlay-local.sh        # Linux/macOS
./scripts/ferlay-local.ps1       # Windows
```

</details>

---

## CLI Reference

```
ferlay setup                                           Interactive setup (relay, pairing, auto-start)
ferlay daemon [--local] [--relay <URL>] [--re-pair]    Start the daemon in foreground
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
├── daemon/       Rust CLI daemon - manages Claude Code sessions
├── relay/        Rust WebSocket relay server
├── app/          Flutter mobile app (Android, iOS)
├── shared/       Shared message types and protocol definitions
├── scripts/      Install scripts (Linux, macOS, Windows)
└── deploy/       Service files and deployment configs
```

---

## Development

```sh
cargo build                                             # Build all crates
cargo test                                              # Run tests
cargo clippy --all-targets -- -D warnings               # Lint
RUST_LOG=furlay_relay=debug cargo run -p furlay-relay    # Run relay locally
./scripts/ferlay-local.sh                               # Run daemon + local relay
```

```sh
cd app && flutter pub get && flutter run                # Run the Flutter app
```

---

## Contributing

The biggest ways to help right now:

1. **Test the daemon** on your OS - Linux distros, macOS versions, Windows. Report what works and what doesn't.
2. **Test the app** - pairing flow, session management, connection stability.
3. **Bug reports** - if pairing fails, sessions don't start, or connections drop, open an issue.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and guidelines.

---

## License

[MIT](LICENSE)
