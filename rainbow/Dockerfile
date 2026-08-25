# The retrieval gateway is deliberately independent of the pinned Kubo node.
# Pin the upstream release so a deploy does not pick up an unreviewed build.
FROM caddy:2-alpine AS caddy

FROM ghcr.io/ipfs/rainbow:v1.24.1

COPY --from=caddy /usr/bin/caddy /usr/local/bin/caddy
COPY --chmod=755 config/start.sh /usr/local/bin/start-rainbow-gateway
COPY config/Caddyfile /etc/caddy/Caddyfile
COPY config/denylist.deny /etc/rainbow/denylist.deny

# Caddy receives edge-authenticated traffic on 8080 and proxies to Rainbow on
# loopback. Rainbow itself stays on 8090, unavailable to Kamal proxy directly.
EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/start-rainbow-gateway"]
