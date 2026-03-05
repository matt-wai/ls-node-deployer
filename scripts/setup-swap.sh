#!/bin/bash
set -e

# 🐳 Swap file setup

SWAP_SIZE="${SWAP_SIZE:-4G}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[swap]${NC} $1"; }
warn() { echo -e "${YELLOW}[swap]${NC} $1"; }
err() { echo -e "${RED}[swap]${NC} $1" >&2; }

if swapon --show | grep -q '/swapfile'; then
    CURRENT=$(swapon --show=SIZE --noheadings | head -1 | tr -d ' ')
    warn "Swap already active (/swapfile, size: $CURRENT)"
    warn "To resize: sudo swapoff /swapfile && sudo rm /swapfile, then re-run"
    exit 0
fi

log "Creating ${SWAP_SIZE} swap file..."
sudo fallocate -l "$SWAP_SIZE" /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

if ! grep -q '/swapfile' /etc/fstab; then
    log "Adding swap to /etc/fstab for persistence..."
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
fi

log "Tuning swappiness to 10..."
sudo sysctl vm.swappiness=10
if ! grep -q 'vm.swappiness' /etc/sysctl.conf; then
    echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf > /dev/null
fi

log "✅ Swap configured:"
swapon --show
free -h | grep -i swap
