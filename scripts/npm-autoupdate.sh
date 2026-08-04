#!/usr/bin/env bash
# 🐳 Nginx Proxy Manager auto-updater
#
# Resolves the target NPM image tag from Docker Hub, pins it into the compose
# file, redeploys, and verifies the public TLS surface. Rolls back the image
# tag AND the /data + /etc/letsencrypt volumes if verification fails, because
# NPM's SQLite migrations are one-way.
#
# Usage: npm-autoupdate.sh [--dry-run] [--force] [--tag X.Y.Z]

set -euo pipefail

CONF="${NPM_AUTOUPDATE_CONF:-/etc/npm-autoupdate.conf}"

NPM_DIR="/home/ubuntu/nginx-proxy-manager"
CONTAINER="nginx-proxy-manager"
IMAGE_REPO="jc21/nginx-proxy-manager"
# 0 = newest release, 1 = one behind, 2 = two behind.
TAG_OFFSET=0
HEALTH_HOSTS="api.orion.aliasintelligence.com api.scout.aliasintelligence.com drx.scout.aliasintelligence.com api.deployer.aliasintelligence.com nginx.scout.aliasintelligence.com xmas.aliasintelligence.com"
BACKUP_DIR="/var/backups/npm"
KEEP_BACKUPS=6
HEALTH_TIMEOUT=240
STATE_DIR="/var/lib/npm-autoupdate"

# shellcheck source=/dev/null
[ -f "$CONF" ] && . "$CONF"

DRY_RUN=0
FORCE=0
TAG_OVERRIDE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --force)   FORCE=1 ;;
        --tag)     TAG_OVERRIDE="${2:-}"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done

log() { echo "[npm-autoupdate] $(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }
die() { echo "[npm-autoupdate] ERROR $*" >&2; exit 1; }

if docker compose version >/dev/null 2>&1; then
    DC="docker compose"
else
    DC="docker-compose"
fi

COMPOSE="$NPM_DIR/docker-compose.yml"
[ -f "$COMPOSE" ] || die "compose file not found: $COMPOSE"
mkdir -p "$BACKUP_DIR" "$STATE_DIR"

dc() { (cd "$NPM_DIR" && $DC "$@"); }

# --- tag resolution -------------------------------------------------------

resolve_target_tag() {
    python3 - "$IMAGE_REPO" "$TAG_OFFSET" <<'PY'
import json, sys, urllib.request

repo, offset = sys.argv[1], int(sys.argv[2])
url = f"https://hub.docker.com/v2/repositories/{repo}/tags/?page_size=100&ordering=last_updated"
with urllib.request.urlopen(url, timeout=30) as r:
    data = json.load(r)

releases = []
for t in data.get("results", []):
    parts = t["name"].split(".")
    if len(parts) == 3 and all(p.isdigit() for p in parts):
        releases.append(tuple(int(p) for p in parts))

if not releases:
    sys.exit("no semver tags found")

releases = sorted(set(releases), reverse=True)
idx = min(offset, len(releases) - 1)
print(".".join(str(n) for n in releases[idx]))
PY
}

current_tag() {
    sed -n "s|^[[:space:]]*image:[[:space:]]*['\"]\?${IMAGE_REPO}:\([^'\"[:space:]]*\)['\"]\?.*|\1|p" "$COMPOSE" | head -1
}

set_tag() {
    sudo sed -i "s|\(^[[:space:]]*image:[[:space:]]*\).*|\1'${IMAGE_REPO}:$1'|" "$COMPOSE"
}

# --- health probing -------------------------------------------------------

# Emits "host<TAB>code" per line. 000 means TLS/connection failure.
probe_hosts() {
    for h in $HEALTH_HOSTS; do
        # curl still emits %{http_code} (000) on failure, so don't append a second value.
        code=$(curl -o /dev/null -sS --max-time 15 -w '%{http_code}' "https://$h/" 2>/dev/null || true)
        [ -n "$code" ] || code=000
        printf '%s\t%s\n' "$h" "$code"
    done
}

wait_container_healthy() {
    local waited=0
    while [ "$waited" -lt "$HEALTH_TIMEOUT" ]; do
        status=$(sudo docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$CONTAINER" 2>/dev/null || echo missing)
        case "$status" in
            healthy|running) log "container status: $status (${waited}s)"; return 0 ;;
            unhealthy)       log "container unhealthy at ${waited}s" ;;
        esac
        sleep 5
        waited=$((waited + 5))
    done
    log "container did not reach healthy within ${HEALTH_TIMEOUT}s (last: ${status:-unknown})"
    return 1
}

# A host regresses if it answered before the change but stopped answering after.
# Absolute status codes are not asserted: some upstreams behind frps return 502
# independently of this box.
compare_health() {
    local before="$1" after="$2" regressions=0
    while IFS=$'\t' read -r host pre; do
        post=$(awk -F'\t' -v h="$host" '$1==h {print $2}' "$after")
        if [ "$pre" != "000" ] && { [ "$post" = "000" ] || [ -z "$post" ]; }; then
            log "REGRESSION $host: $pre -> ${post:-missing}"
            regressions=$((regressions + 1))
        else
            log "ok $host: $pre -> ${post:-missing}"
        fi
    done < "$before"
    [ "$regressions" -eq 0 ]
}

# --- backup / rollback ----------------------------------------------------

backup() {
    local archive="$BACKUP_DIR/npm-$1-$(date -u +%Y%m%d-%H%M%S).tar.gz"
    log "backing up data + letsencrypt to $archive"
    sudo tar czf "$archive" -C "$NPM_DIR" data letsencrypt
    echo "$archive"
}

prune_backups() {
    local count
    count=$(find "$BACKUP_DIR" -maxdepth 1 -name 'npm-*.tar.gz' | wc -l)
    if [ "$count" -gt "$KEEP_BACKUPS" ]; then
        find "$BACKUP_DIR" -maxdepth 1 -name 'npm-*.tar.gz' -printf '%T@ %p\n' \
            | sort -n | head -n "$((count - KEEP_BACKUPS))" | cut -d' ' -f2- \
            | while read -r f; do log "pruning old backup $f"; sudo rm -f "$f"; done
    fi
}

rollback() {
    local old_tag="$1" archive="$2"
    log "ROLLING BACK to $old_tag"
    dc down || true
    sudo rm -rf "$NPM_DIR/data" "$NPM_DIR/letsencrypt"
    sudo tar xzf "$archive" -C "$NPM_DIR"
    set_tag "$old_tag"
    dc up -d
    wait_container_healthy || log "post-rollback container still not healthy — manual attention needed"
    log "rollback to $old_tag complete"
}

write_state() {
    cat <<EOF | sudo tee "$STATE_DIR/state.json" >/dev/null
{
  "last_run": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "result": "$1",
  "running_tag": "$2",
  "target_tag": "$3",
  "openssl": "$4",
  "tag_offset": $TAG_OFFSET
}
EOF
}

container_openssl() {
    sudo docker exec "$CONTAINER" openssl version 2>/dev/null | head -1 || echo unknown
}

# --- main -----------------------------------------------------------------

CUR=$(current_tag)
[ -n "$CUR" ] || die "could not parse current image tag from $COMPOSE"

if [ -n "$TAG_OVERRIDE" ]; then
    TARGET="$TAG_OVERRIDE"
else
    TARGET=$(resolve_target_tag) || die "tag resolution failed"
fi

log "current=$CUR target=$TARGET offset=$TAG_OFFSET openssl=$(container_openssl)"

if [ "$DRY_RUN" -eq 1 ]; then
    log "dry-run: no changes made"
    exit 0
fi

if [ "$CUR" = "$TARGET" ] && [ "$FORCE" -eq 0 ]; then
    log "already on $TARGET — nothing to do"
    write_state uptodate "$CUR" "$TARGET" "$(container_openssl)"
    exit 0
fi

BEFORE=$(mktemp) ; AFTER=$(mktemp)
trap 'rm -f "$BEFORE" "$AFTER"' EXIT

log "recording pre-change health baseline"
probe_hosts > "$BEFORE"
sed 's/^/[npm-autoupdate]   baseline /' "$BEFORE"

ARCHIVE=$(backup "$CUR")

log "pulling $IMAGE_REPO:$TARGET"
sudo docker pull "$IMAGE_REPO:$TARGET" >/dev/null || {
    log "pull failed; staying on $CUR"
    write_state pull-failed "$CUR" "$TARGET" "$(container_openssl)"
    exit 1
}

set_tag "$TARGET"
log "recreating container on $TARGET"
dc up -d

if ! wait_container_healthy; then
    rollback "$CUR" "$ARCHIVE"
    write_state rolled-back-unhealthy "$CUR" "$TARGET" "$(container_openssl)"
    exit 1
fi

sleep 15
log "recording post-change health"
probe_hosts > "$AFTER"

if ! compare_health "$BEFORE" "$AFTER"; then
    rollback "$CUR" "$ARCHIVE"
    write_state rolled-back-regression "$CUR" "$TARGET" "$(container_openssl)"
    exit 1
fi

OSSL=$(container_openssl)
log "upgrade $CUR -> $TARGET verified; container openssl: $OSSL"
write_state upgraded "$TARGET" "$TARGET" "$OSSL"
prune_backups
sudo docker image prune -f >/dev/null 2>&1 || true
log "done"
