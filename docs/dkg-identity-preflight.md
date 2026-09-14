# DKG identity preflight

Limonata's transparent encrypted-mempool DKG has a validator-specific health condition that ordinary staking and signing checks cannot prove.

In the reviewed `limonata-v0.3.6` source, a validator using a remote signer still needs the configured `priv_validator_key_file` path to exist so the DKG can resolve the validator's consensus identity. Upstream documented a failure mode where a validator could remain bonded, unjailed, and signing blocks while silently announcing no DKG encryption key, dealing nothing, and serving no decryption shares.

This matters especially after remote-signer migrations. Common Horcrux guidance removes `priv_validator_key.json` from the validator host to eliminate double-sign risk, while Limonata's DKG still needs an identity file at the configured path. Operators therefore need to satisfy both requirements without putting signing key material back on the validator host.

## Read-only check

```bash
LIMONATA_HOME="$HOME/.limonatad" \
LIMONATA_BIN="$HOME/go/bin/limonatad" \
bash resources/limonata_dkg_identity_preflight.sh
```

The checker:

- verifies the exact reviewed Limonata version and source commit before applying the rule;
- reads only `config.toml` to resolve `priv_validator_laddr` and `priv_validator_key_file`;
- mirrors Limonata's relative-path resolution and default key-path fallback;
- checks only filesystem metadata for the resolved identity path;
- fails closed when a remote signer is configured but the required identity path is missing or is not a regular file;
- never opens, parses, prints, copies, or hashes the priv-validator identity file.

A successful path-existence check is only a prerequisite check. It does **not** prove that the file contains the correct consensus address, that the validator is currently selected for the DKG committee, or that it is contributing dealings or decryption shares. Those require an independent semantic health signal.

## Exit codes

- `0`: reviewed rule checked with no verified hard failure; warnings may remain.
- `1`: verified remote-signer DKG identity prerequisite failure.
- `2`: the release or configuration could not be established safely.

## Safety boundary

Do not restore a signing private key to a validator host merely to satisfy this preflight. The upstream Limonata fix states that DKG self-identification needs the validator's real consensus **address** at the configured identity path; signing-key custody remains a separate remote-signer safety concern. Do not fabricate an identity-only file or restore signing-key material based on this checker. Obtain current upstream Limonata guidance for the required address-only identity representation before changing anything, and review the node's DKG logs before declaring participation healthy.
