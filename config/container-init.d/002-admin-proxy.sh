#!/bin/sh
set -e

# Start Caddy admin proxy with basic auth in background
mkdir -p /tmp/caddy
XDG_DATA_HOME=/tmp/caddy XDG_CONFIG_HOME=/tmp/caddy \
  caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
