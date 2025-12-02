#!/bin/bash
set -e

# 🐳 Nginx Proxy Manager installer with custom credentials

NPM_DIR="/opt/nginx-proxy-manager"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[npm]${NC} $1"; }
warn() { echo -e "${YELLOW}[npm]${NC} $1"; }
err() { echo -e "${RED}[npm]${NC} $1" >&2; }

# Check for required args
if [ -z "$NPM_EMAIL" ]; then
    read -p "Enter admin email: " NPM_EMAIL
    if [ -z "$NPM_EMAIL" ]; then
        err "Admin email is required!"
        exit 1
    fi
fi

if [ -z "$NPM_PASSWORD" ]; then
    read -sp "Enter admin password: " NPM_PASSWORD
    echo
    if [ -z "$NPM_PASSWORD" ]; then
        err "Admin password is required!"
        exit 1
    fi
fi

# Install Docker if not present
if ! command -v docker &> /dev/null; then
    log "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    sudo systemctl enable docker
    sudo systemctl start docker
fi

# Install Docker Compose if not present
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    log "Installing Docker Compose..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
fi

# Create directory
log "Setting up Nginx Proxy Manager..."
sudo mkdir -p "$NPM_DIR/data" "$NPM_DIR/letsencrypt"
cd "$NPM_DIR"

# Create docker-compose.yml
sudo tee docker-compose.yml > /dev/null <<EOF
version: '3.8'
services:
  app:
    image: 'jc21/nginx-proxy-manager:latest'
    restart: unless-stopped
    network_mode: host
    environment:
      INITIAL_ADMIN_EMAIL: "$NPM_EMAIL"
      INITIAL_ADMIN_PASSWORD: "$NPM_PASSWORD"
      DISABLE_IPV6: 'true'
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
    healthcheck:
      test: ["CMD", "/bin/check-health"]
      interval: 10s
      timeout: 3s
EOF

# Start
log "Starting Nginx Proxy Manager..."
if docker compose version &> /dev/null; then
    sudo docker compose up -d
else
    sudo docker-compose up -d
fi

log "✅ Nginx Proxy Manager installed!"
log "Access admin panel at: http://<your-ip>:81"
log "Login with: $NPM_EMAIL"

