#!/bin/sh
set -e

# Background worker: download CAR files from public gateways for a list of CIDs.
# Runs only when WORKER=download.
#
# Env vars:
#   DOWNLOAD_CIDS_FILE    - path to CID list inside the container (required)
#   DOWNLOAD_CONCURRENCY  - parallel downloads (default: 10)
#   DOWNLOAD_TIMEOUT      - per-request timeout in seconds (default: 60)
#   DOWNLOAD_OUT_DIR      - output directory (default: /data/ipfs/cars)
#   DOWNLOAD_STATE_DIR    - state directory (default: /data/ipfs/download-state)
(
  if [ "$WORKER" != "download" ]; then
    exit 0
  fi

  if [ -z "$DOWNLOAD_CIDS_FILE" ]; then
    echo "Download worker: DOWNLOAD_CIDS_FILE not set, skipping"
    exit 0
  fi

  if [ ! -f "$DOWNLOAD_CIDS_FILE" ]; then
    echo "Download worker: $DOWNLOAD_CIDS_FILE not found, skipping"
    exit 0
  fi

  echo "$(date -Iseconds) Download worker: starting download-cars.sh"
  download-cars.sh \
    -f "$DOWNLOAD_CIDS_FILE" \
    -c "${DOWNLOAD_CONCURRENCY:-10}" \
    -t "${DOWNLOAD_TIMEOUT:-60}" \
    -o "${DOWNLOAD_OUT_DIR:-/data/ipfs/cars}" \
    -d "${DOWNLOAD_STATE_DIR:-/data/ipfs/download-state}"
) &
