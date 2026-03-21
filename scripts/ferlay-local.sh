#!/usr/bin/env bash
set -e

# --- Detect repo root ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Check prerequisites ---
if ! command -v cargo &>/dev/null; then
    echo "Error: cargo is not installed. Install Rust via https://rustup.rs"
    exit 1
fi

# --- Locate binaries ---
RELAY_BIN="${REPO_ROOT}/target/release/furlay-relay"
DAEMON_BIN="${REPO_ROOT}/target/release/furlay-daemon"

if [ ! -f "$RELAY_BIN" ] || [ ! -f "$DAEMON_BIN" ]; then
    echo "Binaries not found. Building from source..."
    cargo build --release --manifest-path "$REPO_ROOT/Cargo.toml" -p furlay-relay -p furlay-daemon
fi

# --- Detect LAN IP ---
LAN_IP=""
if command -v ip &>/dev/null; then
    LAN_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}')
fi
if [ -z "$LAN_IP" ] && command -v hostname &>/dev/null; then
    LAN_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
fi
# macOS fallback
if [ -z "$LAN_IP" ] && command -v ifconfig &>/dev/null; then
    LAN_IP=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}')
fi
if [ -z "$LAN_IP" ]; then
    LAN_IP="127.0.0.1"
fi

RELAY_URL="ws://${LAN_IP}:8080/ws"
PID_FILE="${REPO_ROOT}/.ferlay-local.pids"

echo ""
echo "=== Ferlay Local Mode ==="
echo "Relay URL: ${RELAY_URL}"
echo "LAN IP:    ${LAN_IP}"
echo ""
echo "Point your Ferlay app at: ${RELAY_URL}"
echo ""

# --- Cleanup function ---
cleanup() {
    echo ""
    echo "Shutting down Ferlay..."
    if [ -n "$DAEMON_PID" ]; then
        kill "$DAEMON_PID" 2>/dev/null || true
        wait "$DAEMON_PID" 2>/dev/null || true
    fi
    if [ -n "$RELAY_PID" ]; then
        kill "$RELAY_PID" 2>/dev/null || true
        wait "$RELAY_PID" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
    echo "Ferlay stopped."
}
trap cleanup INT TERM EXIT

# --- Start relay in background ---
echo "Starting relay on port 8080..."
PORT=8080 RUST_LOG=furlay_relay=info "$RELAY_BIN" &
RELAY_PID=$!

# Give relay time to bind
sleep 1

# Check relay started
if ! kill -0 "$RELAY_PID" 2>/dev/null; then
    echo "Error: Relay failed to start. Is port 8080 already in use?"
    exit 1
fi

# Save PIDs
echo "relay=$RELAY_PID" > "$PID_FILE"

# --- Start daemon (foreground — shows QR code for pairing) ---
echo "Starting daemon..."
echo ""
RUST_LOG=furlay_daemon=info "$DAEMON_BIN" daemon --local &
DAEMON_PID=$!
echo "daemon=$DAEMON_PID" >> "$PID_FILE"

echo ""
echo "Ferlay is running. Press Ctrl+C to stop."
echo ""

# Wait for either process to exit
wait -n "$RELAY_PID" "$DAEMON_PID" 2>/dev/null || true
