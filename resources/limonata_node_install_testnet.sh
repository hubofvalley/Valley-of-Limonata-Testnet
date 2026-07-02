#!/bin/bash

set -e

# ==== CONFIG ====
echo -e "\n--- Limonata Testnet Node Setup ---"

LOGO="
 __
/__ ._ _. ._   _|   \  / _. | |  _
\_| | (_| | | (_|    \/ (_| | | (/_ \/
                                    /
"

echo "$LOGO"

# Prompt for LIMONATA_MONIKER, LIMONATA_PORT, install method
read -p "Enter your LIMONATA_MONIKER: " LIMONATA_MONIKER
read -p "Enter your preferred port number prefix (leave empty to use default: 26): " LIMONATA_PORT
if [ -z "$LIMONATA_PORT" ]; then
    LIMONATA_PORT=26
fi
read -p "Install method - prebuilt binary or build from source? (p/s, default p): " INSTALL_METHOD
INSTALL_METHOD=${INSTALL_METHOD:-p}
read -p "Configure UFW firewall rules for Limonata? (y/n): " SETUP_UFW

# Service Name Configuration (for multi-instance support)
if [ -z "${LIMONATA_SERVICE_NAME:-}" ]; then
    read -p "Enter Service Name (default 'limonatad'): " LIMONATA_SERVICE_NAME
    LIMONATA_SERVICE_NAME=${LIMONATA_SERVICE_NAME:-limonatad}
fi

echo "Using Service Name: ${LIMONATA_SERVICE_NAME}"

# Stop and remove existing Limonata node (idempotent re-deploy)
sudo systemctl daemon-reload
sudo systemctl stop ${LIMONATA_SERVICE_NAME} 2>/dev/null || true
sudo systemctl disable ${LIMONATA_SERVICE_NAME} 2>/dev/null || true
sudo rm -rf /etc/systemd/system/${LIMONATA_SERVICE_NAME}.service 2>/dev/null || true
sudo rm -f /usr/local/bin/limonatad 2>/dev/null || true
sudo rm -rf $HOME/.limonatad 2>/dev/null || true
sed -i "/LIMONATA_/d" $HOME/.bash_profile 2>/dev/null || true

# 1. Install dependencies
sudo apt update -y
sudo apt install -y curl git jq build-essential gcc unzip wget lz4 openssl

# 2. Install limonatad binary
cd $HOME
if [[ "$INSTALL_METHOD" =~ ^[Ss]$ ]]; then
    # Build from source (requires Go 1.26+, CGO enabled)
    echo "Building limonatad from source (requires Go 1.26+)..."
    git clone https://github.com/Limonata-Blockchain/limonata.git limonata-src || (cd limonata-src && git pull)
    cd limonata-src
    make install
    sudo cp $HOME/go/bin/limonatad /usr/local/bin/limonatad 2>/dev/null || sudo cp $(which limonatad) /usr/local/bin/limonatad
    cd $HOME
else
    # Prebuilt binary (official release)
    echo "Downloading prebuilt limonatad binary..."
    curl -sL https://github.com/Limonata-Blockchain/limonata/releases/latest/download/limonatad-linux-amd64.tar.gz | tar xz
    sudo install limonatad /usr/local/bin/
    rm -f $HOME/limonatad
fi
limonatad version

# 3. Set environment variables
echo "export LIMONATA_MONIKER=\"$LIMONATA_MONIKER\"" >> $HOME/.bash_profile
echo "export LIMONATA_CHAIN_ID=\"limonata_10777-1\"" >> $HOME/.bash_profile
echo "export LIMONATA_EVM_CHAIN_ID=\"10777\"" >> $HOME/.bash_profile
echo "export LIMONATA_PORT=\"$LIMONATA_PORT\"" >> $HOME/.bash_profile
source $HOME/.bash_profile

# Optional: Configure UFW based on chosen ports
if [[ "$SETUP_UFW" =~ ^[Yy]$ ]]; then
    sudo apt install -y ufw
    sudo ufw allow 22/tcp comment "SSH Access"
    sudo ufw allow ${LIMONATA_PORT}656/tcp comment "Limonata Testnet P2P"
    sudo ufw --force enable
    sudo ufw status verbose
fi

# 4. Initialize the node and fetch genesis
limonatad init "$LIMONATA_MONIKER" --chain-id limonata_10777-1
curl -s https://limonata.xyz/genesis.json -o $HOME/.limonatad/config/genesis.json
limonatad genesis validate-genesis

# 5. Network configuration (peers, mempool, gas prices) - verbatim from official guide
CFG=$HOME/.limonatad/config/config.toml
APP=$HOME/.limonatad/config/app.toml
sed -i 's#^persistent_peers =.*#persistent_peers = "4b154368aab24cb5b31c927efd50c73d0f4f9799@142.127.103.79:26656"#' "$CFG"
sed -i 's/^type = "flood"/type = "app"/' "$CFG"
sed -i 's/^minimum-gas-prices = .*/minimum-gas-prices = "0aLIMO"/' "$APP"

# 6. Set custom ports in config.toml and app.toml
sed -i.bak -e "s%laddr = \"tcp://0.0.0.0:26656\"%laddr = \"tcp://0.0.0.0:${LIMONATA_PORT}656\"%;
s%prometheus_listen_addr = \":26660\"%prometheus_listen_addr = \":${LIMONATA_PORT}660\"%;
s%proxy_app = \"tcp://127.0.0.1:26658\"%proxy_app = \"tcp://127.0.0.1:${LIMONATA_PORT}658\"%;
s%laddr = \"tcp://127.0.0.1:26657\"%laddr = \"tcp://127.0.0.1:${LIMONATA_PORT}657\"%" "$CFG"

sed -i.bak -e "s%address = \"tcp://localhost:1317\"%address = \"tcp://localhost:${LIMONATA_PORT}317\"%;
s%address = \"localhost:9090\"%address = \"localhost:${LIMONATA_PORT}090\"%;
s%address = \"127.0.0.1:8545\"%address = \"127.0.0.1:${LIMONATA_PORT}545\"%;
s%ws-address = \"127.0.0.1:8546\"%ws-address = \"127.0.0.1:${LIMONATA_PORT}546\"%" "$APP"

# 7. Create systemd service file
sudo tee /etc/systemd/system/${LIMONATA_SERVICE_NAME}.service > /dev/null <<EOF
[Unit]
Description=Limonata Testnet Node (${LIMONATA_SERVICE_NAME})
After=network-online.target

[Service]
User=$USER
WorkingDirectory=$HOME/.limonatad
ExecStart=$(which limonatad) start --chain-id limonata_10777-1 --evm.evm-chain-id 10777 --minimum-gas-prices 0aLIMO
StandardOutput=journal
StandardError=journal
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
LimitNPROC=65536

[Install]
WantedBy=multi-user.target
EOF

# Save service name to bash_profile for valleyofLimonata.sh
echo "export LIMONATA_SERVICE_NAME=\"${LIMONATA_SERVICE_NAME}\"" >> $HOME/.bash_profile

# 8. Start the node
sudo systemctl daemon-reload
sudo systemctl enable ${LIMONATA_SERVICE_NAME}
sudo systemctl restart ${LIMONATA_SERVICE_NAME}

# 9. Confirmation message for installation completion
if systemctl is-active --quiet ${LIMONATA_SERVICE_NAME}; then
    echo "Node installation and service started successfully!"
    echo "Monitor sync status with: limonatad status 2>&1 | grep -o '\"catching_up\":[a-z]*'"
else
    echo "Node installation failed. Please check the logs for more information."
fi

# show the full logs
echo "sudo journalctl -u ${LIMONATA_SERVICE_NAME} -fn 100"
echo "Let's Buidl Limonata Together"
