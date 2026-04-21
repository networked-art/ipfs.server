#!/bin/sh
set -e

# Background worker: pin CIDs by importing local CAR files (no network fetch).
# Runs only when WORKER=pin-local.
#
# Env vars:
#   PIN_CIDS_FILE          - path to CID list inside the container (required)
#   PIN_LOCAL_CARS_DIR     - directory of $CID.car files (default: /data/ipfs/cars)
#   PIN_LOCAL_CONCURRENCY  - parallel workers (default: 8)
#   PIN_LOCAL_TIMEOUT      - per-CID timeout (default: 5m)
#   PIN_STATE_DIR          - state directory (default: /data/ipfs/pin-state)
(
  if [ "$WORKER" != "pin-local" ]; then
    exit 0
  fi

  if [ -z "$PIN_CIDS_FILE" ]; then
    echo "Pin-local worker: PIN_CIDS_FILE not set, skipping"
    exit 0
  fi

  # Wait for the IPFS API to be ready
  while ! wget -qO /dev/null --post-data="" http://localhost:5001/api/v0/version 2>/dev/null; do
    sleep 2
  done

  if [ ! -f "$PIN_CIDS_FILE" ]; then
    echo "Pin-local worker: $PIN_CIDS_FILE not found, skipping"
    exit 0
  fi

  echo "$(date -Iseconds) Pin-local worker: starting pin-local.sh"
  pin-local.sh \
    -f "$PIN_CIDS_FILE" \
    -o "${PIN_LOCAL_CARS_DIR:-/data/ipfs/cars}" \
    -c "${PIN_LOCAL_CONCURRENCY:-8}" \
    -t "${PIN_LOCAL_TIMEOUT:-5m}" \
    -d "${PIN_STATE_DIR:-/data/ipfs/pin-state}"
) &
