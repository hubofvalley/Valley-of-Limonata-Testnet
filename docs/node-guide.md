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

The upstream v0.3.6 release documents a mandatory coordinated upgrade at block
`1,650,000`, but it also deliberately preserves legacy behavior before the
upgrade gate and reports a successful genesis-to-head replay with zero app-hash
divergence. Valley therefore uses v0.3.6 as the fresh-install genesis binary.
That replay compatibility does not authorize an already-running validator to
activate a coordinated upgrade early.

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
`go.mod` declares Go `1.25.9`; Valley currently installs Go `1.26.5` for its
source-build/Cosmovisor toolchain.

```bash
git clone --depth 1 --branch limonata-v0.3.6 \
  https://github.com/Limonata-Blockchain/limonata.git
cd limonata
git rev-parse HEAD
# Must equal effa377d673fc6f0fb307a78ca54e037e53060f7
make install
```

## Initialise the node and fetch genesis

```bash
MONIKER="your-moniker"
LIMONATA_HOME="$HOME/.limonatad"
limonatad --home "$LIMONATA_HOME" init "$MONIKER" --chain-id limonata_10777-1
curl -fsSL https://limonata.xyz/genesis.json -o "$LIMONATA_HOME/config/genesis.json"
limonatad --home "$LIMONATA_HOME" genesis validate-genesis
```

## Cosmovisor layout

New Valley deployments run `limonatad` through Cosmovisor from the start. The
installer pins Cosmovisor `v1.7.1`, disables binary auto-downloads, and creates:

```text
$HOME/.limonatad/cosmovisor/
  genesis/bin/limonatad
  current -> genesis
  upgrades/
  backup/
```

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

State sync uses the CometBFT RPC endpoint, not the EVM JSON-RPC endpoint.

```bash
CFG="$HOME/.limonatad/config/config.toml"
RPC="https://cosmos-rpc.limonata.xyz"
LATEST=$(curl -fsS "$RPC/block" | jq -r '.result.block.header.height')
TRUST=$(( (LATEST - 2000) / 1000 * 1000 ))
HASH=$(curl -fsS "$RPC/commit?height=$TRUST" | jq -r '.result.signed_header.commit.block_id.hash')

sed -i "/^\[statesync\]/,/^\[/ { \
  s/^enable *=.*/enable = true/; \
  s#^rpc_servers *=.*#rpc_servers = \"$RPC,$RPC\"#; \
  s/^trust_height *=.*/trust_height = $TRUST/; \
  s/^trust_hash *=.*/trust_hash = \"$HASH\"/; \
  s/^trust_period *=.*/trust_period = \"168h0m0s\"/ }" "$CFG"
```

Choosing state sync means the node starts from a trusted state snapshot rather
than executing every block from genesis. Disable state sync if you explicitly
want a full block-1 replay.

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

Do not replace `/usr/local/bin/limonatad` directly on a new Valley deployment;
it is a symlink to `cosmovisor/current/bin/limonatad`. Menu option `1b` detects
this and refuses direct replacement. A future coordinated upgrade must be staged
under the exact on-chain upgrade name from reviewed release metadata.

## Create a validator

```bash
limonatad --home "$HOME/.limonatad" keys add operator
limonatad --home "$HOME/.limonatad" comet show-validator
limonatad --home "$HOME/.limonatad" tx staking create-validator validator.json \
  --from operator --chain-id limonata_10777-1 \
  --gas auto --gas-adjustment 1.4 --gas-prices 1000000000aLIMO -y
limonatad --home "$HOME/.limonatad" query staking validator <cosmosvaloper1...>
```

Store every mnemonic offline. In `validator.json`, use the public key returned by
`comet show-validator`, express self-bond in aLIMO, and keep
`min-self-delegation` at `"1"` unless upstream policy changes.

last updated by: John
