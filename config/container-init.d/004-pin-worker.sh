#!/bin/sh
set -e

# Background worker: pin IPFS CIDs from the indexer database.
# Queries offchain.token_cids for unpinned CIDs and pins them
# directly via the Kubo CLI (no auth needed, same container).
(
  # Wait for the IPFS API to be ready
  while ! wget -qO /dev/null http://localhost:5001/api/v0/version 2>/dev/null; do
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

  BATCH_SIZE="${PIN_BATCH_SIZE:-50}"
  POLL_INTERVAL="${PIN_POLL_INTERVAL:-300}"
  TIMEOUT="${PIN_TIMEOUT:-2m}"

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
    echo "$(date -Iseconds) Pin worker: $COUNT CIDs to pin"

    PINNED=0
    FAILED=0
    NOW=$(date +%s)

    for cid in $CIDS; do
      if ipfs pin add --timeout "$TIMEOUT" "$cid" >/dev/null 2>&1; then
        psql "$DATABASE_URL" -q -c \
          "INSERT INTO offchain.pinned_cids (cid, pinned_at) VALUES ('$cid', $NOW) ON CONFLICT (cid) DO NOTHING"
        PINNED=$((PINNED + 1))
      else
        psql "$DATABASE_URL" -q -c \
          "INSERT INTO offchain.failed_cids (cid, failed_at) VALUES ('$cid', $NOW) ON CONFLICT (cid) DO NOTHING"
        FAILED=$((FAILED + 1))
        echo "$(date -Iseconds) Pin worker: failed $cid"
      fi
    done

    echo "$(date -Iseconds) Pin worker: pinned $PINNED, failed $FAILED"

    # Short pause between batches when there's work, full interval when idle
    sleep 10
  done
) &
