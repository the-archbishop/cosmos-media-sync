#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/.env"

SCRIPT_NAME="$(basename "$0")"

APP_NAME="${1:?Usage: $0 <app_name>}"
APP_BASE="$REMOTE_BASE/$APP_NAME"

MODE="${2:---dry-run}"

# Daily log file: ./logs/downloads-cleanup.sh-radarr-2026-03-02.log
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
  log "Another cleanup for ${APP_NAME} is already running; exiting."
  exit 0
fi

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

# Safety check
if [[ -z "${LOCAL_DEST:-}" || "$LOCAL_DEST" == "/" ]]; then
  log "LOCAL_DEST is unsafe ($LOCAL_DEST)"
  exit 1
fi

# Determine behavior
DO_DELETE=0
case "$MODE" in
  --dry-run) DO_DELETE=0 ;;
  --delete)  DO_DELETE=1 ;;
  *)
    log "Unknown mode: $MODE (use --dry-run or --delete)"
    exit 1
    ;;
esac

log "Starting cleanup for ${APP_NAME}..."
log "Remote: $SEEDBOX_HOST:$APP_BASE"
log "Local : $LOCAL_DEST"
log "Mode  : $MODE"

SSH_OPTS=(-i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -T)

REMOTE_MARKED_TMP="$(mktemp)"
trap 'rm -f "$REMOTE_MARKED_TMP"' EXIT

log "Building remote MARKED list (marker=$MARKER)..."

ssh "${SSH_OPTS[@]}" "$SEEDBOX_HOST" \
  REMOTE_BASE="$APP_BASE" MARKER="$MARKER" \
  bash -s >"$REMOTE_MARKED_TMP" <<'REMOTE'
set -euo pipefail
cd "$REMOTE_BASE"

find . -mindepth 1 -maxdepth 1 -print0 |
while IFS= read -r -d "" p; do
  item=${p#./}

  if [ -d "$item" ]; then
    # directory item: INCLUDE if marker exists inside
    if [ -f "$item/$MARKER" ]; then
      printf "%s/\0" "$item"
    fi
  elif [ -f "$item" ]; then
    # file item: INCLUDE if sidecar marker exists
    if [ -f "$item.$MARKER" ]; then
      printf "%s\0" "$item"
    fi
  fi
done
REMOTE

if [ ! -s "$REMOTE_MARKED_TMP" ]; then
  log "No marked items found on seedbox."
  exit 0
fi

marked_count="$(
  python3 -c 'import sys; print(sys.stdin.buffer.read().count(b"\0"))' \
    <"$REMOTE_MARKED_TMP"
)"
log "Marked items found (count): $marked_count"

log "Processing local deletions..."

deleted=0
missing=0
skipped=0

while IFS= read -r -d "" item; do
  # item is either dir or file
  base="${item%/}"

  if [[ "$base" == *"/"* ]] || [[ "$base" == "." ]] || [[ "$base" == ".." ]] || [[ -z "$base" ]]; then
    log "SKIP suspicious item name: [$item]"
    skipped=$((skipped+1))
    continue
  fi

  target="$LOCAL_DEST/$base"

  # Another safety check
  case "$target" in
    "$LOCAL_DEST"/*) : ;;
    *)
        log "SKIP target outside LOCAL_DEST: $target"
        skipped=$((skipped+1))
        continue
        ;;
    esac

  # Process deletions
  if [ -d "$target" ]; then
    if [ "$DO_DELETE" -eq 1 ]; then
      log "DELETE dir : $target"
      rm -rf -- "$target"
      deleted=$((deleted+1))
    else
      log "DRY-RUN dir: $target"
    fi
  elif [ -f "$target" ]; then
    if [ "$DO_DELETE" -eq 1 ]; then
      log "DELETE file: $target"
      rm -f -- "$target"
      deleted=$((deleted+1))
    else
      log "DRY-RUN file: $target"
    fi
  else
    log "MISSING    : $target"
    missing=$((missing+1))
  fi
done <"$REMOTE_MARKED_TMP"

log "Summary: deleted=$deleted missing=$missing skipped=$skipped"
log "Finished."
