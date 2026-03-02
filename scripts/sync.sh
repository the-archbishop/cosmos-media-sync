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

log "Starting sync for ${APP_NAME}..."

SSH_OPTS=(-i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -T)
RSYNC_SSH="ssh ${SSH_OPTS[*]}"

# Determine destination
case "$APP_NAME" in
  radarr)
    LOCAL_DEST="$LOCAL_BASE/movies"
    ;;
  sonarr)
    LOCAL_DEST="$LOCAL_BASE/shows"
    ;;
  *)
    log "Unknown app: $APP_NAME"
    exit 1
    ;;
esac

mkdir -p "$LOCAL_DEST"

REMOTE_LIST_TMP="$(mktemp)"
trap 'rm -f "$REMOTE_LIST_TMP"' EXIT

log "Building remote list from $SEEDBOX_HOST:$APP_BASE"

# Build remote files-from list and write it locally to REMOTE_LIST_TMP
ssh "${SSH_OPTS[@]}" "$SEEDBOX_HOST" \
  REMOTE_BASE="$APP_BASE" MARKER="$MARKER" \
  bash -s >"$REMOTE_LIST_TMP" <<'REMOTE'
set -euo pipefail
cd "$REMOTE_BASE"

find . -mindepth 1 -maxdepth 1 -print0 |
while IFS= read -r -d "" p; do
  item=${p#./}

  if [ -d "$item" ]; then
    if [ ! -f "$item/$MARKER" ]; then
      printf "%s/***\0" "$item"
    fi
  elif [ -f "$item" ]; then
    if [ ! -f "$item.$MARKER" ]; then
      printf "%s/***\0" "$item"
    fi
  fi
done
REMOTE

if [ ! -s "$REMOTE_LIST_TMP" ]; then
  log "Nothing new to sync."
  exit 0
fi

log "Syncing new items to $LOCAL_DEST..."

rsync -av \
  --from0 \
  --files-from="$REMOTE_LIST_TMP" \
  -e "$RSYNC_SSH" \
  "$SEEDBOX_HOST:$APP_BASE/" \
  "$LOCAL_DEST/"

log "Marking synced items on seedbox..."

ssh "${SSH_OPTS[@]}" "$SEEDBOX_HOST" \
  REMOTE_BASE="$APP_BASE" MARKER="$MARKER" \
  bash -s <"$REMOTE_LIST_TMP" <<'REMOTE'
set -euo pipefail
cd "$REMOTE_BASE"

while IFS= read -r -d "" item; do
  if [ -d "$item" ]; then
    : > "$item/$MARKER"
  elif [ -f "$item" ]; then
    : > "$item.$MARKER"
  fi
done
REMOTE

log "Finished."
