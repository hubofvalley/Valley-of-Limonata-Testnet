# Limonata upgrade readiness

`resources/limonata_upgrade_readiness.sh` is a read-only preflight for a
Valley-managed Limonata node. Run it before a coordinated upgrade, or as a
periodic safety check while waiting for the next upgrade plan:

```bash
bash resources/limonata_upgrade_readiness.sh
```

The checker does not restart services or change node files. It inspects:

- the effective systemd/Cosmovisor environment;
- whether validator-oriented binary auto-download remains disabled;
- whether checksum enforcement remains enabled;
- whether Cosmovisor automatic data backup is enabled or explicitly skipped;
- backup filesystem headroom when automatic backup is enabled;
- the local CometBFT RPC, chain ID, height, and sync state;
- the current on-chain `x/upgrade` plan using the installed `limonatad` query
  command; and
- whether the binary for a scheduled upgrade is already staged under the
  expected Cosmovisor directory, including its local SHA-256 and reported
  version.

The result uses `PASS`, `WARN`, `FAIL`, and `UNKNOWN` states. `UNKNOWN` is not
silently treated as ready: the command exits with status `2` when a required
check cannot be completed and there are no harder failures. Hard failures exit
with status `1`.

## Backup warning

Current Valley installations created before this checker may explicitly set
`UNSAFE_SKIP_BACKUP=true`. The checker reports that as a warning rather than
changing the service. Cosmovisor v1.7.1 defaults this option to `false` and
recommends keeping backups enabled for rollback safety. Whether an operator
should change an existing validator's backup policy depends on verified disk
capacity and recovery procedures, so this read-only preflight does not make
that decision automatically.

## Scope

This is a readiness check, not an upgrade installer. A staged binary being
present does **not** prove that it is the correct future Limonata release. The
operator must still verify the release metadata, signature/checksum, exact
upgrade name, and coordinated upgrade instructions published by Limonata
before staging or running a new binary.
