#!/usr/bin/env bash
# 🐳 Install the weekly Nginx Proxy Manager auto-updater (idempotent).

set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="/etc/npm-autoupdate.conf"

log() { echo "[install-npm-autoupdate] $*"; }

for f in npm-autoupdate.sh npm-autoupdate.service npm-autoupdate.timer; do
    [ -f "$SRC_DIR/$f" ] || { echo "missing $SRC_DIR/$f" >&2; exit 1; }
done

log "installing /usr/local/sbin/npm-autoupdate.sh"
sudo install -m 0755 "$SRC_DIR/npm-autoupdate.sh" /usr/local/sbin/npm-autoupdate.sh

if [ ! -f "$CONF" ]; then
    log "writing default config $CONF"
    sudo tee "$CONF" > /dev/null <<'EOF'
# Nginx Proxy Manager auto-updater configuration.
NPM_DIR="/home/ubuntu/nginx-proxy-manager"
CONTAINER="nginx-proxy-manager"
IMAGE_REPO="jc21/nginx-proxy-manager"

# Patch-level policy: 0 = newest release, 1 = one behind, 2 = two behind.
# Kept at 0 because only the 2.15.x line carries OpenSSL 3.5.x / OpenResty
# 1.29.x; older tags stay on the Debian 12 OpenSSL 3.0.x base that external
# scanners flag.
TAG_OFFSET=0

# Enabled public proxy hosts. Verification is relative to a pre-change
# baseline, so upstreams that are already down do not block an upgrade.
HEALTH_HOSTS="api.orion.aliasintelligence.com drx.scout.aliasintelligence.com api.deployer.aliasintelligence.com nginx.scout.aliasintelligence.com"

BACKUP_DIR="/var/backups/npm"
KEEP_BACKUPS=6
HEALTH_TIMEOUT=240
EOF
else
    log "config $CONF already exists — leaving it alone"
fi

log "installing systemd units"
sudo install -m 0644 "$SRC_DIR/npm-autoupdate.service" /etc/systemd/system/npm-autoupdate.service
sudo install -m 0644 "$SRC_DIR/npm-autoupdate.timer" /etc/systemd/system/npm-autoupdate.timer

sudo mkdir -p /var/backups/npm /var/lib/npm-autoupdate

sudo systemctl daemon-reload
sudo systemctl enable --now npm-autoupdate.timer

log "verifying with a dry run"
sudo /usr/local/sbin/npm-autoupdate.sh --dry-run

log "✅ installed. Next run:"
systemctl list-timers npm-autoupdate.timer --all --no-pager
log "Run now:      sudo systemctl start npm-autoupdate.service"
log "Watch logs:   journalctl -u npm-autoupdate.service -f"
log "Last result:  cat /var/lib/npm-autoupdate/state.json"
