#!/bin/sh
set -e

# Background worker: pin CIDs from a newline-separated text file.
#
# Env vars:
#   PIN_CIDS_FILE     - path to CID list inside the container (required)
#   PIN_CONCURRENCY   - parallel pins (default: 20)
#   PIN_TIMEOUT       - per-CID timeout (default: 2m)
#   PIN_STATE_DIR     - state directory (default: /data/ipfs/pin-state)
(
  if [ -z "$PIN_CIDS_FILE" ]; then
    echo "Pin worker: PIN_CIDS_FILE not set, skipping"
    exit 0
  fi

  # Wait for the IPFS API to be ready
  while ! wget -qO /dev/null --post-data="" http://localhost:5001/api/v0/version 2>/dev/null; do
    sleep 2
  done

  if [ ! -f "$PIN_CIDS_FILE" ]; then
    echo "Pin worker: $PIN_CIDS_FILE not found, skipping"
    exit 0
  fi

  echo "$(date -Iseconds) Pin worker: starting pin-cids.sh"
  pin-cids.sh \
    -f "$PIN_CIDS_FILE" \
    -c "${PIN_CONCURRENCY:-20}" \
    -t "${PIN_TIMEOUT:-2m}" \
    -d "${PIN_STATE_DIR:-/data/ipfs/pin-state}"
) &
