#!/bin/sh
set -e

# Ferlay Daemon Installer
# Usage: curl -sSL https://ferlay.dev/install.sh | sh

REPO="y0sif/ferlay"
BINARY_NAME="ferlay"
INSTALL_DIR="${FERLAY_INSTALL_DIR:-$HOME/.local/bin}"

echo ""
echo "  Ferlay Daemon Installer"
echo "  ========================"
echo ""

# --- Detect OS ---
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$OS" in
  linux)  PLATFORM="linux" ;;
  darwin) PLATFORM="macos" ;;
  *)
    echo "Error: Unsupported OS: $OS"
    echo "  Windows users: use the PowerShell installer."
    echo "  See: https://github.com/$REPO#installation"
    exit 1
    ;;
esac

# --- Detect architecture ---
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) ARCH="x86_64" ;;
  aarch64|arm64) ARCH="aarch64" ;;
  *)
    echo "Error: Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

ASSET_NAME="ferlay-daemon-${PLATFORM}-${ARCH}"
echo "  Detected: ${PLATFORM} / ${ARCH}"

# --- Find download tool ---
if command -v curl >/dev/null 2>&1; then
  DOWNLOAD="curl -fsSL"
  DOWNLOAD_OUT="curl -fsSL -o"
elif command -v wget >/dev/null 2>&1; then
  DOWNLOAD="wget -qO-"
  DOWNLOAD_OUT="wget -qO"
else
  echo "Error: Neither curl nor wget found. Please install one and retry."
  exit 1
fi

# --- Get latest release tag ---
echo "  Fetching latest release..."
RELEASE_URL="https://api.github.com/repos/${REPO}/releases/latest"
TAG=$($DOWNLOAD "$RELEASE_URL" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"//;s/".*//')

if [ -z "$TAG" ]; then
  echo "Error: Could not determine latest release. Check https://github.com/$REPO/releases"
  exit 1
fi

echo "  Latest release: $TAG"

# --- Download binary ---
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET_NAME}.tar.gz"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "  Downloading ${ASSET_NAME}.tar.gz ..."
$DOWNLOAD_OUT "$TMPDIR/ferlay.tar.gz" "$DOWNLOAD_URL"

# --- Extract ---
tar xzf "$TMPDIR/ferlay.tar.gz" -C "$TMPDIR"

# --- Install ---
mkdir -p "$INSTALL_DIR"
mv "$TMPDIR/$ASSET_NAME" "$INSTALL_DIR/$BINARY_NAME"
chmod +x "$INSTALL_DIR/$BINARY_NAME"

echo "  Installed to: $INSTALL_DIR/$BINARY_NAME"

# --- Check PATH ---
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *)
    echo ""
    echo "  WARNING: $INSTALL_DIR is not in your PATH."
    echo ""
    echo "  Add it to your shell config:"
    echo ""
    echo "    bash/zsh:  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
    echo "    fish:      fish_add_path ~/.local/bin"
    echo ""
    # Add to PATH for the rest of this script
    export PATH="$INSTALL_DIR:$PATH"
    ;;
esac

echo ""
echo "  Ferlay installed successfully!"
echo ""

# --- Run interactive setup (relay config, pairing, background service) ---
if [ -t 0 ] || [ -e /dev/tty ]; then
  echo "  Running setup..."
  echo ""
  "$INSTALL_DIR/$BINARY_NAME" setup < /dev/tty
else
  echo "  Next steps:"
  echo "    Run: ferlay setup"
  echo ""
  echo "  This will configure the relay, pair with your phone,"
  echo "  and start the daemon as a background service."
fi
