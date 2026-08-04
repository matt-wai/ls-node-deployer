#!/usr/bin/env bash
# 🐳 Remove the weekly Nginx Proxy Manager auto-updater.
#
# Leaves the container on whatever tag is currently pinned in the compose file,
# and keeps backups in /var/backups/npm. Pass --purge to drop config + backups.

set -euo pipefail

PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

log() { echo "[uninstall-npm-autoupdate] $*"; }

sudo systemctl disable --now npm-autoupdate.timer 2>/dev/null || true
sudo systemctl stop npm-autoupdate.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/npm-autoupdate.timer /etc/systemd/system/npm-autoupdate.service
sudo systemctl daemon-reload
sudo rm -f /usr/local/sbin/npm-autoupdate.sh

if [ "$PURGE" -eq 1 ]; then
    log "purging config, state and backups"
    sudo rm -f /etc/npm-autoupdate.conf
    sudo rm -rf /var/lib/npm-autoupdate /var/backups/npm
else
    log "kept /etc/npm-autoupdate.conf, /var/lib/npm-autoupdate and /var/backups/npm"
fi

log "✅ uninstalled"
