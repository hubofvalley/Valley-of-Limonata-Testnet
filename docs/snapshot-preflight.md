# Limonata snapshot metadata preflight

Valley provides a **read-only** preflight for the currently documented POSTHUMAN
Limonata testnet snapshot. The provider currently publishes a moving `latest`
archive, `snapshot.json` and `SHA256SUMS`. The preflight compares their declared
chain, filename, size and digest; checks the archive's HTTP `Content-Length`
without downloading archive bytes; checks two reviewed public CometBFT RPCs for
chain ID, height, sync status and recent latest-block timestamps; and fails
closed if provider metadata changes during the check.

The RPC freshness limit is reviewed in `VERSIONS.json` (currently 600 seconds).
Both RPCs must report a valid UTC latest-block timestamp within that limit;
`catching_up=false` alone does not demonstrate that a public endpoint is live.
The check uses the operator host's UTC clock and fails closed if a timestamp is
missing, malformed, stale or more than 60 seconds in the future. Keep the host
clock synchronized; an incorrect clock can produce `UNKNOWN`.

From a reviewed local repository checkout:

```bash
bash resources/limonata_snapshot_preflight.sh
```

All provider and RPC URLs are in `VERSIONS.json`, not inferred from a local node
or operator secrets. Results are `PRECHECK_PASS` or `UNKNOWN`. A precheck pass
**does not verify the archive payload** and is not approval to restore, delete,
reset, or overwrite a node. The tool never downloads the archive, performs a
service operation, accesses signing keys, or modifies node configuration.

On an eventual, separately authorized recovery, the operator must independently
verify the SHA-256 of the **fully downloaded** archive against the reviewed
expected digest and follow a signer-state/DKG recovery plan. The preflight never
claims cryptographic trust in a provider merely because its own JSON and
checksum file agree. A full archive can exceed tens of gigabytes; downloading
and hashing it is deliberately outside this tool's resource-safe scope.

Any failed HTTP request, missing or ambiguous field, bad filename, RPC/network
disagreement, unexpected layout, or rotating metadata results in `UNKNOWN` with
nonzero exit status. There is no fallback to stale cached metadata.

Evidence sources: [POSTHUMAN Limonata guide](https://nodes.posthuman.digital/chains/limonata),
[current Limonata release](https://github.com/Limonata-Blockchain/limonata/releases/tag/limonata-v0.3.6).
