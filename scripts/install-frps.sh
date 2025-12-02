#!/bin/bash
set -e

# 🐳 frps installer - auto-detect arch, download latest, servicize

FRPS_PORT="${FRPS_PORT:-6819}"
INSTALL_DIR="/opt/frps"
CONFIG_FILE="/etc/frps/frps.toml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[frps]${NC} $1"; }
warn() { echo -e "${YELLOW}[frps]${NC} $1"; }
err() { echo -e "${RED}[frps]${NC} $1" >&2; }

# Check for token
if [ -z "$FRPS_TOKEN" ]; then
    read -p "Enter frps token: " FRPS_TOKEN
    if [ -z "$FRPS_TOKEN" ]; then
        err "Token is required!"
        exit 1
    fi
fi

# Detect architecture
detect_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l|armhf) echo "arm" ;;
        i386|i686) echo "386" ;;
        *) err "Unsupported architecture: $arch"; exit 1 ;;
    esac
}

ARCH=$(detect_arch)
log "Detected architecture: $ARCH"

# Get latest version
log "Fetching latest frp release..."
LATEST_URL=$(curl -sI https://github.com/fatedier/frp/releases/latest | grep -i "location:" | sed 's/.*tag\/\(.*\)\r/\1/')
VERSION=$(echo "$LATEST_URL" | tr -d '[:space:]')
log "Latest version: $VERSION"

# Download
DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/${VERSION}/frp_${VERSION#v}_linux_${ARCH}.tar.gz"
log "Downloading from: $DOWNLOAD_URL"

TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"
curl -sL "$DOWNLOAD_URL" -o frp.tar.gz
tar -xzf frp.tar.gz

# Install
log "Installing frps..."
sudo mkdir -p "$INSTALL_DIR" /etc/frps
sudo cp frp_*/frps "$INSTALL_DIR/"
sudo chmod +x "$INSTALL_DIR/frps"

# Create config
log "Creating config at $CONFIG_FILE..."
sudo tee "$CONFIG_FILE" > /dev/null <<EOF
bindPort = $FRPS_PORT
auth.method = "token"
auth.token = "$FRPS_TOKEN"

# Dashboard (optional, uncomment to enable)
# webServer.addr = "0.0.0.0"
# webServer.port = 7500
# webServer.user = "admin"
# webServer.password = "admin"

log.to = "/var/log/frps.log"
log.level = "info"
EOF

# Create systemd service
log "Creating systemd service..."
sudo tee /etc/systemd/system/frps.service > /dev/null <<EOF
[Unit]
Description=frps server
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/frps -c $CONFIG_FILE
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable frps
sudo systemctl start frps

# Cleanup
rm -rf "$TMP_DIR"

log "✅ frps installed and running on port $FRPS_PORT"
log "Check status: sudo systemctl status frps"

