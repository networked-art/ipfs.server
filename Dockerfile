FROM caddy:2-alpine AS caddy

FROM debian:bookworm-slim AS pgtools
RUN apt-get update && \
    apt-get install -y --no-install-recommends postgresql-client && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /out/bin /out/lib && \
    cp /usr/lib/postgresql/15/bin/psql /out/bin/ && \
    cp /usr/lib/postgresql/15/bin/pg_isready /out/bin/ && \
    for bin in /out/bin/*; do \
      ldd "$bin" | grep '=> /' | awk '{print $3}'; \
    done | sort -u | grep -vE 'libc\.so|libm\.so|libpthread|libresolv|ld-linux|libnss' \
    | while read lib; do cp -L "$lib" /out/lib/; done

FROM ipfs/kubo:v0.40.0
COPY --from=caddy /usr/bin/caddy /usr/local/bin/caddy
COPY --from=pgtools /out/bin/ /usr/local/bin/
COPY --from=pgtools /out/lib/ /lib/
COPY config/Caddyfile /etc/caddy/Caddyfile
COPY config/container-init.d/ /container-init.d/
