#!/bin/sh
set -e

# Background worker: pin IPFS CIDs from the indexer database.
# Queries offchain.token_cids for unpinned CIDs and pins them
# directly via the Kubo CLI (no auth needed, same container).
#
# Env vars (all optional):
#   PIN_CONCURRENCY   - parallel pins (default: 5)
#   PIN_BATCH_SIZE    - CIDs per batch (default: 50)
#   PIN_POLL_INTERVAL - seconds between idle polls (default: 300)
#   PIN_TIMEOUT       - per-CID timeout (default: 2m)
(
  # Wait for the IPFS API to be ready
  while ! wget -qO /dev/null --post-data="" http://localhost:5001/api/v0/version 2>/dev/null; do
    sleep 2
  done

  # Wait for the database to be reachable
  if [ -z "$DATABASE_URL" ]; then
    echo "Pin worker: DATABASE_URL not set, skipping"
    exit 0
  fi

  while ! pg_isready -d "$DATABASE_URL" >/dev/null 2>&1; do
    sleep 5
  done

  echo "$(date -Iseconds) Pin worker: started"

  # Ensure tracking tables exist
  psql "$DATABASE_URL" -q -c "
    CREATE SCHEMA IF NOT EXISTS offchain;

    CREATE TABLE IF NOT EXISTS offchain.pinned_cids (
      cid TEXT PRIMARY KEY,
      pinned_at INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS offchain.failed_cids (
      cid TEXT PRIMARY KEY,
      failed_at INTEGER NOT NULL
    );
  "

  CONCURRENCY="${PIN_CONCURRENCY:-10}"
  BATCH_SIZE="${PIN_BATCH_SIZE:-50}"
  POLL_INTERVAL="${PIN_POLL_INTERVAL:-300}"
  TIMEOUT="${PIN_TIMEOUT:-2m}"

  # Helper script for xargs -P: pins one CID and records the result
  cat > /tmp/pin-one.sh << 'PINSCRIPT'
#!/bin/sh
cid="$1"
timeout="$2"
db="$3"
now=$(date +%s)
if ipfs pin add --timeout "$timeout" "$cid" >/dev/null 2>&1; then
  psql "$db" -q -c "INSERT INTO offchain.pinned_cids (cid, pinned_at) VALUES ('$cid', $now) ON CONFLICT (cid) DO NOTHING"
else
  psql "$db" -q -c "INSERT INTO offchain.failed_cids (cid, failed_at) VALUES ('$cid', $now) ON CONFLICT (cid) DO NOTHING"
  echo "$(date -Iseconds) Pin worker: failed $cid"
fi
PINSCRIPT
  chmod +x /tmp/pin-one.sh

  while true; do
    CIDS=$(psql "$DATABASE_URL" -t -A -c "
      SELECT DISTINCT u.cid
      FROM offchain.token_cids tc,
      LATERAL unnest(ARRAY[tc.metadata_cid, tc.image_cid, tc.animation_cid]) AS u(cid)
      LEFT JOIN offchain.pinned_cids p ON p.cid = u.cid
      LEFT JOIN offchain.failed_cids f ON f.cid = u.cid
      WHERE u.cid IS NOT NULL
        AND p.cid IS NULL
        AND f.cid IS NULL
      LIMIT $BATCH_SIZE
    ")

    if [ -z "$CIDS" ]; then
      sleep "$POLL_INTERVAL"
      continue
    fi

    COUNT=$(echo "$CIDS" | wc -l)
    BEFORE=$(psql "$DATABASE_URL" -t -A -c "SELECT count(*) FROM offchain.pinned_cids")
    echo "$(date -Iseconds) Pin worker: pinning $COUNT CIDs (concurrency=$CONCURRENCY)"

    echo "$CIDS" | xargs -P "$CONCURRENCY" -I{} /tmp/pin-one.sh {} "$TIMEOUT" "$DATABASE_URL"

    AFTER=$(psql "$DATABASE_URL" -t -A -c "SELECT count(*) FROM offchain.pinned_cids")
    FAILED=$(psql "$DATABASE_URL" -t -A -c "SELECT count(*) FROM offchain.failed_cids")
    echo "$(date -Iseconds) Pin worker: pinned $((AFTER - BEFORE)), total=$AFTER, failed=$FAILED"

    # Short pause between batches when there's work
    sleep 10
  done
) &
