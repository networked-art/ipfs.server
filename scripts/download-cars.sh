#!/bin/sh
set -e

# Download CIDs as CAR files from public IPFS gateways, trying each in turn.
# Saves to a flat directory named by CID. Import into IPFS later with `ipfs dag import`.
#
# Usage: download-cars.sh [OPTIONS]
#   -f FILE        CID list, one per line (default: /data/ipfs/all_cids.txt)
#   -c CONCURRENCY parallel downloads (default: 10)
#   -t TIMEOUT     per-request timeout in seconds (default: 60)
#   -o DIR         output directory for CAR files (default: /data/ipfs/cars)
#   -d DIR         state directory (default: /data/ipfs/download-state)
#
# State files in DIR:
#   progress      - line number where the next run resumes
#   done          - successfully downloaded CIDs, one per line
#   failed        - failed CIDs, one per line
#   download.log  - timestamped log

CIDS_FILE="/data/ipfs/all_cids.txt"
CONCURRENCY=10
TIMEOUT=60
OUT_DIR="/data/ipfs/cars"
STATE_DIR="/data/ipfs/download-state"

while getopts "f:c:t:o:d:" opt; do
  case $opt in
    f) CIDS_FILE="$OPTARG" ;;
    c) CONCURRENCY="$OPTARG" ;;
    t) TIMEOUT="$OPTARG" ;;
    o) OUT_DIR="$OPTARG" ;;
    d) STATE_DIR="$OPTARG" ;;
    *) echo "Usage: $0 [-f file] [-c concurrency] [-t timeout] [-o outdir] [-d state_dir]" >&2; exit 1 ;;
  esac
done

mkdir -p "$OUT_DIR" "$STATE_DIR"

PROGRESS_FILE="$STATE_DIR/progress"
DONE_FILE="$STATE_DIR/done"
FAILED_FILE="$STATE_DIR/failed"
LOG_FILE="$STATE_DIR/download.log"

touch "$DONE_FILE" "$FAILED_FILE"

if [ -f "$PROGRESS_FILE" ]; then
  START_LINE=$(cat "$PROGRESS_FILE")
else
  START_LINE=1
fi

TOTAL=$(wc -l < "$CIDS_FILE")

log() {
  echo "$(date -Iseconds) $1" | tee -a "$LOG_FILE"
}

log "=== Download session started ==="
log "File: $CIDS_FILE ($TOTAL CIDs)"
log "Resuming from line: $START_LINE"
log "Concurrency: $CONCURRENCY, Timeout: ${TIMEOUT}s"
log "Output: $OUT_DIR"
log "Downloaded so far: $(wc -l < "$DONE_FILE"), Failed so far: $(wc -l < "$FAILED_FILE")"

SKIP_FILE=$(mktemp)
sort -u "$DONE_FILE" "$FAILED_FILE" > "$SKIP_FILE"
SKIP_COUNT=$(wc -l < "$SKIP_FILE")
log "Skipping $SKIP_COUNT already-handled CIDs"

WORKER=$(mktemp)
cat > "$WORKER" << 'SCRIPT'
#!/bin/sh
cid="$1"; out_dir="$2"; state_dir="$3"; timeout="$4"
outfile="$out_dir/$cid.car"

if [ -s "$outfile" ]; then
  echo "$cid" >> "$state_dir/done"
  exit 0
fi

GATEWAYS="https://ipfs.foundation.app/ipfs https://ipfs.io/ipfs https://ipfs.filebase.io/ipfs https://dweb.link/ipfs https://eu.orbitor.dev/ipfs"

for gw in $GATEWAYS; do
  tmpfile=$(mktemp)
  if wget -q --tries=1 -T "$timeout" -O "$tmpfile" "$gw/$cid?format=car" 2>/dev/null && [ -s "$tmpfile" ]; then
    mv "$tmpfile" "$outfile"
    echo "$cid" >> "$state_dir/done"
    exit 0
  fi
  rm -f "$tmpfile"
done
echo "$cid" >> "$state_dir/failed"
SCRIPT
chmod +x "$WORKER"

cleanup() {
  rm -f "$SKIP_FILE" "$WORKER"
  log "=== Download session ended ==="
  log "Overall: $(wc -l < "$DONE_FILE") downloaded, $(wc -l < "$FAILED_FILE") failed out of $TOTAL"
}
trap cleanup EXIT

BATCH_SIZE=500
LINE=$START_LINE

while [ "$LINE" -le "$TOTAL" ]; do
  BATCH_END=$((LINE + BATCH_SIZE - 1))
  [ "$BATCH_END" -gt "$TOTAL" ] && BATCH_END=$TOTAL

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
  log "Lines $LINE-$BATCH_END: downloading $BATCH_COUNT CIDs..."

  BEFORE_DONE=$(wc -l < "$DONE_FILE")
  BEFORE_FAILED=$(wc -l < "$FAILED_FILE")

  echo "$BATCH" | xargs -P "$CONCURRENCY" -I{} "$WORKER" {} "$OUT_DIR" "$STATE_DIR" "$TIMEOUT"

  AFTER_DONE=$(wc -l < "$DONE_FILE")
  AFTER_FAILED=$(wc -l < "$FAILED_FILE")
  OK=$((AFTER_DONE - BEFORE_DONE))
  FAIL=$((AFTER_FAILED - BEFORE_FAILED))
  PCT=$((AFTER_DONE * 100 / TOTAL))

  LINE=$((BATCH_END + 1))
  echo "$LINE" > "$PROGRESS_FILE"

  log "  +$OK done, +$FAIL failed | Total: $AFTER_DONE/$TOTAL ($PCT%) downloaded, $AFTER_FAILED failed"
done
