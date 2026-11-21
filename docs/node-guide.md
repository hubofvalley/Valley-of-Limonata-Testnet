# Limonata Testnet Node — Manual Guide

This guide summarises the manual commands behind `valleyofLimonata.sh`. The
Valley installer is the canonical executable flow in this repository.

## Reviewed binary target

Valley pins fresh installs to the official Limonata release:

- release: `limonata-v0.3.6`
- commit: `effa377d673fc6f0fb307a78ca54e037e53060f7`
- artifact: `limonatad-linux-amd64.tar.gz`
- SHA-256: `39ff376963498de120604c273d50751afc005ebeec9cbcca88c0f732eff56125`
- release-signing fingerprint: `A45380198F390AF69126AE12E4ECEC477C1735FB`
- operator-facing binary path: `$HOME/go/bin/limonatad`

The upstream v0.3.6 release documents a mandatory coordinated upgrade at block
`1,650,000`, but it also deliberately preserves legacy behavior before the
upgrade gate and reports a successful genesis-to-head replay with zero app-hash
divergence. Valley therefore uses v0.3.6 as the fresh-install genesis binary.
That replay compatibility does not authorize an already-running validator to
activate a coordinated upgrade early.

The Valley installer supports Linux x86_64 (AMD64) only.

## Verify the official prebuilt binary

```bash
RELEASE=limonata-v0.3.6
BASE="https://github.com/Limonata-Blockchain/limonata/releases/download/$RELEASE"
mkdir -p /tmp/limonata-v036 && cd /tmp/limonata-v036
curl -fsSLO "$BASE/limonatad-linux-amd64.tar.gz"
curl -fsSLO "$BASE/SHA256SUMS.txt"
curl -fsSLO "$BASE/SHA256SUMS.txt.asc"
curl -fsSLO "$BASE/limonata-release-signing-key.asc"

gpg --show-keys --with-fingerprint limonata-release-signing-key.asc
# Confirm the fingerprint is exactly:
# A453 8019 8F39 0AF6 9126  AE12 E4EC EC47 7C17 35FB

gpg --import limonata-release-signing-key.asc
gpg --verify SHA256SUMS.txt.asc SHA256SUMS.txt
sha256sum -c --ignore-missing SHA256SUMS.txt

tar xzf limonatad-linux-amd64.tar.gz
./limonatad version --long | head -3
```

The Valley installer additionally compares the artifact against the pinned
SHA-256 above before installation.

## Build from source

The tagged source is pinned to the same full commit. The upstream v0.3.6
`go.mod` declares Go `1.25.9`; Valley installs the pinned Go `1.26.8` toolchain
only when the operator selects the source-build path.

```bash
git clone --depth 1 --branch limonata-v0.3.6 \
  https://github.com/Limonata-Blockchain/limonata.git
cd limonata
git rev-parse HEAD
# Must equal effa377d673fc6f0fb307a78ca54e037e53060f7
make install
```

Both the prebuilt and source paths converge on `$HOME/go/bin/limonatad` before
Cosmovisor is initialized.

## Authenticate testnet genesis before initializing the node

As observed on **2026-11-13**, the mutable official URL
`https://limonata.xyz/genesis.json` serves `limonata_20777-1`, **not** the
pinned testnet `limonata_10777-1`. Its SHA-256 does not match the reviewed
testnet digest. Do not use this URL to initialize a testnet node until the
upstream publishes a verifiable testnet-specific source. Do not remove the
checksum or switch this testnet tool to mainnet parameters. The automated
installer checks the candidate **before** installing a binary or initializing
a node home, but may still install OS prerequisites before this check.

For a later verified testnet source, the manual operation must preserve this
order: download into a temporary file, verify both digest and chain ID, then
initialize the node and install the authenticated genesis. The following
example deliberately refuses the currently mismatching URL:

```bash
MONIKER="your-moniker"
LIMONATA_HOME="$HOME/.limonatad"
GENESIS_CANDIDATE=$(mktemp)
if curl -fsSL https://limonata.xyz/genesis.json -o "$GENESIS_CANDIDATE" \
   && printf '%s  %s\n' \
      'bb76a6d8abbb1bdeaa41d92811066b16bd6a48f58f7136e3fcb71226b6af4569' \
      "$GENESIS_CANDIDATE" | sha256sum -c - \
   && jq -e '.chain_id == "limonata_10777-1"' "$GENESIS_CANDIDATE" >/dev/null; then
    if "$HOME/go/bin/limonatad" --home "$LIMONATA_HOME" init "$MONIKER" --chain-id limonata_10777-1 \
       && install -m 0644 "$GENESIS_CANDIDATE" "$LIMONATA_HOME/config/genesis.json" \
       && "$HOME/go/bin/limonatad" --home "$LIMONATA_HOME" genesis validate-genesis; then
        echo "Testnet genesis verified and installed."
    else
        echo "Node initialization or genesis validation failed; inspect partial state manually." >&2
    fi
else
    echo "REFUSED: upstream genesis is not the reviewed Limonata testnet genesis." >&2
fi
rm -f -- "$GENESIS_CANDIDATE"
```

## Cosmovisor layout

New Valley deployments run `limonatad` through Cosmovisor from the start. The
installer pins the official Cosmovisor `v1.7.3` Linux AMD64 release artifact
by SHA-256 and disables binary auto-downloads. It creates the following
per-node layout:

```text
$HOME/.limonatad/cosmovisor/
  genesis/bin/limonatad
  current -> genesis
  upgrades/
  backup/
```

The verified Cosmovisor executable is installed in the Limonata-private path
`$HOME/.local/libexec/valley-of-limonata/cosmovisor`, rather than replacing
`/usr/local/bin/cosmovisor` (which may be used by other chains). An existing
private executable is reused only when it is byte-identical to the verified
release artifact; other files and symlinks fail closed.

The user-facing command remains:

```text
$HOME/go/bin/limonatad
  -> $HOME/.limonatad/cosmovisor/current/bin/limonatad
```

That matches the Valley of Story pattern: operators use the normal binary name
from `~/go/bin`, while Cosmovisor owns the active executable behind the symlink.

For a full replay from block 1, Valley pre-stages the same v0.3.6 binary under
the Limonata-specific upgrade names registered by the v0.3.6 source:

```text
valgrant-v1
encmempool-threshold-vpcap-v1
gassponsor-security-caps-v1
encmempool-transparent-dkg-v1
encmempool-dkg-dealing-retention-v1
encmempool-strict-concentration-v1
```

This lets Cosmovisor traverse historical on-chain upgrade boundaries while the
application itself replays the correct historical behavior. `DAEMON_ALLOW_DOWNLOAD_BINARIES`
is `false`; no historical executable is fetched dynamically.

## Configure the network

```bash
CFG="$HOME/.limonatad/config/config.toml"
APP="$HOME/.limonatad/config/app.toml"
sed -i 's#^persistent_peers =.*#persistent_peers = "4b154368aab24cb5b31c927efd50c73d0f4f9799@142.127.103.79:26656"#' "$CFG"
sed -i 's/^type = "flood"/type = "app"/' "$CFG"
sed -i 's/^minimum-gas-prices = .*/minimum-gas-prices = "0aLIMO"/' "$APP"
```

Optional validator-friendly settings:

```bash
# Keep transaction indexing enabled:
sed -i 's/^indexer = .*/indexer = "kv"/' "$CFG"

# Or disable transaction indexing to reduce disk and IO use:
sed -i 's/^indexer = .*/indexer = "null"/' "$CFG"

# Use custom pruning for a normal validator:
sed -i 's/^pruning = .*/pruning = "custom"/' "$APP"
sed -i 's/^pruning-keep-recent = .*/pruning-keep-recent = "100"/' "$APP"
sed -i 's/^pruning-interval = .*/pruning-interval = "19"/' "$APP"
```

TCP port 26656, or the selected Valley-prefixed P2P port, must be publicly
reachable.

## Optional state sync

State sync uses CometBFT RPC endpoints, not EVM JSON-RPC. Valley of Limonata
requires two distinct, independently reviewed testnet RPC sources to agree on
a trusted commit. Distinct URLs alone do not prove independent operators.

**Do not copy runnable state-sync configuration commands from older versions of
this guide.** The former illustrative snippet could write `config.toml` after
comparing raw hashes, without checking chain identity, RPC block freshness,
bounded numeric heights, or the returned commit header. Copying it directly
could enable state sync from invalid or stale evidence.

For a fresh installation, use menu option `1a` with state sync ON. The
installer validates the two configured sources before it writes state-sync
settings: expected Cosmos chain ID, `catching_up=false`, valid heights,
fresh latest-block timestamps, a common trust height, and identical
well-formed commit evidence at that height. It refuses an unavailable,
stale, wrong-chain, malformed, or disagreeing witness; there is no automatic
unsafe fallback. Review actual operator independence separately.

Advanced operators may provide independently verified URLs through
`LIMONATA_STATE_SYNC_PRIMARY_RPC` and
`LIMONATA_STATE_SYNC_WITNESS_RPC`. These settings are inputs to validation,
not overrides of its fail-closed checks.

If two trustworthy, fresh testnet RPC sources are not available, do not
enable state sync. Switching to a full genesis replay also requires a
verified testnet genesis: the former public genesis URL currently serves
the separate `limonata_20777-1` network. Do not substitute mainnet evidence
or bypass genesis provenance checks. Neither mode should be described as
restore-ready until its prerequisites are independently verified.

## Start the node

The Valley systemd service starts Cosmovisor, which then starts `limonatad`:

```bash
cosmovisor run start --home "$HOME/.limonatad" \
  --chain-id limonata_10777-1 \
  --evm.evm-chain-id 10777 \
  --minimum-gas-prices 0aLIMO
```

Required Cosmovisor environment values include:

```bash
DAEMON_NAME=limonatad
DAEMON_HOME=$HOME/.limonatad
DAEMON_ALLOW_DOWNLOAD_BINARIES=false
DAEMON_DOWNLOAD_MUST_HAVE_CHECKSUM=true
DAEMON_RESTART_AFTER_UPGRADE=true
```

Check sync status with:

```bash
curl -s http://127.0.0.1:26657/status | jq '.result.sync_info'
```

## Updating a Valley deployment

Do not replace `$HOME/go/bin/limonatad` directly on a new Valley deployment; it
is a symlink to `cosmovisor/current/bin/limonatad`. Menu option `1b` detects this
and refuses direct replacement. A future coordinated upgrade must be staged
under the exact on-chain upgrade name from reviewed release metadata.

## Create a validator

```bash
$HOME/go/bin/limonatad --home "$HOME/.limonatad" keys add operator
$HOME/go/bin/limonatad --home "$HOME/.limonatad" comet show-validator
$HOME/go/bin/limonatad --home "$HOME/.limonatad" tx staking create-validator validator.json \
  --from operator --chain-id limonata_10777-1 \
  --gas auto --gas-adjustment 1.4 --gas-prices 1000000000aLIMO -y
$HOME/go/bin/limonatad --home "$HOME/.limonatad" query staking validator <cosmosvaloper1...>
```

Store every mnemonic offline. In `validator.json`, use the public key returned by
`comet show-validator`, express self-bond in aLIMO, and keep
`min-self-delegation` at `"1"` unless upstream policy changes.

## Genesis provenance during fresh installation

The installer downloads canonical testnet genesis into a temporary candidate
file and checks the pinned SHA-256 and Cosmos chain ID before copying it to the
node home and running the binary's `genesis validate-genesis` command. The
reviewed digest is recorded in `VERSIONS.json`. A digest mismatch, unavailable
candidate, malformed JSON or unexpected chain causes a fail-closed exit.
Genesis is retrieved from a mutable upstream URL, so maintainers must review
and independently verify a changed genesis before updating the pin.

If installation fails after initializing the node home, partial local files may
remain. The fresh-install guard intentionally refuses reruns; do not delete or
reset validator data automatically. Assess any recovery manually.

last updated by: John
