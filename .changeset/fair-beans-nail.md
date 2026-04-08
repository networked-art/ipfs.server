---
"@1001/ipfs-server": minor
---

Add upload script for files and directories

Upload files or entire directories to the IPFS node's MFS via `pnpm upload`. Supports optional pinning (`--pin`) and custom MFS paths (`--mfs-path`). Runs natively on Node 24 with no build tooling required.

```sh
# Upload a directory
pnpm upload ./dist

# Upload a single file
pnpm upload ./image.png

# Pin the content after uploading
pnpm upload ./dist --pin

# Specify a custom MFS path (defaults to /<name>)
pnpm upload ./dist --mfs-path /my-site
```
