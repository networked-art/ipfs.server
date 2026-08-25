#!/bin/sh

set -eu

: "${RAINBOW_ORIGIN_TOKEN:?RAINBOW_ORIGIN_TOKEN is required}"

# Caddy is intentionally a small, local authentication hop. It stays in the
# foreground only until the original Rainbow entrypoint replaces this shell.
caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
caddy_pid=$!

trap 'kill "$caddy_pid" 2>/dev/null || true; wait "$caddy_pid" 2>/dev/null || true' INT TERM

exec /usr/local/bin/entrypoint.sh
