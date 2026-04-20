FROM caddy:2-alpine AS caddy

FROM ipfs/kubo:v0.40.0
COPY --from=caddy /usr/bin/caddy /usr/local/bin/caddy
COPY --chmod=755 scripts/pin-cids.sh /usr/local/bin/pin-cids.sh
COPY --chmod=755 scripts/download-cars.sh /usr/local/bin/download-cars.sh
COPY config/Caddyfile /etc/caddy/Caddyfile
COPY config/container-init.d/ /container-init.d/
