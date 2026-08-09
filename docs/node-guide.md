# Limonata Testnet Node — Manual Guide

This guide summarises the manual commands behind `valleyofLimonata.sh`. The
source of truth is the [official Limonata validator guide](https://limonata.xyz/VALIDATOR.md).

## Install the binary

Prebuilt binary:

```bash
curl -sL https://github.com/Limonata-Blockchain/limonata/releases/latest/download/limonatad-linux-amd64.tar.gz | tar xz
sudo install limonatad /usr/local/bin/
limonatad version
```

Build from source (Go 1.26+, CGO enabled):

```bash
git clone https://github.com/Limonata-Blockchain/limonata.git && cd limonata
make install
```

## Initialise the node and fetch genesis

```bash
MONIKER="your-moniker"
LIMONATA_HOME="$HOME/.limonatad"
limonatad --home "$LIMONATA_HOME" init "$MONIKER" --chain-id limonata_10777-1
curl -s https://limonata.xyz/genesis.json -o "$LIMONATA_HOME/config/genesis.json"
limonatad --home "$LIMONATA_HOME" genesis validate-genesis
```

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

TCP port 26656 (P2P) must be publicly reachable.

## Optional state sync

State sync requires Limonata v0.3.3 or newer. Use the CometBFT RPC endpoint,
not the EVM JSON-RPC endpoint.

```bash
CFG="$HOME/.limonatad/config/config.toml"
RPC="https://cosmos-rpc.limonata.xyz"
LATEST=$(curl -s "$RPC/block" | jq -r '.result.block.header.height')
TRUST=$(( (LATEST - 2000) / 1000 * 1000 ))
HASH=$(curl -s "$RPC/commit?height=$TRUST" | jq -r '.result.signed_header.commit.block_id.hash')

sed -i "/^\[statesync\]/,/^\[/ { \
  s/^enable *=.*/enable = true/; \
  s#^rpc_servers *=.*#rpc_servers = \"$RPC,$RPC\"#; \
  s/^trust_height *=.*/trust_height = $TRUST/; \
  s/^trust_hash *=.*/trust_hash = \"$HASH\"/; \
  s/^trust_period *=.*/trust_period = \"168h0m0s\"/ }" "$CFG"
```

For an existing node, stop the service and back up validator keys before running
the following destructive reset. A fresh Valley installation has no local block
state to reset and does not need this command.

```bash
sudo systemctl stop limonatad
BACKUP="$HOME/priv_validator_key.$(date +%Y%m%d-%H%M%S).json"
install -m 600 "$HOME/.limonatad/config/priv_validator_key.json" "$BACKUP"
limonatad tendermint unsafe-reset-all --home "$HOME/.limonatad" --keep-addr-book
```

## Start the node

```bash
limonatad start --home "$HOME/.limonatad" \
  --chain-id limonata_10777-1 \
  --evm.evm-chain-id 10777 \
  --minimum-gas-prices 0aLIMO

curl -s http://127.0.0.1:26657/status | jq '.result.sync_info'
```

The Valley installer runs this command through `limonatad.service`.

## Create a validator

```bash
limonatad --home "$HOME/.limonatad" keys add operator            # Store the mnemonic offline.
# Fund the operator address through https://limonata.xyz.
limonatad --home "$HOME/.limonatad" comet show-validator         # Use this public key in validator.json.
limonatad --home "$HOME/.limonatad" tx staking create-validator validator.json \
  --from operator --chain-id limonata_10777-1 \
  --gas auto --gas-adjustment 1.4 --gas-prices 1000000000aLIMO -y
limonatad --home "$HOME/.limonatad" query staking validator <cosmosvaloper1...>
```

In `validator.json`, use the public key returned by `comet show-validator`, set
the self-bond amount in aLIMO (`1000000000000000000aLIMO` = 1 LIMO), and keep
`min-self-delegation` set to `"1"`.

After the validator has established a reliable track record, apply through
https://limonata.xyz/#validator using the validator operator address and a new,
never-funded grant-wallet address. Do not create a second validator for the
grant.

## Features not currently available upstream

- Cosmovisor or a documented on-chain upgrade flow.
- A general-purpose block explorer.

last updated by: John
