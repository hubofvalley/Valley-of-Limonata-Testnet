# Limonata snapshot metadata preflight

Valley provides a **read-only** preflight for the currently documented POSTHUMAN
Limonata testnet snapshot. The provider currently publishes a moving `latest`
archive, `snapshot.json` and `SHA256SUMS`. The preflight compares their declared
chain, filename, size and digest; checks the archive's HTTP `Content-Length`
without downloading archive bytes; checks two reviewed public CometBFT RPCs for
chain ID, height, sync status and recent latest-block timestamps; and fails
closed if provider metadata changes during the check.

The RPC freshness limit is reviewed in `VERSIONS.json` (currently 600 seconds).
The reviewed RPC pair is POSTHUMAN and ANODE, matching the independent
testnet witnesses used by the state-sync installer review. On 2026-11-11,
both reported the same `limonata_10777-1` block/commit at height 5455000;
the previously configured `cosmos-rpc.limonata.xyz/status` returned HTTP 503
with a maintenance response, so it cannot satisfy the mandatory live RPC
check. This endpoint selection is **not** an automatic fallback or a claim
that either provider will remain available. If either reviewed RPC fails,
the preflight must still return `UNKNOWN`.
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

This preflight also does **not** impose a maximum snapshot age or block lag.
It reports `SNAPSHOT_AGE_SECONDS` using the provider's untrusted
`snapshot_time` and the local UTC clock. Missing, malformed, or future
timestamps report `UNKNOWN` rather than an invented zero age. The reported
`SNAPSHOT_LAG_BLOCKS` is the snapshot height subtracted from the *lower*
of the two validated RPC heights, a conservative lower bound on observed
lag. Both are informational and do **not** change the existing
`PRECHECK_PASS (metadata consistency only)` result or grant permission
to restore. In particular, a stale archive can still pass the metadata
preflight. Treat its age and lag as explicit operator decision inputs, not
cryptographic proof of recovery readiness.

On 2026-11-12 the publicly available POSTHUMAN metadata still dated the
archive 2026-11-07T19:33:15Z (height 5,363,250), while ANODE reported
height above 5,476,000. The reviewed POSTHUMAN RPC returned HTTP 502 and
the official Cosmos RPC HTTP 503 during this check, so a successful
two-witness live preflight was **not** established on that date. The
diagnostic addition is validated with deterministic fixtures; it does not
weaken the mandatory two-RPC fail-closed gate or introduce a fallback.

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
