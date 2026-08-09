# Valley of Limonata — Usage Guide

How to run the tool, how to navigate it, and what every menu option does.

## Running the tool

```bash
bash <(curl -s https://raw.githubusercontent.com/hubofvalley/Valley-of-Limonata-Testnet/main/resources/valleyofLimonata.sh)
```

Or from a local clone:

```bash
bash resources/valleyofLimonata.sh
```

On first run, the script shows its privacy and safety statement before asking for a
**service name** (default `limonatad`). It saves the validated name to
`~/.bash_profile` and will not ask again. Run the script as the same user that owns
`~/.limonatad` to avoid permission issues.

The wrapper forces `LIMONATA_HOME=$HOME/.limonatad` for CLI calls because the
upstream binary can otherwise fall back to its `evmd` default home.

## Navigation

- Choose an option by typing the number + letter together (e.g. `1a`), or the number
  first, Enter, then the letter.
- Normal confirmations require the full word `yes` or `no`; press Enter to accept
  defaults shown in parentheses. Destructive actions require the exact words
  `REDEPLOY` or `DELETE`, and replacing an existing key backup requires `OVERWRITE`.
- After exiting, run `source ~/.bash_profile` so environment variables set by the
  script apply to your current shell session.

## Menu options explained

### 1. Node Interactions

| Option | What it does | Risk | When to use |
|---|---|---|---|
| **1a. Deploy/Re-deploy Limonata Node** | Shows a full safety disclaimer, then asks for a moniker, validated two-digit port prefix, indexer, pruning, state sync, installation method, optional UFW settings, and service name. It installs dependencies, fetches `limonatad`, initializes the node, configures the network, and starts the service. Existing installations require typing `REDEPLOY`. | **Destructive on re-deploy:** permanently removes `~/.limonatad`, including local block data and `priv_validator_key.json`. Back up keys first. | First setup or a deliberate clean re-install. |
| **1b. Update Limonata Binary** | Downloads and verifies the latest official release before stopping the service. It preserves the previous binary and restores it if the updated service fails to start. Node data and keys are untouched. | Service restart; brief downtime. | When upstream announces a new release. |
| **1c. Add Peers** | Edits `persistent_peers` in `~/.limonatad/config/config.toml`: enter peers manually or reset to the official peer. Restart the node afterwards with 3a. | Configuration change. | When the node cannot find peers or after network changes. |
| **1d. Show Node Status** | Reads the local RPC port, prints local RPC status, and compares local height with the Limonata EVM RPC. A small negative difference is normal when the local node is ahead of the public RPC. | Read-only. | Check sync progress; required before creating a validator. |
| **1e. Show Node Logs** | Live-tails `journalctl -u limonatad -fn 100`. Press Ctrl+C to return to the menu. | Read-only. | Debugging or watching sync. |

### 2. Validator/Key Interactions

| Option | What it does | Risk | When to use |
|---|---|---|---|
| **2a. Create/Recover Operator Key** | Creates a new key or recovers one from an existing mnemonic. | **Key operation:** a new mnemonic is shown once; store it offline and never share it. | Before creating a validator or after reinstalling a server. |
| **2b. Show Validator Consensus Pubkey** | Prints the consensus public key used in `validator.json`. | Read-only. | Reference or verification before validator creation. |
| **2c. Create Validator** | Verifies the selected key and sync state, validates stake and commission values, builds `validator.json`, shows it for approval, then uses the official `1000000000aLIMO` staking gas price. | **On-chain transaction:** review every value before typing `yes`. | Once, when registering the validator. |
| **2d. Query Balance** | Queries bank balances for a local keyring key or any address. Amounts are shown in aLIMO. | Read-only. | Verify faucet funds or inspect an address. |
| **2e. Delegate Tokens** | Uses the selected key for self-delegation or delegates to a manually entered validator. It validates the amount and displays a final transaction review. | **On-chain transaction:** requires explicit `yes` before broadcast. | Increase self-stake or delegate a foundation grant from its separate grant wallet. |
| **2f. Query Validator Status** | Queries bonding status, tokens, and commission by valoper address. | Read-only. | Confirm the validator is bonded or monitor stake. |

### 3. Node Management

| Option | What it does | Risk | When to use |
|---|---|---|---|
| **3a. Restart Limonata Node** | Restarts the configured systemd service after daemon-reload. | Brief downtime. | After configuration changes. |
| **3b. Stop Limonata Node** | Stops the configured systemd service. | Node downtime. | Maintenance or before manual data operations. |
| **3c. Delete Limonata Node** | Stops and disables the service, removes its unit, deletes `~/.limonatad` and the binary, and cleans `LIMONATA_*` variables. Requires typing `DELETE`. | **Destructive:** deleting without backups permanently loses the validator identity. | Deliberate decommissioning only. |
| **3d. Backup Validator Key** | Copies `priv_validator_key.json` to `$HOME` with mode `600`. If a backup already exists, replacement requires typing `OVERWRITE`. Move the file somewhere safe and offline afterwards. | Writes a sensitive local backup file. | Immediately after deployment and before delete/re-deploy. |

### 4. Show Endpoints & Useful Links
Official Limonata links (website, validator guide, faucet, GitHub), network facts
(chain IDs, seed peer, genesis URL), and Grand Valley contacts.

### 5. Show Guidelines
In-tool summary of navigation, the recommended validator flow, and safety notes.

### 6. Exit
Leaves the script. Remember `source ~/.bash_profile`.

## Recommended first-time flow

1. `1a` deploy → wait until `1d` shows `catching_up: false`
2. `3d` back up the validator key immediately
3. `2a` create operator key → fund via https://faucet.limonata.xyz → confirm with `2d`
4. `2c` create validator → review the transaction → confirm with `2f`
5. Build a reliable track record, then apply at https://limonata.xyz/#validator with
   the valoper address and a new, never-funded grant-wallet address

## Installer choices

- **Transaction indexer ON** keeps transaction indexing enabled (`indexer = "kv"`), useful when you want transaction search/query tooling.
- **Transaction indexer OFF** sets `indexer = "null"`, lighter on disk and IO, but transaction search is limited.
- **Custom pruning ON** sets `pruning = "custom"`, `pruning-keep-recent = "100"`, and `pruning-interval = "19"`. This keeps only recent state needed by normal validators and prunes older state every 19 blocks to reduce disk growth.
- **Custom pruning OFF** leaves upstream defaults unchanged.
- **State sync ON** obtains a trusted height and hash from the official CometBFT RPC (`https://cosmos-rpc.limonata.xyz`) for a much faster initial sync. If trust data is unavailable, the installer asks before falling back to genesis sync.
- **State sync OFF** performs a normal sync from genesis.
- **UFW ON** asks for the current SSH port before enabling the firewall, then keeps SSH and the selected Limonata P2P port reachable.

## Safety notes

- Never share private keys or mnemonics; the script never sends data off your server.
- Testnet tokens are valueless; stake delegated by the Limonata team remains team property.
- Staking transactions require the official minimum gas price of `1000000000aLIMO`.
- Audit any script before running it — this one lives at
  https://github.com/hubofvalley/Valley-of-Limonata-Testnet/blob/main/resources/valleyofLimonata.sh

last updated by: John
