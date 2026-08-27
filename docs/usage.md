# Valley of Limonata — Usage Guide

How to run the tool, navigate it, and understand each menu option.

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
`~/.bash_profile`. Run the script as the same user that owns `~/.limonatad`.

The wrapper forces `LIMONATA_HOME=$HOME/.limonatad` for CLI calls because the
upstream binary can otherwise fall back to its `evmd` default home.

## Navigation

- Choose an option by typing the number + letter together, for example `1a`.
- Normal confirmations require `yes` or `no`; destructive actions require the
  exact words shown by the tool, such as `REDEPLOY` or `DELETE`.
- After exiting, run `source ~/.bash_profile` if you want newly written variables
  in the current shell.

## Menu options explained

### 1. Node Interactions

| Option | What it does | Risk | When to use |
|---|---|---|---|
| **1a. Deploy/Re-deploy Limonata Node** | Installs the reviewed `limonata-v0.3.6` target, verifies the official artifact, installs pinned Cosmovisor, initializes the node, configures the network, and starts the systemd service through Cosmovisor. Existing installs require `REDEPLOY`. | **Destructive on re-deploy:** removes `~/.limonatad`, including local block data and `priv_validator_key.json`. | First setup or an intentional clean reinstall. |
| **1b. Update Limonata Binary** | On new Valley installs, detects the Cosmovisor-managed `current` symlink and refuses direct binary replacement. If the current target is already v0.3.6 it exits cleanly. The legacy direct-binary path remains only for older Valley installs. | Direct replacement of a Cosmovisor `current` binary is blocked. | Check whether a current Valley node needs a reviewed upgrade. |
| **1c. Add Peers** | Edits `persistent_peers` in `~/.limonatad/config/config.toml`. | Configuration change. | Peer/connectivity repair. |
| **1d. Show Node Status** | Reads the local RPC status and compares local height with the public Limonata RPC. | Read-only. | Check sync progress. |
| **1e. Show Node Logs** | Live-tails the configured systemd unit. | Read-only. | Debugging or watching sync. |

### 2. Validator/Key Interactions

| Option | What it does | Risk | When to use |
|---|---|---|---|
| **2a. Create/Recover Operator Key** | Creates a local key or recovers one from a mnemonic. | **Key operation.** | Before validator creation or after deliberate recovery. |
| **2b. Show Validator Consensus Pubkey** | Prints the consensus public key. | Read-only. | Build or verify `validator.json`. |
| **2c. Create Validator** | Validates the selected key and sync state, builds `validator.json`, and broadcasts the staking transaction after confirmation. | **On-chain transaction.** | Once, after the node is synced. |
| **2d. Query Balance** | Queries balances for a key or address. | Read-only. | Verify funding. |
| **2e. Delegate Tokens** | Delegates after validation and explicit confirmation. | **On-chain transaction.** | Self-stake or delegation. |
| **2f. Query Validator Status** | Queries bonding status, tokens, and commission. | Read-only. | Validator monitoring. |

### 3. Node Management

| Option | What it does | Risk | When to use |
|---|---|---|---|
| **3a. Restart Limonata Node** | Restarts the configured Cosmovisor-backed systemd service. | Brief downtime. | After configuration changes. |
| **3b. Stop Limonata Node** | Stops the service. | Node downtime. | Maintenance. |
| **3c. Delete Limonata Node** | Stops/disables the service and deletes the node home and binary link after `DELETE`. | **Destructive.** | Deliberate decommission only. |
| **3d. Backup Validator Key** | Copies `priv_validator_key.json` to `$HOME` with mode `600`. | Creates a sensitive local backup. | Immediately after deploy and before destructive work. |

### 4–6

Option 4 shows official endpoints and useful links. Option 5 shows the in-tool
operator guidelines. Option 6 exits.

## Fresh-install binary and Cosmovisor model

Valley currently pins:

- Limonata: `limonata-v0.3.6`
- source commit: `effa377d673fc6f0fb307a78ca54e037e53060f7`
- artifact SHA-256: `39ff376963498de120604c273d50751afc005ebeec9cbcca88c0f732eff56125`
- release-signing fingerprint: `A45380198F390AF69126AE12E4ECEC477C1735FB`
- Cosmovisor: `v1.7.1`
- Valley installer Go toolchain: `1.26.5`

The v0.3.6 source intentionally preserves legacy behavior before its coordinated
upgrade gate and upstream reports successful `genesis -> head` replay without
app-hash divergence. Valley therefore puts v0.3.6 in
`~/.limonatad/cosmovisor/genesis/bin/limonatad` for a fresh deployment.

For a full block-1 replay, the installer also pre-stages the same pinned binary
under these Limonata upgrade names:

```text
valgrant-v1
encmempool-threshold-vpcap-v1
gassponsor-security-caps-v1
encmempool-transparent-dkg-v1
encmempool-dkg-dealing-retention-v1
encmempool-strict-concentration-v1
```

This is specifically a **fresh/replay path**. It does not override upstream live
validator coordination rules. Upstream v0.3.6 is a consensus-breaking coordinated
upgrade at block `1,650,000`; an already-running validator should not activate it
outside the network's coordinated upgrade flow.

Cosmovisor auto-downloads are disabled. `/usr/local/bin/limonatad` points to
`cosmovisor/current/bin/limonatad`; do not replace that symlink with an arbitrary
binary.

## Recommended first-time flow

1. `1a` deploy, then wait until `1d` shows `catching_up: false`.
2. `3d` back up the validator key immediately.
3. `2a` create the operator key, fund it from the faucet, and confirm with `2d`.
4. `2c` create the validator and confirm with `2f`.
5. Build a reliable track record, then follow the current Limonata validator
   application process.

## Installer choices

- **Prebuilt (`p`)**: downloads the exact v0.3.6 release, checks the pinned GPG
  fingerprint, verifies the signed checksum file, and compares the artifact to
  the Valley-pinned SHA-256.
- **Source (`s`)**: clones tag `limonata-v0.3.6` and refuses to build unless it
  resolves to the pinned full commit.
- **Transaction indexer ON**: keeps `indexer = "kv"`; OFF uses `"null"`.
- **Custom pruning ON**: uses `keep-recent=100` and `interval=19`.
- **State sync ON**: starts from trusted state obtained from the official
  CometBFT RPC. If you explicitly want to execute from block 1, choose state
  sync OFF.
- **UFW ON**: preserves the SSH port you provide and opens the selected Limonata
  P2P port.

## Safety notes

- Never share private keys or mnemonics.
- Testnet tokens are valueless.
- Staking transactions use `1000000000aLIMO` gas price in the Valley flow.
- Audit operational scripts before running them, especially destructive deploy,
  delete, and upgrade paths.

last updated by: John
