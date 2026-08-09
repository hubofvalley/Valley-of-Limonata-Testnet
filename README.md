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
- Binary: `limonatad` (cosmos/evm single binary — no separate execution client)
- Service: `limonatad.service`
- Genesis: https://limonata.xyz/genesis.json
- Faucet: https://faucet.limonata.xyz

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

- Deploy/re-deploy Limonata node (prebuilt or source, validated ports, optional state sync, UFW, systemd)
- Verify and update the Limonata binary with automatic rollback on service failure
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
