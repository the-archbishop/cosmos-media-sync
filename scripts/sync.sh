#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/.env"

SCRIPT_NAME="$(basename "$0")"

APP_NAME="${1:?Usage: $0 <app_name>}"
APP_BASE="$REMOTE_BASE/$APP_NAME"

# Daily log file: ./logs/sync.sh-2026-03-02.log
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$REPO_ROOT/logs"
TODAY="$(date +%F)"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME}-${APP_NAME}-${TODAY}.log"

mkdir -p "$LOG_DIR"

# Cleanup old files
find "$LOG_DIR" -type f -name "${SCRIPT_NAME}-${APP_NAME}-*.log" -mtime +14 -delete

log() {
  # Log prefix
  echo "$(date '+%Y-%m-%d %H:%M:%S') [$SCRIPT_NAME/$APP_NAME] $*"
}

exec >>"$LOG_FILE" 2>&1

# Setup app-based locks
LOCK_DIR="$REPO_ROOT/locks"
mkdir -p "$LOCK_DIR"
LOCK_FILE="$LOCK_DIR/${SCRIPT_NAME}-${APP_NAME}.lock"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "Another sync for ${APP_NAME} is already running; exiting."
  exit 0
fi

log "Starting sync for ${APP_NAME}..."

SSH_OPTS=(-i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -T)
RSYNC_SSH="ssh ${SSH_OPTS[*]}"

# Determine destination
case "$APP_NAME" in
  radarr)
    LOCAL_DEST="$LOCAL_BASE/$MOVIES_DEST"
    ;;
  sonarr)
    LOCAL_DEST="$LOCAL_BASE/$SHOWS_DEST"
    ;;
  *)
    log "Unknown app: $APP_NAME"
    exit 1
    ;;
esac

mkdir -p "$LOCAL_DEST"

REMOTE_ITEMS_TMP="$(mktemp)"
trap 'rm -f "$REMOTE_ITEMS_TMP"' EXIT

log "Building remote list from $SEEDBOX_HOST:$APP_BASE"

ssh "${SSH_OPTS[@]}" "$SEEDBOX_HOST" \
  REMOTE_BASE="$APP_BASE" MARKER="$MARKER" \
  bash -s >"$REMOTE_ITEMS_TMP" <<'REMOTE'
set -euo pipefail
cd "$REMOTE_BASE"

find . -mindepth 1 -maxdepth 1 -print0 |
while IFS= read -r -d "" p; do
  item=${p#./}

  if [ -d "$item" ]; then
    # directory item: skip if marker exists inside
    if [ ! -f "$item/$MARKER" ]; then
      printf "%s/\0" "$item"
    fi
  elif [ -f "$item" ]; then
    # file item: skip if sidecar marker exists
    if [ ! -f "$item.$MARKER" ]; then
      printf "%s\0" "$item"
    fi
  fi
done
REMOTE

if [ ! -s "$REMOTE_ITEMS_TMP" ]; then
  log "Nothing new to sync."
  exit 0
fi

log "Syncing new items to $LOCAL_DEST..."

rsync -av \
  --from0 \
  --files-from="$REMOTE_ITEMS_TMP" \
  -e "$RSYNC_SSH" \
  "$SEEDBOX_HOST:$APP_BASE/" \
  "$LOCAL_DEST/"

item_count="$(
  python3 -c 'import sys; print(sys.stdin.buffer.read().count(b"\0"))' \
    <"$REMOTE_ITEMS_TMP"
)"
log "Items to mark (count): $item_count"

log "Marking synced items on seedbox..."

ssh "${SSH_OPTS[@]}" "$SEEDBOX_HOST" \
  REMOTE_BASE="$APP_BASE" MARKER="$MARKER" \
  'bash -c '"'"'
set -euo pipefail
cd "$REMOTE_BASE"

while IFS= read -r -d "" item; do
  item="${item%/}"
  if [ -d "$item" ]; then
    : > "$item/$MARKER"
  elif [ -f "$item" ]; then
    : > "$item.$MARKER"
  fi
done
'"'"'' <"$REMOTE_ITEMS_TMP"

log "Verifying markers on seedbox..."

ssh "${SSH_OPTS[@]}" "$SEEDBOX_HOST" \
  REMOTE_BASE="$APP_BASE" MARKER="$MARKER" \
  'bash -c '"'"'
set -euo pipefail
cd "$REMOTE_BASE"

i=0
while IFS= read -r -d "" item; do
  item="${item%/}"
  if [ -d "$item" ]; then
    if [ -f "$item/$MARKER" ]; then
      echo "MARKED $item"
    else
      echo "MISSING marker: $item"
      exit 2
    fi
  fi
  i=$((i+1))
  [ "$i" -ge 5 ] && break
done
'"'"'' <"$REMOTE_ITEMS_TMP"

log "Finished."
