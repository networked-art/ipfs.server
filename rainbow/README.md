# EVM.now Rainbow retrieval gateway

This is a separate, retrieval-only Rainbow service on the Networked IPFS
host. It does not replace or modify the `1001-ipfs` Kubo deployment: Kubo
continues to provide only the project's explicitly pinned CIDs.

The Cloudflare Worker is the public entry point. Rainbow receives only
Worker-originated requests carrying `X-EVMNow-Gateway-Token`; direct retrieval
through the origin returns `403`. `/health` is the sole unauthenticated path.

## First deployment

1. Copy `.env.production.example` to local `.env.production` and set the
   target/IPFS hostname. Keep `RAINBOW_ORIGIN_TOKEN` out of it.
2. Generate an opaque token, export it while deploying, and set the same value
   as the Worker secret. Do not commit or print it.
3. Install `ops/docker-egress-specialuse-guard.sh` at
   `/usr/local/sbin/evm-now-rainbow-egress-guard`, install the matching systemd
   unit, enable it, and verify all IPv4 and IPv6 rules on `enp41s0`.
4. Run `ops/provision-data-volume.sh` once. It creates a fixed-size 250 GiB
   cache filesystem under `/home/ipfs/rainbow`; do not replace it with a root
   filesystem or parent bind mount.
5. Deploy with `pnpm kamal:setup` once, then `pnpm kamal:deploy`.

Rainbow's DHT crawler is permanently disabled. It uses delegated HTTP routing,
request/response limits, Bad Bits plus the local emergency denylist, and
resource limits. Keep public gateway fallbacks in the Worker because long-tail
CID retrieval is not guaranteed.
