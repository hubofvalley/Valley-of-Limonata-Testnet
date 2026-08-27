# Valley of Limonata - Testnet

Interactive terminal tool by **Grand Valley** to deploy and manage a Limonata testnet validator node.

## System Requirements

| Category  | Requirements |
| --------- | ------------ |
| CPU       | 2+ vCPU      |
| RAM       | 4+ GB        |
| Storage   | 50+ GB SSD   |
| Bandwidth | 100+ MBit/s  |

- Chain: `Limonata Testnet`
- Chain ID: `limonata_10777-1` (EVM chain ID: `10777`, hex `0x2a19`)
- Native denom: `aLIMO` (1 LIMO = 10^18 aLIMO)
- Binary command: `~/go/bin/limonatad`
- Reviewed release: `limonata-v0.3.6` (`effa377d673fc6f0fb307a78ca54e037e53060f7`)
- Process manager: Cosmovisor (`v1.7.1` in the Valley installer)
- Active binary target: `~/.limonatad/cosmovisor/current/bin/limonatad`
- Service: `limonatad.service`
- Genesis: https://limonata.xyz/genesis.json
- Faucet: https://faucet.limonata.xyz

Fresh Valley installs use the official `v0.3.6` binary as the Cosmovisor genesis
binary. The operator-facing command lives at `~/go/bin/limonatad`, matching the
Valley of Story convention, and is symlinked to Cosmovisor's active `current`
binary. Upstream v0.3.6 is intentionally replay-compatible with pre-upgrade
history and was tested by Limonata from genesis to head without app-hash
divergence. Valley also pre-stages that same pinned binary under the historical
Limonata upgrade names needed during a full genesis replay. Automatic binary
downloads are disabled.

This does **not** mean an already-running validator should activate a coordinated
upgrade early. For live validators, follow the on-chain upgrade height and the
upstream release instructions.

Network notes: no staking inflation (`x/mint` disabled) — validators earn a share
of network transaction fees plus commission. Protocol-sponsored gas does not apply
to staking transactions; staking commands require a gas price of
`1000000000aLIMO`. Testnet tokens are valueless.

## Run

```bash
bash <(curl -s https://raw.githubusercontent.com/hubofvalley/Valley-of-Limonata-Testnet/main/resources/valleyofLimonata.sh)
```

## Documentation

- **[Usage guide — every menu option explained](docs/usage.md)**
- [Manual node guide (commands behind the menu)](docs/node-guide.md)

## Features

- Deploy/re-deploy Limonata node with pinned v0.3.6, Cosmovisor, validated ports, optional state sync, UFW, and systemd
- Keep the user-facing `limonatad` command in `~/go/bin`, symlinked to Cosmovisor `current`
- Verify the official v0.3.6 artifact with pinned SHA-256 plus the official GPG signing fingerprint
- Pre-stage replay-safe v0.3.6 across known historical Cosmovisor upgrade slots for genesis sync
- Protect Cosmovisor-managed nodes from direct replacement through the legacy updater
- Add/reset persistent peers
- Node status (block height, catching_up) and live logs
- Create/recover operator key, show validator consensus pubkey
- Create validator (guided `validator.json` + `tx staking create-validator`)
- Query balance, delegate tokens, query validator status
- Backup validator key, restart/stop/delete node

## Recommended validator flow

1. `1a` Deploy node, wait until `1d` shows `catching_up: false`
2. `3d` Backup `priv_validator_key.json` immediately
3. `2a` Create operator key, fund it via https://faucet.limonata.xyz
4. `2c` Review and submit the create-validator transaction
5. Build a reliable track record, then apply at https://limonata.xyz/#validator
   with the valoper address and a new, never-funded grant-wallet address

## Connect with Grand Valley

- X: https://x.com/bacvalley
- GitHub: https://github.com/hubofvalley
- Email: letsbuidltogether@grandvalleys.com

**Let's Buidl Limonata Together - Grand Valley**

last updated by: John
