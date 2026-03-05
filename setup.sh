#!/bin/bash
set -e

# 🐳 Lightsail Node Deployer - frps + Nginx Proxy Manager

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${CYAN}[setup]${NC} $1"; }
err() { echo -e "${RED}[setup]${NC} $1" >&2; }

usage() {
    cat <<EOF
🐳 Lightsail Node Deployer

Usage: $0 [OPTIONS]

Options:
    --frps-token TOKEN      Token for frps authentication (required for frps)
    --frps-port PORT        Port for frps (default: 6819)
    --npm-email EMAIL       Admin email for Nginx Proxy Manager
    --npm-password PASS     Admin password for Nginx Proxy Manager
    --skip-frps             Skip frps installation
    --skip-npm              Skip Nginx Proxy Manager installation
    --skip-swap             Skip swap setup
    --swap-size SIZE        Swap file size (default: 4G)
    -h, --help              Show this help

Examples:
    # Interactive mode (will prompt for values)
    $0

    # Full automated setup
    $0 --frps-token mysecrettoken --npm-email admin@example.com --npm-password mypassword

    # Only install frps
    $0 --frps-token mysecrettoken --skip-npm

    # Only install NPM
    $0 --npm-email admin@example.com --npm-password mypassword --skip-frps
EOF
    exit 0
}

# Defaults
SKIP_FRPS=false
SKIP_NPM=false
SKIP_SWAP=false
export FRPS_PORT="${FRPS_PORT:-6819}"
export SWAP_SIZE="${SWAP_SIZE:-4G}"

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --frps-token) export FRPS_TOKEN="$2"; shift 2 ;;
        --frps-port) export FRPS_PORT="$2"; shift 2 ;;
        --npm-email) export NPM_EMAIL="$2"; shift 2 ;;
        --npm-password) export NPM_PASSWORD="$2"; shift 2 ;;
        --skip-frps) SKIP_FRPS=true; shift ;;
        --skip-npm) SKIP_NPM=true; shift ;;
        --skip-swap) SKIP_SWAP=true; shift ;;
        --swap-size) export SWAP_SIZE="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) err "Unknown option: $1"; usage ;;
    esac
done

log "🐳 Starting Lightsail Node Deployer..."

# Update system
log "Updating system packages..."
sudo apt-get update -qq

# Setup swap
if [ "$SKIP_SWAP" = false ]; then
    log "Setting up ${SWAP_SIZE} swap..."
    bash "$SCRIPT_DIR/scripts/setup-swap.sh"
else
    log "Skipping swap setup"
fi

# Install frps
if [ "$SKIP_FRPS" = false ]; then
    log "Installing frps..."
    bash "$SCRIPT_DIR/scripts/install-frps.sh"
else
    log "Skipping frps installation"
fi

# Install NPM
if [ "$SKIP_NPM" = false ]; then
    log "Installing Nginx Proxy Manager..."
    bash "$SCRIPT_DIR/scripts/install-npm.sh"
else
    log "Skipping Nginx Proxy Manager installation"
fi

log "🎉 Setup complete!"
echo ""
echo -e "${GREEN}Summary:${NC}"
[ "$SKIP_SWAP" = false ] && echo "  • Swap: ${SWAP_SIZE}"
[ "$SKIP_FRPS" = false ] && echo "  • frps running on port $FRPS_PORT"
[ "$SKIP_NPM" = false ] && echo "  • Nginx Proxy Manager at http://<your-ip>:81"
echo ""
echo -e "${YELLOW}Remember to open these ports in Lightsail firewall:${NC}"
[ "$SKIP_FRPS" = false ] && echo "  • $FRPS_PORT (TCP) - frps"
[ "$SKIP_NPM" = false ] && echo "  • 80 (TCP) - HTTP"
[ "$SKIP_NPM" = false ] && echo "  • 81 (TCP) - NPM Admin"
[ "$SKIP_NPM" = false ] && echo "  • 443 (TCP) - HTTPS"

