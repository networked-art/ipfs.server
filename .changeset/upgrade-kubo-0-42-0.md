---
"@1001/ipfs-server": minor
---

Upgrade Kubo from v0.40.0 to v0.42.0

This picks up the upstream fix for pin operations hanging during reprovide
cycles under selective `Provide.Strategy` modes, bounded daemon shutdowns, and
the stronger `ipfs diag healthy` container health check. It also updates WebUI
CID detection for the redirect behavior introduced in Kubo 0.41 and explicitly
keeps anonymous telemetry disabled by default.
