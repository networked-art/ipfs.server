#!/bin/sh
set -e

# Pin CIDs from local CAR files. For each CID in the list, imports the
# corresponding $CID.car (no root pinning) and then explicitly pins the CID.
# Explicit pinning by the CID from the list guarantees the pinned CID matches
# what we expected — if the CAR's root differs, `ipfs pin add` fails because
# the block isn't in the local store.
#
# Usage: pin-local.sh [OPTIONS]
#   -f FILE        CID list, one per line (default: /data/ipfs/all_cids.txt)
#   -o DIR         directory containing $CID.car files (default: /data/ipfs/cars)
#   -c CONCURRENCY parallel workers (default: 8)
#   -t TIMEOUT     per-CID timeout (default: 5m)
#   -d DIR         state directory (default: /data/ipfs/pin-state)
#
# State files in DIR:
#   pinned    - successfully pinned CIDs
#   failed    - failed CIDs (import or pin error)
#   missing   - CIDs with no local CAR file
#   pin.log   - timestamped log

CIDS_FILE="/data/ipfs/all_cids.txt"
CARS_DIR="/data/ipfs/cars"
CONCURRENCY=8
TIMEOUT="5m"
STATE_DIR="/data/ipfs/pin-state"

while getopts "f:o:c:t:d:" opt; do
  case $opt in
    f) CIDS_FILE="$OPTARG" ;;
    o) CARS_DIR="$OPTARG" ;;
    c) CONCURRENCY="$OPTARG" ;;
    t) TIMEOUT="$OPTARG" ;;
    d) STATE_DIR="$OPTARG" ;;
    *) echo "Usage: $0 [-f file] [-o cars_dir] [-c concurrency] [-t timeout] [-d state_dir]" >&2; exit 1 ;;
  esac
done

mkdir -p "$STATE_DIR"

PINNED_FILE="$STATE_DIR/pinned"
FAILED_FILE="$STATE_DIR/failed"
MISSING_FILE="$STATE_DIR/missing"
LOG_FILE="$STATE_DIR/pin.log"

touch "$PINNED_FILE" "$FAILED_FILE" "$MISSING_FILE"

TOTAL=$(sort -u "$CIDS_FILE" | wc -l)

log() {
  echo "$(date -Iseconds) $1" | tee -a "$LOG_FILE"
}

log "=== Local pin session started ==="
log "CIDs: $CIDS_FILE ($TOTAL unique)"
log "CARs: $CARS_DIR"
log "Concurrency: $CONCURRENCY, Timeout: $TIMEOUT"
log "Pinned so far: $(sort -u "$PINNED_FILE" | wc -l), Failed so far: $(sort -u "$FAILED_FILE" | wc -l), Missing so far: $(sort -u "$MISSING_FILE" | wc -l)"

# Build skip list from previously handled CIDs (pinned/failed/missing)
SKIP_FILE=$(mktemp)
sort -u "$PINNED_FILE" "$FAILED_FILE" "$MISSING_FILE" > "$SKIP_FILE"
SKIP_COUNT=$(wc -l < "$SKIP_FILE")
log "Skipping $SKIP_COUNT already-handled CIDs"

# Work list: unique CIDs from input, minus already-handled
WORK_FILE=$(mktemp)
if [ -s "$SKIP_FILE" ]; then
  sort -u "$CIDS_FILE" | grep -vxFf "$SKIP_FILE" > "$WORK_FILE" || true
else
  sort -u "$CIDS_FILE" > "$WORK_FILE"
fi
WORK_COUNT=$(wc -l < "$WORK_FILE")
log "Work remaining: $WORK_COUNT CIDs"

WORKER=$(mktemp)
cat > "$WORKER" << 'SCRIPT'
#!/bin/sh
cid="$1"; cars_dir="$2"; timeout="$3"; state_dir="$4"

car="$cars_dir/$cid.car"

if [ ! -s "$car" ]; then
  echo "$cid" >> "$state_dir/missing"
  exit 0
fi

# Import blocks only; do NOT pin roots declared in the CAR (we pin by the
# filename CID below to guarantee it matches the list).
if ! timeout "$timeout" ipfs dag import --pin-roots=false --stats=false --silent "$car" >/dev/null 2>&1; then
  echo "$cid import-failed" >> "$state_dir/failed"
  exit 0
fi

# Pin the CID from the list. Fails if the root of the CAR didn't match the
# filename (block absent) — which is exactly the safety check we want.
if timeout "$timeout" ipfs pin add --progress=false "$cid" >/dev/null 2>&1; then
  echo "$cid" >> "$state_dir/pinned"
else
  echo "$cid pin-failed" >> "$state_dir/failed"
fi
SCRIPT
chmod +x "$WORKER"

cleanup() {
  rm -f "$SKIP_FILE" "$WORK_FILE" "$WORKER"
  log "=== Local pin session ended ==="
  log "Pinned: $(sort -u "$PINNED_FILE" | wc -l), Failed: $(sort -u "$FAILED_FILE" | wc -l), Missing: $(sort -u "$MISSING_FILE" | wc -l) of $TOTAL total unique"
}
trap cleanup EXIT

BATCH_SIZE=500
OFFSET=0

while [ "$OFFSET" -lt "$WORK_COUNT" ]; do
  END=$((OFFSET + BATCH_SIZE))
  [ "$END" -gt "$WORK_COUNT" ] && END=$WORK_COUNT

  BATCH=$(sed -n "$((OFFSET + 1)),${END}p" "$WORK_FILE")
  BATCH_COUNT=$(echo "$BATCH" | grep -c .)

  BEFORE_PINNED=$(wc -l < "$PINNED_FILE")
  BEFORE_FAILED=$(wc -l < "$FAILED_FILE")
  BEFORE_MISSING=$(wc -l < "$MISSING_FILE")

  log "Batch $((OFFSET + 1))-$END: processing $BATCH_COUNT CIDs..."
  echo "$BATCH" | xargs -P "$CONCURRENCY" -I{} "$WORKER" {} "$CARS_DIR" "$TIMEOUT" "$STATE_DIR"

  AFTER_PINNED=$(wc -l < "$PINNED_FILE")
  AFTER_FAILED=$(wc -l < "$FAILED_FILE")
  AFTER_MISSING=$(wc -l < "$MISSING_FILE")

  OK=$((AFTER_PINNED - BEFORE_PINNED))
  FAIL=$((AFTER_FAILED - BEFORE_FAILED))
  MISS=$((AFTER_MISSING - BEFORE_MISSING))
  PCT=$((AFTER_PINNED * 100 / TOTAL))

  log "  +$OK pinned, +$FAIL failed, +$MISS missing | Total: $AFTER_PINNED/$TOTAL ($PCT%) pinned, $AFTER_FAILED failed, $AFTER_MISSING missing"

  OFFSET=$END
done
