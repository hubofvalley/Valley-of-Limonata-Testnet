#!/bin/bash

set -euo pipefail

if [ -z "${HOME:-}" ] || [ "$HOME" = "/" ]; then
    echo "Refusing installation because HOME is empty or unsafe: ${HOME:-<unset>}"
    exit 1
fi

# ==== CONFIG ====
echo -e "\n--- Limonata Testnet Node Setup ---"

LOGO="
 __
/__ ._ _. ._   _|   \  / _. | |  _
\_| | (_| | | (_|    \/ (_| | | (/_ \/
                                    /
"

echo "$LOGO"

# Input helpers
prompt_short_yes_no() {
    local prompt=$1 default_value=$2 answer
    while true; do
        read -r -p "$prompt" answer
        answer=${answer:-$default_value}
        case "${answer,,}" in
            y|n) printf '%s' "${answer,,}"; return ;;
            *) echo "Please enter y or n." >&2 ;;
        esac
    done
}

# Prompt for moniker, port prefix, and installation choices.
while [ -z "${LIMONATA_MONIKER:-}" ]; do
    read -r -p "Enter your LIMONATA_MONIKER: " LIMONATA_MONIKER
    [ -z "$LIMONATA_MONIKER" ] && echo "Moniker cannot be empty."
done

while true; do
    read -r -p "Enter a two-digit port prefix from 10 to 64 (default: 26): " LIMONATA_PORT
    LIMONATA_PORT=${LIMONATA_PORT:-26}
    if [[ "$LIMONATA_PORT" =~ ^([1-5][0-9]|6[0-4])$ ]]; then
        break
    fi
    echo "Invalid port prefix. Enter exactly two digits from 10 to 64."
done
echo
echo "Indexer setting:"
echo "- ON  = keeps the transaction indexer enabled, useful for search/query tooling."
echo "- OFF = disables transaction indexing, lighter on disk/IO but tx search will be limited."
LIMONATA_INDEXER_ENABLED=$(prompt_short_yes_no "Enable transaction indexer? (y/n, default y): " y)
echo
echo "Pruning setting:"
echo "- custom pruning keeps recent state only, reducing disk usage for normal validators."
echo "- pruning-keep-recent = 100 means keep the latest 100 recent states."
echo "- pruning-interval = 19 means prune every 19 blocks."
LIMONATA_CUSTOM_PRUNING=$(prompt_short_yes_no "Use custom pruning (keep-recent=100, interval=19)? (y/n, default y): " y)
LIMONATA_STATE_SYNC=$(prompt_short_yes_no "Enable official state sync for a faster initial sync? (y/n, default y): " y)
while true; do
    read -r -p "Install method - prebuilt binary or build from source? (p/s, default p): " INSTALL_METHOD
    INSTALL_METHOD=${INSTALL_METHOD:-p}
    [[ "${INSTALL_METHOD,,}" =~ ^(p|s)$ ]] && break
    echo "Please enter p for prebuilt or s for source."
done
SETUP_UFW=$(prompt_short_yes_no "Configure UFW firewall rules for Limonata? (y/n, default n): " n)
if [ "$SETUP_UFW" = "y" ]; then
    while true; do
        read -r -p "Enter the current SSH port that must remain reachable (default: 22): " SSH_PORT
        SSH_PORT=${SSH_PORT:-22}
        if [[ "$SSH_PORT" =~ ^[0-9]+$ ]] && [ "$SSH_PORT" -ge 1 ] && [ "$SSH_PORT" -le 65535 ]; then
            break
        fi
        echo "Invalid SSH port. Enter a number from 1 to 65535."
    done
fi

# Service Name Configuration (for multi-instance support)
if [ -z "${LIMONATA_SERVICE_NAME:-}" ]; then
    while true; do
        read -r -p "Enter service name (default 'limonatad'): " LIMONATA_SERVICE_NAME
        LIMONATA_SERVICE_NAME=${LIMONATA_SERVICE_NAME:-limonatad}
        [[ "$LIMONATA_SERVICE_NAME" =~ ^[A-Za-z0-9_.@-]+$ ]] && break
        echo "Invalid service name. Use letters, numbers, dots, underscores, @, or hyphens only."
        LIMONATA_SERVICE_NAME=""
    done
fi
if ! [[ "$LIMONATA_SERVICE_NAME" =~ ^[A-Za-z0-9_.@-]+$ ]]; then
    echo "Invalid service name. Use letters, numbers, dots, underscores, @, or hyphens only."
    exit 1
fi

echo "Using Service Name: ${LIMONATA_SERVICE_NAME}"

# Require explicit confirmation before an existing installation is removed.
if { [ -d "$HOME/.limonatad" ] || [ -f "/etc/systemd/system/${LIMONATA_SERVICE_NAME}.service" ] || command -v limonatad >/dev/null 2>&1; } \
    && [ "${LIMONATA_REDEPLOY_CONFIRMED:-0}" != "1" ]; then
    echo "WARNING: An existing Limonata installation was detected."
    echo "Re-deployment permanently deletes $HOME/.limonatad, including local block data and priv_validator_key.json."
    echo "Back up validator keys and store the operator mnemonic offline before continuing."
    read -r -p "Type REDEPLOY to confirm permanent deletion: " REDEPLOY_CONFIRM
    if [ "$REDEPLOY_CONFIRM" != "REDEPLOY" ]; then
        echo "Re-deployment cancelled. No existing node data was changed."
        exit 0
    fi
fi

# Stop and remove the existing Limonata node (idempotent re-deploy).
sudo systemctl daemon-reload
sudo systemctl stop "$LIMONATA_SERVICE_NAME" 2>/dev/null || true
sudo systemctl disable "$LIMONATA_SERVICE_NAME" 2>/dev/null || true
sudo rm -f "/etc/systemd/system/${LIMONATA_SERVICE_NAME}.service" 2>/dev/null || true
sudo rm -f /usr/local/bin/limonatad 2>/dev/null || true
sudo rm -rf "$HOME/.limonatad" 2>/dev/null || true
sed -i "/LIMONATA_/d" "$HOME/.bash_profile" 2>/dev/null || true

# 1. Install dependencies
sudo apt update -y
sudo apt install -y curl git jq bc build-essential gcc unzip wget lz4 openssl

# 2. Install limonatad binary
cd "$HOME"
if [[ "$INSTALL_METHOD" =~ ^[Ss]$ ]]; then
    # Build from source (requires Go 1.26+, CGO enabled)
    echo "Building limonatad from source (requires Go 1.26+)..."
    git clone https://github.com/Limonata-Blockchain/limonata.git limonata-src || (cd limonata-src && git pull --ff-only)
    cd limonata-src
    make install
    sudo cp "$HOME/go/bin/limonatad" /usr/local/bin/limonatad 2>/dev/null || sudo cp "$(command -v limonatad)" /usr/local/bin/limonatad
    cd "$HOME"
else
    # Prebuilt binary (official release)
    echo "Downloading prebuilt limonatad binary..."
    curl -fsSL https://github.com/Limonata-Blockchain/limonata/releases/latest/download/limonatad-linux-amd64.tar.gz | tar xz
    sudo install limonatad /usr/local/bin/
    rm -f "$HOME/limonatad"
fi
limonatad version

# 3. Set environment variables
{
    echo "export LIMONATA_MONIKER=\"$LIMONATA_MONIKER\""
    echo "export LIMONATA_CHAIN_ID=\"limonata_10777-1\""
    echo "export LIMONATA_EVM_CHAIN_ID=\"10777\""
    echo "export LIMONATA_PORT=\"$LIMONATA_PORT\""
    echo "export LIMONATA_HOME=\"$HOME/.limonatad\""
    echo "export LIMONATA_EVM_RPC=\"https://rpc.limonata.xyz\""
    echo "export LIMONATA_STAKING_GAS_PRICE=\"1000000000aLIMO\""
} >> "$HOME/.bash_profile"
# shellcheck disable=SC1091
source "$HOME/.bash_profile"
LIMONATA_HOME=${LIMONATA_HOME:-$HOME/.limonatad}

# Optional: Configure UFW based on chosen ports
if [[ "$SETUP_UFW" =~ ^[Yy]$ ]]; then
    sudo apt install -y ufw
    sudo ufw allow "${SSH_PORT}/tcp" comment "SSH Access"
    sudo ufw allow "${LIMONATA_PORT}656/tcp" comment "Limonata Testnet P2P"
    sudo ufw --force enable
    sudo ufw status verbose
fi

# 4. Initialize the node and fetch genesis
limonatad --home "$LIMONATA_HOME" init "$LIMONATA_MONIKER" --chain-id limonata_10777-1
curl -fsSL https://limonata.xyz/genesis.json -o "$LIMONATA_HOME/config/genesis.json"
limonatad --home "$LIMONATA_HOME" genesis validate-genesis

# 5. Network configuration (peers, mempool, gas prices) - verbatim from official guide
CFG="$LIMONATA_HOME/config/config.toml"
APP="$LIMONATA_HOME/config/app.toml"
sed -i 's#^persistent_peers =.*#persistent_peers = "4b154368aab24cb5b31c927efd50c73d0f4f9799@142.127.103.79:26656"#' "$CFG"
sed -i 's/^type = "flood"/type = "app"/' "$CFG"
sed -i 's/^minimum-gas-prices = .*/minimum-gas-prices = "0aLIMO"/' "$APP"

if [[ "$LIMONATA_INDEXER_ENABLED" =~ ^[Nn]$ ]]; then
    sed -i 's/^indexer = .*/indexer = "null"/' "$CFG"
else
    sed -i 's/^indexer = .*/indexer = "kv"/' "$CFG"
fi

if [[ "$LIMONATA_CUSTOM_PRUNING" =~ ^[Yy]$ ]]; then
    sed -i 's/^pruning = .*/pruning = "custom"/' "$APP"
    sed -i 's/^pruning-keep-recent = .*/pruning-keep-recent = "100"/' "$APP"
    sed -i 's/^pruning-interval = .*/pruning-interval = "19"/' "$APP"
fi

# 6. Set custom ports in config.toml and app.toml
sed -i.bak -e "s%laddr = \"tcp://0.0.0.0:26656\"%laddr = \"tcp://0.0.0.0:${LIMONATA_PORT}656\"%;
s%prometheus_listen_addr = \":26660\"%prometheus_listen_addr = \":${LIMONATA_PORT}660\"%;
s%proxy_app = \"tcp://127.0.0.1:26658\"%proxy_app = \"tcp://127.0.0.1:${LIMONATA_PORT}658\"%;
s%laddr = \"tcp://127.0.0.1:26657\"%laddr = \"tcp://127.0.0.1:${LIMONATA_PORT}657\"%" "$CFG"

sed -i.bak -e "s%address = \"tcp://localhost:1317\"%address = \"tcp://localhost:${LIMONATA_PORT}317\"%;
s%address = \"localhost:9090\"%address = \"localhost:${LIMONATA_PORT}090\"%;
s%address = \"127.0.0.1:8545\"%address = \"127.0.0.1:${LIMONATA_PORT}545\"%;
s%ws-address = \"127.0.0.1:8546\"%ws-address = \"127.0.0.1:${LIMONATA_PORT}546\"%" "$APP"

# 7. Configure optional state sync from the official CometBFT RPC.
configure_state_sync() {
    local rpc="https://cosmos-rpc.limonata.xyz" latest trust hash

    if ! latest=$(curl -fsS --max-time 15 "$rpc/block" | jq -r '.result.block.header.height // empty'); then
        return 1
    fi
    if ! [[ "$latest" =~ ^[0-9]+$ ]] || [ "$latest" -le 2000 ]; then
        return 1
    fi

    trust=$(( (latest - 2000) / 1000 * 1000 ))
    if ! hash=$(curl -fsS --max-time 15 "$rpc/commit?height=$trust" | jq -r '.result.signed_header.commit.block_id.hash // empty'); then
        return 1
    fi
    [[ "$hash" =~ ^[0-9A-Fa-f]{64}$ ]] || return 1
    grep -q '^\[statesync\]' "$CFG" || return 1

    sed -i "/^\[statesync\]/,/^\[/ { \
      s/^enable *=.*/enable = true/; \
      s#^rpc_servers *=.*#rpc_servers = \"$rpc,$rpc\"#; \
      s/^trust_height *=.*/trust_height = $trust/; \
      s/^trust_hash *=.*/trust_hash = \"$hash\"/; \
      s/^trust_period *=.*/trust_period = \"168h0m0s\"/ }" "$CFG"

    echo "State sync configured: trusted height $trust via $rpc"
}

if [ "$LIMONATA_STATE_SYNC" = "y" ]; then
    if ! configure_state_sync; then
        echo "WARNING: State sync configuration failed because the official CometBFT RPC did not return valid trust data."
        CONTINUE_GENESIS=$(prompt_short_yes_no "Continue with normal genesis sync instead? (y/n, default n): " n)
        if [ "$CONTINUE_GENESIS" != "y" ]; then
            echo "Installation stopped before the service was created. Re-run when the state-sync RPC is available, or choose normal genesis sync."
            exit 1
        fi
    fi
fi

# 8. Create the systemd service file.
sudo tee "/etc/systemd/system/${LIMONATA_SERVICE_NAME}.service" > /dev/null <<EOF
[Unit]
Description=Limonata Testnet Node (${LIMONATA_SERVICE_NAME})
After=network-online.target

[Service]
User=$USER
WorkingDirectory=$LIMONATA_HOME
ExecStart=/usr/local/bin/limonatad start --home $LIMONATA_HOME --chain-id limonata_10777-1 --evm.evm-chain-id 10777 --minimum-gas-prices 0aLIMO
StandardOutput=journal
StandardError=journal
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
LimitNPROC=65536

[Install]
WantedBy=multi-user.target
EOF

# Save the service name for valleyofLimonata.sh.
echo "export LIMONATA_SERVICE_NAME=\"${LIMONATA_SERVICE_NAME}\"" >> "$HOME/.bash_profile"

# 9. Start the node.
sudo systemctl daemon-reload
sudo systemctl enable "$LIMONATA_SERVICE_NAME"
sudo systemctl restart "$LIMONATA_SERVICE_NAME"

# 10. Confirm installation status.
if systemctl is-active --quiet "$LIMONATA_SERVICE_NAME"; then
    echo "Node installation and service started successfully!"
    echo "Monitor sync status with: curl -s http://127.0.0.1:${LIMONATA_PORT}657/status | jq '.result.sync_info'"
else
    echo "Node installation failed. Please check the logs for more information."
    echo "sudo journalctl -u ${LIMONATA_SERVICE_NAME} -fn 100"
    exit 1
fi

# show the full logs
echo "sudo journalctl -u ${LIMONATA_SERVICE_NAME} -fn 100"
echo "Let's Buidl Limonata Together"
