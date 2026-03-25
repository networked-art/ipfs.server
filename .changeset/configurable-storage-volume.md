---
"@1001/ipfs-server": minor
---

Add configurable storage volume via `IPFS_VOLUME` environment variable

- The IPFS data volume can now be configured via `IPFS_VOLUME` env var, defaulting to the named Docker volume `ipfs_data`
- Supports host path bind mounts (e.g. `/mnt/ipfs/ipfs_data`) for custom storage locations
