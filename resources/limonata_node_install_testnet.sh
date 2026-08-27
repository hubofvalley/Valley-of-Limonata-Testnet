#!/bin/bash

set -euo pipefail

if [ -z "${HOME:-}" ] || [ "$HOME" = "/" ]; then
    echo "Refusing installation because HOME is empty or unsafe: ${HOME:-<unset>}"
    exit 1
fi

readonly LIMONATA_RELEASE="limonata-v0.3.6"
readonly LIMONATA_RELEASE_COMMIT="effa377d673fc6f0fb307a78ca54e037e53060f7"
readonly LIMONATA_ARTIFACT="limonatad-linux-amd64.tar.gz"
readonly LIMONATA_ARTIFACT_SHA256="39ff376963498de120604c273d50751afc005ebeec9cbcca88c0f732eff56125"
readonly LIMONATA_SIGNING_KEY_FINGERPRINT="A45380198F390AF69126AE12E4ECEC477C1735FB"
readonly LIMONATA_REPO="https://github.com/Limonata-Blockchain/limonata.git"
readonly LIMONATA_RELEASE_BASE="https://github.com/Limonata-Blockchain/limonata/releases/download/${LIMONATA_RELEASE}"
readonly COSMOVISOR_VERSION="v1.7.1"
readonly GO_VERSION="1.26.5"
readonly GO_LINUX_AMD64_SHA256="5c2c3b16caefa1d968a94c1daca04a7ca301a496d9b086e17ad77bb81393f053"
readonly GO_ROOT="$HOME/.local/go-${GO_VERSION}"
readonly COSMOVISOR_BIN="/usr/local/bin/cosmovisor"
readonly LIMONATA_BIN_DIR="$HOME/go/bin"
readonly LIMONATA_BIN="$LIMONATA_BIN_DIR/limonatad"

export PATH="$LIMONATA_BIN_DIR:$PATH"

# v0.3.6 contains the historical Limonata upgrade handlers and is explicitly
# designed to replay pre-v0.3.6 history byte-for-byte. Pre-stage the same pinned
# binary in these historical Cosmovisor slots so a fresh genesis sync can traverse
# old on-chain upgrade boundaries without downloading or executing mutable binaries.
readonly HISTORICAL_UPGRADES=(
    "valgrant-v1"
    "encmempool-threshold-vpcap-v1"
    "gassponsor-security-caps-v1"
    "encmempool-transparent-dkg-v1"
    "encmempool-dkg-dealing-retention-v1"
    "encmempool-strict-concentration-v1"
)

# ==== CONFIG ====
echo -e "\n--- Limonata Testnet Node Setup ---"

LOGO="
 __
/__ ._ _. ._   _|   \\  / _. | |  _
\_| | (_| | | (_|    \\/ (_| | | (/_ \\/
                                    /
"

echo "$LOGO"
echo "Pinned release: ${LIMONATA_RELEASE} (${LIMONATA_RELEASE_COMMIT})"
echo "Fresh installs use this replay-compatible release from block 1 under Cosmovisor."
echo "User-facing binary path: ${LIMONATA_BIN}"

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
    read -r -p "Install method - verified prebuilt binary or build pinned source? (p/s, default p): " INSTALL_METHOD
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

sudo systemctl daemon-reload
sudo systemctl stop "$LIMONATA_SERVICE_NAME" 2>/dev/null || true
sudo systemctl disable "$LIMONATA_SERVICE_NAME" 2>/dev/null || true
sudo rm -f "/etc/systemd/system/${LIMONATA_SERVICE_NAME}.service" 2>/dev/null || true
sudo rm -f /usr/local/bin/limonatad 2>/dev/null || true
rm -f "$LIMONATA_BIN" 2>/dev/null || true
sudo rm -rf "$HOME/.limonatad" 2>/dev/null || true
sed -i "/LIMONATA_/d" "$HOME/.bash_profile" 2>/dev/null || true

sudo apt update -y
sudo apt install -y curl git jq bc build-essential gcc unzip wget lz4 openssl gnupg ca-certificates
mkdir -p "$LIMONATA_BIN_DIR"
if ! grep -Fqx 'export PATH="$HOME/go/bin:$PATH"' "$HOME/.bash_profile" 2>/dev/null; then
    echo 'export PATH="$HOME/go/bin:$PATH"' >> "$HOME/.bash_profile"
fi

WORKDIR=$(mktemp -d)
cleanup() {
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

install_go_toolchain() {
    local archive="$WORKDIR/go${GO_VERSION}.linux-amd64.tar.gz"

    if [ -x "$GO_ROOT/bin/go" ] && "$GO_ROOT/bin/go" version | grep -q "go${GO_VERSION}"; then
        echo "Pinned Go toolchain already installed: $GO_ROOT"
        return
    fi

    echo "Installing pinned Go ${GO_VERSION} toolchain..."
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -o "$archive"
    echo "${GO_LINUX_AMD64_SHA256}  ${archive}" | sha256sum -c -
    rm -rf "$GO_ROOT"
    mkdir -p "$GO_ROOT"
    tar -xzf "$archive" -C "$GO_ROOT" --strip-components=1
    "$GO_ROOT/bin/go" version
}

install_cosmovisor() {
    echo "Installing pinned Cosmovisor ${COSMOVISOR_VERSION} from the verified Go module..."
    mkdir -p "$HOME/.local/bin"
    GOBIN="$HOME/.local/bin" "$GO_ROOT/bin/go" install "cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@${COSMOVISOR_VERSION}"
    sudo install -m 0755 "$HOME/.local/bin/cosmovisor" "$COSMOVISOR_BIN"
    "$COSMOVISOR_BIN" --help >/dev/null
}

install_go_toolchain
install_cosmovisor

STAGED_BINARY="$WORKDIR/limonatad"

install_verified_prebuilt() {
    local release_dir="$WORKDIR/release"
    local gnupg_home="$release_dir/gnupg"
    local key_fingerprint actual_sha

    mkdir -p "$release_dir" "$gnupg_home"
    chmod 700 "$gnupg_home"

    echo "Downloading pinned official Limonata ${LIMONATA_RELEASE} release..."
    curl -fsSL "${LIMONATA_RELEASE_BASE}/${LIMONATA_ARTIFACT}" -o "$release_dir/${LIMONATA_ARTIFACT}"
    curl -fsSL "${LIMONATA_RELEASE_BASE}/SHA256SUMS.txt" -o "$release_dir/SHA256SUMS.txt"
    curl -fsSL "${LIMONATA_RELEASE_BASE}/SHA256SUMS.txt.asc" -o "$release_dir/SHA256SUMS.txt.asc"
    curl -fsSL "${LIMONATA_RELEASE_BASE}/limonata-release-signing-key.asc" -o "$release_dir/limonata-release-signing-key.asc"

    key_fingerprint=$(gpg --batch --homedir "$gnupg_home" --with-colons --import-options show-only --import \
        "$release_dir/limonata-release-signing-key.asc" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')
    if [ "$key_fingerprint" != "$LIMONATA_SIGNING_KEY_FINGERPRINT" ]; then
        echo "Release signing key fingerprint mismatch. Refusing installation."
        echo "Expected: $LIMONATA_SIGNING_KEY_FINGERPRINT"
        echo "Observed: ${key_fingerprint:-<none>}"
        exit 1
    fi

    gpg --batch --homedir "$gnupg_home" --import "$release_dir/limonata-release-signing-key.asc" >/dev/null 2>&1
    gpg --batch --homedir "$gnupg_home" --verify "$release_dir/SHA256SUMS.txt.asc" "$release_dir/SHA256SUMS.txt"

    actual_sha=$(sha256sum "$release_dir/${LIMONATA_ARTIFACT}" | awk '{print $1}')
    if [ "$actual_sha" != "$LIMONATA_ARTIFACT_SHA256" ]; then
        echo "Pinned artifact SHA256 mismatch. Refusing installation."
        echo "Expected: $LIMONATA_ARTIFACT_SHA256"
        echo "Observed: $actual_sha"
        exit 1
    fi

    (
        cd "$release_dir"
        grep "  ${LIMONATA_ARTIFACT}$" SHA256SUMS.txt | sha256sum -c -
        tar -xzf "$LIMONATA_ARTIFACT"
    )

    if [ ! -x "$release_dir/limonatad" ]; then
        echo "Verified archive does not contain an executable limonatad binary."
        exit 1
    fi
    install -m 0755 "$release_dir/limonatad" "$STAGED_BINARY"
}

build_pinned_source() {
    local source_dir="$WORKDIR/limonata-src"
    local actual_commit

    echo "Building Limonata ${LIMONATA_RELEASE} from pinned source commit..."
    git clone --depth 1 --branch "$LIMONATA_RELEASE" "$LIMONATA_REPO" "$source_dir"
    actual_commit=$(git -C "$source_dir" rev-parse HEAD)
    if [ "$actual_commit" != "$LIMONATA_RELEASE_COMMIT" ]; then
        echo "Source tag resolved to an unexpected commit. Refusing build."
        echo "Expected: $LIMONATA_RELEASE_COMMIT"
        echo "Observed: $actual_commit"
        exit 1
    fi

    PATH="$GO_ROOT/bin:$PATH" CGO_ENABLED=1 make -C "$source_dir" install
    if [ ! -x "$LIMONATA_BIN" ]; then
        echo "Source build did not produce $LIMONATA_BIN"
        exit 1
    fi
    install -m 0755 "$LIMONATA_BIN" "$STAGED_BINARY"
}

if [[ "$INSTALL_METHOD" =~ ^[Ss]$ ]]; then
    build_pinned_source
else
    install_verified_prebuilt
fi

VERSION_OUTPUT=$("$STAGED_BINARY" version --long 2>/dev/null || "$STAGED_BINARY" version 2>/dev/null || true)
echo "$VERSION_OUTPUT"
if ! grep -Eq '(^|[^0-9])v?0\.3\.6([^0-9]|$)' <<<"$VERSION_OUTPUT"; then
    echo "Staged binary does not report v0.3.6. Refusing installation."
    exit 1
fi

# Put the operator-facing binary in ~/go/bin, matching the Valley of Story UX.
# After Cosmovisor initialization this path becomes a symlink to current/bin.
install -m 0755 "$STAGED_BINARY" "$LIMONATA_BIN"

{
    echo "export LIMONATA_MONIKER=\"$LIMONATA_MONIKER\""
    echo "export LIMONATA_CHAIN_ID=\"limonata_10777-1\""
    echo "export LIMONATA_EVM_CHAIN_ID=\"10777\""
    echo "export LIMONATA_PORT=\"$LIMONATA_PORT\""
    echo "export LIMONATA_HOME=\"$HOME/.limonatad\""
    echo "export LIMONATA_EVM_RPC=\"https://rpc.limonata.xyz\""
    echo "export LIMONATA_STAKING_GAS_PRICE=\"1000000000aLIMO\""
    echo "export LIMONATA_TARGET_VERSION=\"${LIMONATA_RELEASE}\""
} >> "$HOME/.bash_profile"
# shellcheck disable=SC1091
source "$HOME/.bash_profile"
LIMONATA_HOME=${LIMONATA_HOME:-$HOME/.limonatad}

if [[ "$SETUP_UFW" =~ ^[Yy]$ ]]; then
    sudo apt install -y ufw
    sudo ufw allow "${SSH_PORT}/tcp" comment "SSH Access"
    sudo ufw allow "${LIMONATA_PORT}656/tcp" comment "Limonata Testnet P2P"
    sudo ufw --force enable
    sudo ufw status verbose
fi

# Initialize using the pinned v0.3.6 binary, then fetch and validate live genesis.
"$LIMONATA_BIN" --home "$LIMONATA_HOME" init "$LIMONATA_MONIKER" --chain-id limonata_10777-1
curl -fsSL https://limonata.xyz/genesis.json -o "$LIMONATA_HOME/config/genesis.json"
"$LIMONATA_BIN" --home "$LIMONATA_HOME" genesis validate-genesis

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

sed -i.bak -e "s%laddr = \"tcp://0.0.0.0:26656\"%laddr = \"tcp://0.0.0.0:${LIMONATA_PORT}656\"%;
s%prometheus_listen_addr = \":26660\"%prometheus_listen_addr = \":${LIMONATA_PORT}660\"%;
s%proxy_app = \"tcp://127.0.0.1:26658\"%proxy_app = \"tcp://127.0.0.1:${LIMONATA_PORT}658\"%;
s%laddr = \"tcp://127.0.0.1:26657\"%laddr = \"tcp://127.0.0.1:${LIMONATA_PORT}657\"%" "$CFG"

sed -i.bak -e "s%address = \"tcp://localhost:1317\"%address = \"tcp://localhost:${LIMONATA_PORT}317\"%;
s%address = \"localhost:9090\"%address = \"localhost:${LIMONATA_PORT}090\"%;
s%address = \"127.0.0.1:8545\"%address = \"127.0.0.1:${LIMONATA_PORT}545\"%;
s%ws-address = \"127.0.0.1:8546\"%ws-address = \"127.0.0.1:${LIMONATA_PORT}546\"%" "$APP"

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

# Initialize Cosmovisor with v0.3.6 as the genesis binary. The same replay-safe
# binary is pre-staged under known historical upgrade names so Cosmovisor does not
# need auto-download while a fresh node traverses old upgrade heights.
export DAEMON_NAME=limonatad
export DAEMON_HOME="$LIMONATA_HOME"
export DAEMON_DATA_BACKUP_DIR="$LIMONATA_HOME/cosmovisor/backup"
mkdir -p "$DAEMON_DATA_BACKUP_DIR"
"$COSMOVISOR_BIN" init "$LIMONATA_BIN"
mkdir -p "$LIMONATA_HOME/cosmovisor/upgrades"

for upgrade_name in "${HISTORICAL_UPGRADES[@]}"; do
    upgrade_bin_dir="$LIMONATA_HOME/cosmovisor/upgrades/${upgrade_name}/bin"
    mkdir -p "$upgrade_bin_dir"
    install -m 0755 "$LIMONATA_HOME/cosmovisor/genesis/bin/limonatad" "$upgrade_bin_dir/limonatad"
done

rm -f "$LIMONATA_BIN"
ln -s "$LIMONATA_HOME/cosmovisor/current/bin/limonatad" "$LIMONATA_BIN"

if [ ! -x "$(readlink -f "$LIMONATA_BIN")" ]; then
    echo "Cosmovisor current binary symlink is invalid. Refusing to create the service."
    exit 1
fi

sudo tee "/etc/systemd/system/${LIMONATA_SERVICE_NAME}.service" > /dev/null <<EOF
[Unit]
Description=Cosmovisor Limonata Testnet Node (${LIMONATA_SERVICE_NAME})
After=network-online.target
Wants=network-online.target

[Service]
User=$USER
Type=simple
WorkingDirectory=$LIMONATA_HOME
ExecStart=$COSMOVISOR_BIN run start --home $LIMONATA_HOME --chain-id limonata_10777-1 --evm.evm-chain-id 10777 --minimum-gas-prices 0aLIMO
StandardOutput=journal
StandardError=journal
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
LimitNPROC=65536
Environment="DAEMON_NAME=limonatad"
Environment="DAEMON_HOME=$LIMONATA_HOME"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"
Environment="DAEMON_DOWNLOAD_MUST_HAVE_CHECKSUM=true"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="DAEMON_DATA_BACKUP_DIR=$LIMONATA_HOME/cosmovisor/backup"
Environment="UNSAFE_SKIP_BACKUP=true"

[Install]
WantedBy=multi-user.target
EOF

echo "export LIMONATA_SERVICE_NAME=\"${LIMONATA_SERVICE_NAME}\"" >> "$HOME/.bash_profile"

sudo systemctl daemon-reload
sudo systemctl enable "$LIMONATA_SERVICE_NAME"
sudo systemctl restart "$LIMONATA_SERVICE_NAME"

if systemctl is-active --quiet "$LIMONATA_SERVICE_NAME"; then
    echo "Node installation and Cosmovisor service started successfully!"
    echo "CLI binary: $LIMONATA_BIN"
    echo "Current binary: $(readlink -f "$LIMONATA_BIN")"
    "$LIMONATA_BIN" --home "$LIMONATA_HOME" version || true
    echo "Monitor sync status with: curl -s http://127.0.0.1:${LIMONATA_PORT}657/status | jq '.result.sync_info'"
else
    echo "Node installation failed. Please check the logs for more information."
    echo "sudo journalctl -u ${LIMONATA_SERVICE_NAME} -fn 100"
    exit 1
fi

echo "sudo journalctl -u ${LIMONATA_SERVICE_NAME} -fn 100"
echo "Let's Buidl Limonata Together"
