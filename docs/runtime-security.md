# Limonata runtime security preflight

`resources/limonata_runtime_security.sh` is a read-only configuration and binary
preflight for a Limonata node. It is intentionally narrower than a vulnerability
scanner: it checks one verified runtime advisory against the **actual embedded
module version** in the active binary, then correlates that result with the local
listener configuration.

Run it from a repository checkout:

```bash
bash resources/limonata_runtime_security.sh
```

The checker does not restart services, edit configuration, inspect private keys,
change firewall rules, or submit transactions.

## What it checks

- reads `google.golang.org/grpc` from the active Go binary with
  `go version -m` rather than assuming the dependency from a release name;
- evaluates that embedded version against `CVE-2026-84304 /
  GHSA-vp52-pcj8-j9qc`, whose published affected range is gRPC-Go `<=1.83.0`
  and whose first fixed version is `1.83.1`;
- if the binary is in the affected range, checks the `[grpc]` enable/address
  settings in `app.toml` and fails when the configured listener is non-loopback;
- reports a warning when an affected gRPC-Go version is present but the listener
  is loopback-only, so operators can track the release risk without treating a
  local-only listener as proven remote exposure; and
- checks `[json-rpc]` HTTP/WS listeners. A non-loopback listener with `eth` or
  `personal` enabled is reported as a warning because Limonata upstream PR #13
  documents a server-side signing risk when that configuration is also combined
  with a non-empty keyring. This preflight deliberately does **not** inspect
  keyring contents, so it does not claim that the full PR #13 condition is met.

## Result semantics

- `PASS` - the specific check was proven safe for the condition being tested.
- `WARN` - a verified risk signal exists but the checker did not prove an
  immediately exploitable runtime condition.
- `FAIL` - an embedded gRPC-Go version in the published affected range is
  configured on a non-loopback gRPC listener.
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

The checker also does not replace Limonata release coordination. A dependency
version newer than the affected range only closes this one advisory check; it
does not certify the binary or make an unofficial build safe for validator use.
Always use the coordinated, authenticated Limonata release path.
