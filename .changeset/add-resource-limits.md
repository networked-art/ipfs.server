---
"@1001/ipfs-server": minor
---

Add configurable resource limits for CPU, memory, and file descriptors

- Container-level limits (`CONTAINER_CPUS`, `CONTAINER_MEMORY`) are now configurable via environment variables (defaults: 2 CPUs, 6G memory)
- Added Kubo libp2p resource manager limits (`RESOURCE_MGR_MAX_MEMORY`, `RESOURCE_MGR_MAX_FILE_DESCRIPTORS`) with defaults of 4GB and 4096
