# Limonata Testnet Node — Manual Guide

Ringkasan langkah manual di balik menu `valleyofLimonata.sh`. Sumber:
https://limonata.xyz/VALIDATOR.md (perintah diambil verbatim).

## Install binary

Prebuilt:
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

## Init + genesis

```bash
MONIKER="your-moniker"
limonatad init "$MONIKER" --chain-id limonata_10777-1
curl -s https://limonata.xyz/genesis.json -o ~/.limonatad/config/genesis.json
limonatad genesis validate-genesis
```

## Network config

```bash
CFG=~/.limonatad/config/config.toml
APP=~/.limonatad/config/app.toml
sed -i 's#^persistent_peers =.*#persistent_peers = "4b154368aab24cb5b31c927efd50c73d0f4f9799@142.127.103.79:26656"#' "$CFG"
sed -i 's/^type = "flood"/type = "app"/' "$CFG"
sed -i 's/^minimum-gas-prices = .*/minimum-gas-prices = "0aLIMO"/' "$APP"
```

Port 26656 (P2P) harus publicly reachable.

## Start

```bash
limonatad start --chain-id limonata_10777-1 --evm.evm-chain-id 10777 --minimum-gas-prices 0aLIMO
limonatad status 2>&1 | grep -o '"catching_up":[a-z]*'
```

Installer Valley of memasang ini sebagai systemd service `limonatad.service`.

## Validator

```bash
limonatad keys add operator            # simpan mnemonic offline
# fund via https://faucet.limonata.xyz
limonatad comet show-validator         # pubkey untuk validator.json
limonatad tx staking create-validator validator.json \
  --from operator --chain-id limonata_10777-1 --gas auto --gas-adjustment 1.3 --fees 0aLIMO -y
limonatad query staking validator <cosmosvaloper1...>
```

`validator.json`: pubkey dari `comet show-validator`, amount dalam aLIMO
(mis. `1000000000000000000aLIMO` = 1 LIMO), `min-self-delegation: "1"`.

Setelah aktif: kirim alamat operator + valoper ke tim Limonata untuk delegasi stake.

## Belum tersedia dari upstream (per 2026-07-02)

- Snapshot resmi — sync from genesis.
- Cosmovisor / on-chain upgrade flow.
- RPC publik + explorer — status node dicek dari RPC lokal.
