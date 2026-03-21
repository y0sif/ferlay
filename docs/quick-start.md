# Quick Start

## 1. Install the daemon

```sh
curl -sSL https://get.ferlay.dev | sh
```

Or download the binary directly from [GitHub Releases](https://github.com/OWNER/ferlay/releases/latest).

## 2. Start the daemon

```sh
ferlay daemon
```

On first run, a QR code will be displayed in your terminal for pairing.

## 3. Scan the QR code

Open the Ferlay app on your phone and scan the QR code shown in your terminal.

Get the app:
- [Android APK](https://github.com/OWNER/ferlay/releases/latest) (from GitHub Releases)

## 4. Start a session

Tap "New Session" in the app, enter your project directory, and tap Start.
Open the session URL in Claude to begin coding.

---

## Running as a background service

### Linux (systemd)

```sh
mkdir -p ~/.config/systemd/user
cp deploy/ferlay-daemon.service ~/.config/systemd/user/ferlay.service
systemctl --user daemon-reload
systemctl --user enable --now ferlay
```

### macOS (launchd)

```sh
cp deploy/dev.ferlay.daemon.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/dev.ferlay.daemon.plist
```

### Any platform (nohup)

```sh
nohup ferlay daemon > /tmp/ferlay.log 2>&1 &
```

## Configuration

```sh
# Show all config
ferlay config show

# Change relay URL
ferlay config set relay-url wss://my-relay.example.com/ws

# Reset to default hosted relay
ferlay config set relay-url default

# Check version
ferlay --version
```
