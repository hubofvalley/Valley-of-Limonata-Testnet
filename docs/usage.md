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

On first run the script asks for a **service name** (default `limonatad`) and saves it
to `~/.bash_profile` — it will not ask again. Run the script as the same user that
owns `~/.limonatad` to avoid permission issues.

## Navigation

- Choose an option by typing the number + letter together (e.g. `1a`), or the number
  first, Enter, then the letter.
- `yes`/`no` prompts require the full word; press Enter to accept defaults shown in
  parentheses.
- After exiting, run `source ~/.bash_profile` so environment variables set by the
  script apply to your current shell session.

## Menu options explained

### 1. Node Interactions

| Option | What it does | When to use |
|---|---|---|
| **1a. Deploy/Re-deploy Limonata Node** | Shows a full disclaimer (services created, ports, directories), then runs the installer: installs dependencies, downloads `limonatad` (prebuilt or build from source), initializes the node with your moniker, fetches genesis, sets peers/mempool/gas price per the official guide, applies your custom port prefix, creates and starts `limonatad.service`. **Re-running deletes the existing node data** (`~/.limonatad`) — backup keys first. | First setup, or clean re-install. |
| **1b. Update Limonata Binary** | Stops the service, downloads the latest official release binary, replaces `/usr/local/bin/limonatad`, restarts the service. Node data and keys are untouched. | When upstream announces a new release. |
| **1c. Add Peers** | Edits `persistent_peers` in `~/.limonatad/config/config.toml`: enter peers manually (comma-separated `id@host:port`) or reset to the official seed peer. Restart the node afterwards (3a). | Node stuck finding peers / after network changes. |
| **1d. Show Node Status** | Queries your local node RPC: current block height and `catching_up`. `catching_up: false` = fully synced. | Check sync progress; prerequisite check before creating a validator. |
| **1e. Show Node Logs** | Live-tails `journalctl -u limonatad -fn 100`. Press Ctrl+C to return to the menu. | Debugging, watching sync. |

### 2. Validator/Key Interactions

| Option | What it does | When to use |
|---|---|---|
| **2a. Create/Recover Operator Key** | `limonatad keys add <name>` (new key — **write the mnemonic down offline**, shown once) or `--recover` (restore from existing mnemonic). Shows the faucet link to fund the address. | Before creating a validator; after reinstalling a server. |
| **2b. Show Validator Consensus Pubkey** | Prints `limonatad comet show-validator` — the consensus pubkey embedded in `validator.json`. | Reference/verification; the create-validator flow reads it automatically. |
| **2c. Create Validator** | Guided flow: asks key name, moniker, self-stake amount in LIMO (converted to aLIMO), commission rates, website/details; builds `validator.json`, shows it for confirmation, submits `tx staking create-validator` with zero fees. Requires: node synced (1d) + operator key funded (2a + faucet). | Once, when registering your validator. |
| **2d. Query Balance** | `limonatad query bank balances` for a local keyring key or any address. Amounts are in aLIMO (1 LIMO = 10^18 aLIMO). | Verify faucet funds arrived; check balances. |
| **2e. Delegate Tokens** | `tx staking delegate` to your own validator (valoper derived from the `operator` key) or any validator address you enter. | Increase self-stake or support another validator. |
| **2f. Query Validator Status** | `limonatad query staking validator <valoper>` — bonding status, tokens, commission. | Confirm validator is active/bonded after 2c; monitor stake. |

### 3. Node Management

| Option | What it does | When to use |
|---|---|---|
| **3a. Restart Limonata Node** | `systemctl restart limonatad` (with daemon-reload). | After config changes (peers, ports). |
| **3b. Stop Limonata Node** | `systemctl stop limonatad`. | Maintenance; before manual data operations. |
| **3c. Delete Limonata Node** | **Destructive.** Stops and disables the service, removes the service file, deletes `~/.limonatad` and the binary, cleans `LIMONATA_*` vars from `~/.bash_profile`. Asks for confirmation first. **Backup your mnemonic and `priv_validator_key.json` before this** — deleting without backup permanently loses your validator identity. | Decommissioning the node. |
| **3d. Backup Validator Key** | Copies `~/.limonatad/config/priv_validator_key.json` to `$HOME`. Move it somewhere safe and offline afterwards. | Immediately after deploy; before any delete/re-deploy. |

### 4. Show Endpoints & Useful Links
Official Limonata links (website, validator guide, faucet, GitHub), network facts
(chain IDs, seed peer, genesis URL), and Grand Valley contacts.

### 5. Show Guidelines
In-tool summary of navigation, the recommended validator flow, and safety notes.

### 6. Exit
Leaves the script. Remember `source ~/.bash_profile`.

## Recommended first-time flow

1. `1a` deploy → wait until `1d` shows `catching_up: false`
2. `2a` create operator key → fund via https://faucet.limonata.xyz → confirm with `2d`
3. `2c` create validator → confirm with `2f`
4. `3d` backup validator key immediately
5. Send your operator + valoper addresses to the Limonata team for stake delegation

## Safety notes

- Never share private keys or mnemonics; the script never sends data off your server.
- Testnet tokens are valueless; stake delegated by the Limonata team remains team property.
- Audit any script before running it — this one lives at
  https://github.com/hubofvalley/Valley-of-Limonata-Testnet/blob/main/resources/valleyofLimonata.sh
