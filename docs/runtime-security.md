# Limonata runtime security preflight

`resources/limonata_runtime_security.sh` is a read-only configuration and binary
preflight for a Limonata node. It is intentionally narrower than a general
vulnerability scanner: it evaluates only security findings that have been
independently mapped to the exact runtime evidence the checker can establish.

Run it from a repository checkout:

```bash
bash resources/limonata_runtime_security.sh
```

The checker does not restart services, edit configuration, inspect private keys,
change firewall rules, or submit transactions.

## What it checks

### Reviewed Limonata release source

The current reviewed release contract is `limonata-v0.3.6`, commit
`effa377d673fc6f0fb307a78ca54e037e53060f7`.

Cosmos EVM published critical advisory
[`GHSA-367m-g444-9mg3`](https://github.com/cosmos/evm/security/advisories/GHSA-367m-g444-9mg3)
for a non-atomic `StateDB.Commit` path. The exact Limonata v0.3.6 commit was
checked rather than classified from its custom version number:

- Limonata v0.3.6 `x/vm/statedb/statedb.go` is source-identical to the same file
  in affected Cosmos EVM v0.7.2 and writes the final commit directly to the
  transaction context;
- Limonata v0.3.6 `x/erc20/keeper/ibc_callbacks.go` is also source-identical to
  the affected Cosmos EVM v0.7.2 callback path that can swallow a failed refund
  reconversion; and
- patched Cosmos EVM v0.7.3 stages the final StateDB writes in a cache context
  and publishes them only after the complete commit succeeds.

For that exact reviewed Limonata commit, the preflight therefore reports a hard
security finding until Limonata publishes a coordinated release carrying an
equivalent atomic-commit fix. This is a **source-equivalence verdict**, not a
claim that the public Limonata testnet is currently exploitable: live ERC20/IBC
state and reachability are separate questions, and the checker does not attempt
to reproduce an exploit.

A binary claiming v0.3.6 with a different or missing commit is `UNKNOWN`; the
checker refuses to transfer the verdict to different source. Other Limonata
versions are not automatically classified by this release-specific rule.

### gRPC-Go runtime dependency

- reads `google.golang.org/grpc` from the active Go binary with
  `go version -m` rather than assuming the dependency from a release name;
- evaluates that embedded version against `CVE-2026-84304 /
  GHSA-vp52-pcj8-j9qc`, whose published affected range is gRPC-Go `<=1.83.0`
  and whose first fixed version is `1.83.1`;
- if the binary is in the affected range, checks the `[grpc]` enable/address
  settings in `app.toml` and fails when the configured listener is non-loopback;
- reports a warning when an affected gRPC-Go version is present but the listener
  is loopback-only, so operators can track the release risk without treating a
  local-only listener as proven remote exposure.

### EVM JSON-RPC signing surface

The checker inspects `[json-rpc]` HTTP/WS listeners. A non-loopback listener with
`eth` or `personal` enabled is reported as a warning because Limonata upstream
PR #13 documents a server-side signing risk when that configuration is also
combined with a non-empty keyring. This preflight deliberately does **not**
inspect keyring contents, so it does not claim that the full PR #13 condition is
met.

## Result semantics

- `PASS` - the specific check was proven safe for the condition being tested.
- `WARN` - a verified risk signal exists but the checker did not prove an
  immediately exploitable runtime condition.
- `FAIL` - a verified hard security finding applies to the exact evidence the
  checker established, such as the reviewed v0.3.6 StateDB source finding or an
  affected gRPC-Go server configured on a non-loopback listener.
- `UNKNOWN` - required binary metadata or configuration could not be established.
  Unknown state is not silently treated as ready.

Exit codes are `0` for no hard failures/unknowns (warnings may exist), `1` for a
hard failure, and `2` when a required check is unknown and no hard failure exists.

## Scope and limitations

This preflight does not prove that a service is reachable from the public
internet. Reverse proxies, containers, network namespaces, NAT, and systemd or
CLI flag overrides can change effective exposure beyond what `app.toml` alone
shows. Treat a non-loopback configuration as a reason to review the complete
network path, and treat a loopback result as configuration evidence rather than
an external reachability proof.

The source-level StateDB verdict is deliberately pinned to the exact reviewed
Limonata v0.3.6 commit. It does not infer vulnerability from Limonata's version
number alone and does not substitute for upstream vulnerability coordination.
Do not build or deploy an unofficial validator binary merely to incorporate an
upstream security patch; wait for a coordinated, authenticated Limonata release.

Likewise, a dependency version newer than one affected range only closes that
specific advisory check. It does not certify the entire binary or node. Always
use the coordinated, authenticated Limonata release path.
