#!/bin/sh
set -e

# Pin CIDs from a file with concurrency, progress tracking, and failure logging.
#
# Usage: pin-cids.sh [OPTIONS]
#   -f FILE        CID list, one per line (default: /data/all_cids.txt)
#   -c CONCURRENCY parallel pins (default: 20)
#   -t TIMEOUT     per-CID timeout (default: 2m)
#   -d DIR         working directory for state files (default: /data/ipfs/pin-state)
#
# State files in DIR:
#   progress  - line number where the next run resumes
#   pinned    - successfully pinned CIDs, one per line
#   failed    - failed CIDs, one per line
#   pin.log   - timestamped log

CIDS_FILE="/data/all_cids.txt"
CONCURRENCY=20
TIMEOUT="2m"
STATE_DIR="/data/ipfs/pin-state"

while getopts "f:c:t:d:" opt; do
  case $opt in
    f) CIDS_FILE="$OPTARG" ;;
    c) CONCURRENCY="$OPTARG" ;;
    t) TIMEOUT="$OPTARG" ;;
    d) STATE_DIR="$OPTARG" ;;
    *) echo "Usage: $0 [-f file] [-c concurrency] [-t timeout] [-d state_dir]" >&2; exit 1 ;;
  esac
done

mkdir -p "$STATE_DIR"

PROGRESS_FILE="$STATE_DIR/progress"
PINNED_FILE="$STATE_DIR/pinned"
FAILED_FILE="$STATE_DIR/failed"
LOG_FILE="$STATE_DIR/pin.log"

touch "$PINNED_FILE" "$FAILED_FILE"

if [ -f "$PROGRESS_FILE" ]; then
  START_LINE=$(cat "$PROGRESS_FILE")
else
  START_LINE=1
fi

TOTAL=$(wc -l < "$CIDS_FILE")

log() {
  echo "$(date -Iseconds) $1" | tee -a "$LOG_FILE"
}

log "=== Pin session started ==="
log "File: $CIDS_FILE ($TOTAL CIDs)"
log "Resuming from line: $START_LINE"
log "Concurrency: $CONCURRENCY, Timeout: $TIMEOUT"
log "Pinned so far: $(wc -l < "$PINNED_FILE"), Failed so far: $(wc -l < "$FAILED_FILE")"

# Build skip set from already-handled CIDs
SKIP_FILE=$(mktemp)
sort -u "$PINNED_FILE" "$FAILED_FILE" > "$SKIP_FILE"
SKIP_COUNT=$(wc -l < "$SKIP_FILE")
log "Skipping $SKIP_COUNT already-handled CIDs"

# Write the single-CID worker script (called by xargs -P)
WORKER=$(mktemp)
cat > "$WORKER" << 'SCRIPT'
#!/bin/sh
cid="$1"; timeout="$2"; state_dir="$3"
if ipfs pin add --timeout "$timeout" "$cid" >/dev/null 2>&1; then
  echo "$cid" >> "$state_dir/pinned"
else
  echo "$cid" >> "$state_dir/failed"
fi
SCRIPT
chmod +x "$WORKER"

# Trap to clean up and report on exit
cleanup() {
  rm -f "$SKIP_FILE" "$WORKER"
  log "=== Pin session ended ==="
  log "Overall: $(wc -l < "$PINNED_FILE") pinned, $(wc -l < "$FAILED_FILE") failed out of $TOTAL"
}
trap cleanup EXIT

BATCH_SIZE=500
LINE=$START_LINE

while [ "$LINE" -le "$TOTAL" ]; do
  BATCH_END=$((LINE + BATCH_SIZE - 1))
  [ "$BATCH_END" -gt "$TOTAL" ] && BATCH_END=$TOTAL

  # Extract batch, filter out already-handled CIDs
  RAW_BATCH=$(sed -n "${LINE},${BATCH_END}p" "$CIDS_FILE")
  if [ -s "$SKIP_FILE" ]; then
    BATCH=$(echo "$RAW_BATCH" | grep -vxFf "$SKIP_FILE" || true)
  else
    BATCH="$RAW_BATCH"
  fi

  if [ -z "$BATCH" ]; then
    LINE=$((BATCH_END + 1))
    echo "$LINE" > "$PROGRESS_FILE"
    continue
  fi

  BATCH_COUNT=$(echo "$BATCH" | wc -l)
  log "Lines $LINE-$BATCH_END: pinning $BATCH_COUNT CIDs..."

  # Pin with concurrency via xargs
  BEFORE_PINNED=$(wc -l < "$PINNED_FILE")
  BEFORE_FAILED=$(wc -l < "$FAILED_FILE")

  echo "$BATCH" | xargs -P "$CONCURRENCY" -I{} "$WORKER" {} "$TIMEOUT" "$STATE_DIR"

  AFTER_PINNED=$(wc -l < "$PINNED_FILE")
  AFTER_FAILED=$(wc -l < "$FAILED_FILE")
  OK=$((AFTER_PINNED - BEFORE_PINNED))
  FAIL=$((AFTER_FAILED - BEFORE_FAILED))
  PCT=$((AFTER_PINNED * 100 / TOTAL))

  LINE=$((BATCH_END + 1))
  echo "$LINE" > "$PROGRESS_FILE"

  log "  +$OK pinned, +$FAIL failed | Total: $AFTER_PINNED/$TOTAL ($PCT%) pinned, $AFTER_FAILED failed"
done
