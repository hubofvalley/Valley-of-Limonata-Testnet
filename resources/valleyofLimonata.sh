#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
ORANGE='\033[38;5;214m'
RESET='\033[0m'

# Load saved Valley settings without prompting before the privacy notice.
# shellcheck disable=SC1091
source "$HOME/.bash_profile" 2>/dev/null
# Keep the operator-facing Limonata binary consistent with Valley of Story.
# This works before and after a fresh install because PATH may contain a directory
# that does not exist yet; the installer creates it when needed.
export PATH="$HOME/go/bin:$PATH"

LIMONATA_HOME=${LIMONATA_HOME:-$HOME/.limonatad}
LIMONATA_EVM_RPC=${LIMONATA_EVM_RPC:-https://rpc.limonata.xyz}
LIMONATA_CHAIN_ID=${LIMONATA_CHAIN_ID:-limonata_10777-1}
LIMONATA_EVM_CHAIN_ID=${LIMONATA_EVM_CHAIN_ID:-10777}
LIMONATA_STAKING_GAS_PRICE=${LIMONATA_STAKING_GAS_PRICE:-1000000000aLIMO}
LIMONATA_TARGET_VERSION=${LIMONATA_TARGET_VERSION:-limonata-v0.3.6}

LOGO="
 __      __     _  _                        __   _      _                             _
 \ \    / /    | || |                      / _| | |    (_)_ __  ___  _ _  __ _| |_ __ _
  \ \  / /__ _ | || |  ___  _   _    ___  | |_  | |__  | | '  \/ _ \| ' \/ _\` |  _/ _\` |
  _\ \/ // __ || || | / _ \| | | |  / _ \ |  _| |____| |_|_|_|_\___/|_||_\__,_|\__\__,_|
 | |\  /| (_| || || ||  __/| |_| | | (_) || |
 | |_\/  \__,_||_||_| \___| \__, |  \___/ |_|
 | '_ \ | | | |              __/ |
 | |_) || |_| |             |___/
 |____/  \__, |
          __/ |
         |___/
 __
/__ __ __ __   _|   \  / __ | |  _
\_| | (_| | | (_|    \/ (_| | | (/_ \/
                                    /
"

PRIVACY_SAFETY_STATEMENT="
${YELLOW}Privacy and Safety Statement${RESET}

${GREEN}No User Data Stored Externally${RESET}
- This script does not store any user data externally. All operations are performed locally on your machine.

${GREEN}No Phishing Links${RESET}
- This script does not contain any phishing links. All URLs and commands are provided for legitimate purposes related to Limonata node operations.

${GREEN}Security Best Practices${RESET}
- Always verify the integrity of the script and its source.
- Ensure you are running the script in a secure environment.
- Be cautious when entering sensitive information such as keys.

${GREEN}Disclaimer${RESET}
- The authors of this script are not responsible for any misuse or damage caused by the use of this script.
- Use this script at your own risk.

${GREEN}Contact${RESET}
- If you have any concerns or questions, please contact us at letsbuidltogether@grandvalleys.com.
"

ENDPOINTS="${GREEN}
Limonata useful links:${RESET}
- Official Website: ${BLUE}https://limonata.xyz${RESET}
- Validator Guide: ${BLUE}https://limonata.xyz/VALIDATOR.md${RESET}
- Faucet (test LIMO): ${BLUE}https://faucet.limonata.xyz${RESET}
- Validator Application: ${BLUE}https://limonata.xyz/#validator${RESET}
- Validator Scoring: ${BLUE}https://grounds.limonata.xyz${RESET}
- GitHub: ${BLUE}https://github.com/Limonata-Blockchain/limonata${RESET}

${GREEN}Network facts:${RESET}
- Chain ID: ${CYAN}limonata_10777-1${RESET} | EVM Chain ID: ${CYAN}10777${RESET} (hex: 0x2a19)
- Seed/peer: ${CYAN}4b154368aab24cb5b31c927efd50c73d0f4f9799@142.127.103.79:26656${RESET}
- Genesis: ${BLUE}https://limonata.xyz/genesis.json${RESET}
- State-sync RPC: ${BLUE}https://cosmos-rpc.limonata.xyz${RESET}
- No staking inflation (x/mint disabled) - validators earn tx fees + commission
- Staking gas price: ${CYAN}${LIMONATA_STAKING_GAS_PRICE}${RESET}

${GREEN}Connect with Grand Valley:${RESET}
- X: ${BLUE}https://x.com/bacvalley${RESET}
- GitHub: ${BLUE}https://github.com/hubofvalley${RESET}
- Email: ${BLUE}letsbuidltogether@grandvalleys.com${RESET}
"
# TODO-GV-ENDPOINT: Add a *-grandvalleys.com Limonata endpoint after Grand Valley infrastructure is live.

function ensure_service_name() {
    local input_service
    while [ -z "${LIMONATA_SERVICE_NAME:-}" ]; do
        echo -e "${YELLOW}Service name configuration not found.${RESET}"
        read -r -p "Enter service name (default 'limonatad'): " input_service
        input_service=${input_service:-limonatad}
        if [[ "$input_service" =~ ^[A-Za-z0-9_.@-]+$ ]]; then
            LIMONATA_SERVICE_NAME=$input_service
        else
            echo -e "${RED}Invalid service name. Use letters, numbers, dots, underscores, @, or hyphens only.${RESET}"
        fi
    done
    if ! grep -q '^export LIMONATA_SERVICE_NAME=' "$HOME/.bash_profile" 2>/dev/null; then
        echo "export LIMONATA_SERVICE_NAME=\"$LIMONATA_SERVICE_NAME\"" >> "$HOME/.bash_profile"
    fi
    export LIMONATA_SERVICE_NAME
}

function show_intro() {
    local binary_version
    if command -v limonatad >/dev/null 2>&1; then
        binary_version=$(limonatad version 2>/dev/null | head -n 1)
        [ -z "$binary_version" ] && binary_version="installed; version unavailable"
    else
        binary_version="not installed; target $LIMONATA_TARGET_VERSION"
    fi

    echo -e "
Valley of Limonata by ${ORANGE}Grand Valley${RESET}

${GREEN}Limonata Node System Requirements${RESET}
${YELLOW}| Category  | Requirements     |
| --------- | ---------------- |
| CPU       | 2+ vCPU          |
| RAM       | 4+ GB            |
| Storage   | 50+ GB SSD       |
| Bandwidth | 100+ MBit/s      |${RESET}

- service file name: ${CYAN}${LIMONATA_SERVICE_NAME}.service${RESET}
- current chain: ${CYAN}Limonata Testnet${RESET}
- current chain ID: ${CYAN}${LIMONATA_CHAIN_ID}${RESET} (EVM chain ID: ${CYAN}${LIMONATA_EVM_CHAIN_ID}${RESET})
- native denom: ${CYAN}aLIMO${RESET} (1 LIMO = 10^18 aLIMO)
- binary: ${CYAN}$HOME/go/bin/limonatad${RESET} (${CYAN}${binary_version}${RESET})"
}

# Display LOGO and wait for user input to continue
echo -e "$LOGO"
echo -e "$PRIVACY_SAFETY_STATEMENT"
echo -e "\n${YELLOW}Press Enter to continue...${RESET}"
read -r

# Ask once only after the privacy statement, then display the intro.
ensure_service_name
show_intro
echo -e "$ENDPOINTS"
echo -e "\n${YELLOW}Press Enter to continue...${RESET}"
read -r

grep -q '^export LIMONATA_CHAIN_ID=' "$HOME/.bash_profile" 2>/dev/null || echo "export LIMONATA_CHAIN_ID=\"limonata_10777-1\"" >> "$HOME/.bash_profile"
grep -q '^export LIMONATA_EVM_CHAIN_ID=' "$HOME/.bash_profile" 2>/dev/null || echo "export LIMONATA_EVM_CHAIN_ID=\"10777\"" >> "$HOME/.bash_profile"
grep -q '^export LIMONATA_HOME=' "$HOME/.bash_profile" 2>/dev/null || echo "export LIMONATA_HOME=\"$HOME/.limonatad\"" >> "$HOME/.bash_profile"
grep -q '^export LIMONATA_EVM_RPC=' "$HOME/.bash_profile" 2>/dev/null || echo "export LIMONATA_EVM_RPC=\"https://rpc.limonata.xyz\"" >> "$HOME/.bash_profile"
grep -q '^export LIMONATA_STAKING_GAS_PRICE=' "$HOME/.bash_profile" 2>/dev/null || echo "export LIMONATA_STAKING_GAS_PRICE=\"1000000000aLIMO\"" >> "$HOME/.bash_profile"
# shellcheck disable=SC1091
source "$HOME/.bash_profile"
LIMONATA_HOME=${LIMONATA_HOME:-$HOME/.limonatad}
LIMONATA_EVM_RPC=${LIMONATA_EVM_RPC:-https://rpc.limonata.xyz}

# Strip trailing carriage returns (CRLF) from all config variables
LIMONATA_HOME=$(echo "$LIMONATA_HOME" | tr -d '\r')
LIMONATA_EVM_RPC=$(echo "$LIMONATA_EVM_RPC" | tr -d '\r')
LIMONATA_CHAIN_ID=$(echo "$LIMONATA_CHAIN_ID" | tr -d '\r')
LIMONATA_EVM_CHAIN_ID=$(echo "$LIMONATA_EVM_CHAIN_ID" | tr -d '\r')
LIMONATA_STAKING_GAS_PRICE=$(echo "$LIMONATA_STAKING_GAS_PRICE" | tr -d '\r')
LIMONATA_SERVICE_NAME=$(echo "$LIMONATA_SERVICE_NAME" | tr -d '\r')
LIMONATA_MONIKER=$(echo "$LIMONATA_MONIKER" | tr -d '\r')

function limonata_cmd() {
    local port
    port=$(get_local_rpc_port)
    if [[ "$1" == "tx" || "$1" == "query" ]] && [ -n "$port" ]; then
        limonatad --home "$LIMONATA_HOME" --node "tcp://localhost:$port" "$@"
    else
        limonatad --home "$LIMONATA_HOME" "$@"
    fi
}

function hex_to_dec() {
    local value=${1:-}
    if [[ "$value" =~ ^0x[0-9a-fA-F]+$ ]]; then
        printf "%d" "$value"
    fi
}

function get_network_height() {
    local result
    result=$(curl -m 5 -s -X POST "$LIMONATA_EVM_RPC" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result // empty' 2>/dev/null)
    hex_to_dec "$result"
}

function get_local_rpc_port() {
    local cfg="$LIMONATA_HOME/config/config.toml"
    if [ ! -f "$cfg" ]; then
        return
    fi
    awk '/^\[rpc\]/ {in_rpc=1} /^\[/ && !/^\[rpc\]/ {in_rpc=0} in_rpc && /laddr = "tcp:\/\// {split($0, a, ":"); gsub(/".*/, "", a[3]); print a[3]; exit}' "$cfg"
}

function get_local_status_json() {
    local port
    port=$(get_local_rpc_port)
    if [ -z "$port" ]; then
        return
    fi
    curl -m 5 -s "http://127.0.0.1:${port}/status"
}

function get_local_height() {
    get_local_status_json | jq -r '.result.sync_info.latest_block_height // empty' 2>/dev/null
}

function get_local_catching_up() {
    local val
    val=$(get_local_status_json | jq -r '.result.sync_info.catching_up' 2>/dev/null)
    echo "${val:-true}"
}

function prompt_back_or_continue() {
    read -r -p "Press Enter to continue or type 'back' to go back to the menu: " user_choice
    if [[ ${user_choice,,} == "back" ]]; then
        menu
        return 1
    fi
    return 0
}

function is_positive_decimal() {
    local value=${1:-}
    [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
    awk -v value="$value" 'BEGIN { exit !(value > 0) }'
}

function is_rate() {
    local value=${1:-}
    [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
    awk -v value="$value" 'BEGIN { exit !(value >= 0 && value <= 1) }'
}

function require_standard_limonata_home() {
    local expected_home="$HOME/.limonatad"
    if [ "$LIMONATA_HOME" != "$expected_home" ]; then
        echo -e "${RED}Refusing destructive action: LIMONATA_HOME must be exactly $expected_home, but it is $LIMONATA_HOME.${RESET}"
        return 1
    fi
}

function deploy_limonata_node() {
    if ! require_standard_limonata_home; then
        menu
        return
    fi
    clear
    echo -e "${RED}▓▒░ IMPORTANT DISCLAIMER AND TERMS ░▒▓${RESET}"
    echo -e "${YELLOW}1. SECURITY:${RESET}"
    echo -e "- This script ${GREEN}DOES NOT${RESET} send any data outside your server"
    echo "- All operations are performed locally"
    echo "- You are encouraged to audit the script at:"
    echo -e "  ${BLUE}https://github.com/hubofvalley/Valley-of-Limonata-Testnet/blob/main/resources/limonata_node_install_testnet.sh${RESET}"

    echo -e "\n${YELLOW}2. SYSTEM IMPACT:${RESET}"
    echo -e "${GREEN}New Service:${RESET}"
    echo -e "  • ${CYAN}${LIMONATA_SERVICE_NAME}.service${RESET} (Limonata Node)"
    echo -e "\n${RED}Existing Service to be Replaced:${RESET}"
    echo -e "  • ${CYAN}${LIMONATA_SERVICE_NAME}${RESET}"
    echo -e "${RED}Re-deploying permanently deletes ${LIMONATA_HOME}, including local block data and priv_validator_key.json.${RESET}"
    echo -e "${RED}Back up the validator key with menu 3d and store the operator mnemonic offline before continuing.${RESET}"

    echo -e "\n${GREEN}Port Configuration:${RESET}"
    echo -e "Ports will be adjusted based on your input (example if you enter 38):"
    echo -e "  • ${CYAN}38657${RESET} (RPC) <-- 26657"
    echo -e "  • ${CYAN}38656${RESET} (P2P) <-- 26656"
    echo -e "  • ${CYAN}38545${RESET} (EVM-RPC) <-- 8545"
    echo -e "  • ${CYAN}38546${RESET} (EVM WebSocket) <-- 8546"

    echo -e "\n${GREEN}Directories:${RESET}"
    echo -e "  • ${CYAN}$HOME/.limonatad${RESET}"
    echo -e "  • ${CYAN}$HOME/go/bin/limonatad${RESET} (operator-facing binary symlink)"

    echo -e "\n${YELLOW}3. REQUIREMENTS:${RESET}"
    echo "- CPU: 2+ vCPU, RAM: 4+ GB, Storage: 50+ GB SSD"
    echo "- Ubuntu 22.04/24.04 recommended"
    echo "- P2P port must be publicly reachable"

    echo -e "\n${YELLOW}4. VALIDATOR RESPONSIBILITIES:${RESET}"
    echo "- As a validator, you'll need to:"
    echo "  - Maintain good uptime (recommended 99%+)"
    echo "  - Keep your node software updated"
    echo "  - Regularly backup your keys and data"
    echo "- Note: Limonata testnet has no staking inflation;"
    echo "  validators earn transaction fees + commission"

    echo -e "\n${GREEN}By continuing you agree to these terms.${RESET}"
    read -r -p $'\n\e[33mDo you want to proceed with installation? (yes/no): \e[0m' confirm

    if [[ "${confirm,,}" != "yes" ]]; then
        echo -e "${RED}Installation cancelled by user.${RESET}"
        menu
        return
    fi

    if [ -d "$LIMONATA_HOME" ] || [ -f "/etc/systemd/system/${LIMONATA_SERVICE_NAME}.service" ] || command -v limonatad >/dev/null 2>&1; then
        echo -e "\n${RED}An existing Limonata installation was detected.${RESET}"
        read -r -p "Type REDEPLOY to confirm permanent deletion of the existing node data: " redeploy_confirm
        if [ "$redeploy_confirm" != "REDEPLOY" ]; then
            echo -e "${RED}Re-deployment cancelled. No node data was changed.${RESET}"
            menu
            return
        fi
    fi

    echo -e "\n${GREEN}Starting installation...${RESET}"
    echo -e "${YELLOW}This may take 1-5 minutes. Please don't interrupt the process.${RESET}"
    sleep 2

    LIMONATA_REDEPLOY_CONFIRMED=1 bash <(curl -s https://raw.githubusercontent.com/hubofvalley/Valley-of-Limonata-Testnet/main/resources/limonata_node_install_testnet.sh)
    hash -r
    menu
}

function update_limonata_binary() {
    echo -e "${YELLOW}You are about to check the reviewed Limonata binary target and upgrade path.${RESET}"
    if ! prompt_back_or_continue; then
        return
    fi
    bash <(curl -s https://raw.githubusercontent.com/hubofvalley/Valley-of-Limonata-Testnet/main/resources/limonata_update.sh)
    hash -r
    menu
}

function add_peers() {
    echo "Select an option:"
    echo "1. Add peers manually"
    echo "2. Reset to official seed peer"
    echo "3. Back"
    read -r -p "Enter your choice (1, 2, or 3): " choice

    CFG=$LIMONATA_HOME/config/config.toml
    if [ ! -f "$CFG" ]; then
        echo -e "${RED}config.toml not found at $CFG. Deploy the node first.${RESET}"
        menu
        return
    fi

    case $choice in
        1)
            read -r -p "Enter peers (comma-separated id@host:port): " peers
            echo "You have entered the following peers: $peers"
            read -r -p "Do you want to proceed? (yes/no): " confirm
            if [[ "${confirm,,}" == "yes" ]]; then
                sed -i -e "s|^persistent_peers *=.*|persistent_peers = \"$peers\"|" "$CFG"
                echo "Peers added manually."
            else
                echo "Operation cancelled. Returning to menu."
            fi
            ;;
        2)
            sed -i -e "s|^persistent_peers *=.*|persistent_peers = \"4b154368aab24cb5b31c927efd50c73d0f4f9799@142.127.103.79:26656\"|" "$CFG"
            echo "Official seed peer restored."
            ;;
        3)
            menu
            return
            ;;
        *)
            echo "Invalid choice. Please enter 1, 2, or 3."
            add_peers
            return
            ;;
    esac
    echo -e "\n${YELLOW}Now you can restart your Limonata node to apply changes.${RESET}"
    menu
}

function show_node_status() {
    local port status_json node_height catching_up network_height block_difference
    port=$(get_local_rpc_port)
    if [ -z "$port" ]; then
        echo -e "${RED}Cannot find local RPC port in $LIMONATA_HOME/config/config.toml. Deploy the node first.${RESET}"
        echo -e "${YELLOW}Press Enter to go back to Valley of Limonata main menu${RESET}"
        read -r
        menu
        return
    fi

    status_json=$(get_local_status_json)
    node_height=$(echo "$status_json" | jq -r '.result.sync_info.latest_block_height // empty' 2>/dev/null)
    if [ -z "$node_height" ]; then
        echo -e "${RED}Cannot reach local node RPC at http://127.0.0.1:${port}/status. Is ${LIMONATA_SERVICE_NAME}.service running?${RESET}"
    else
        echo -e "${CYAN}Local RPC status: curl http://127.0.0.1:${port}/status | jq${RESET}"
        echo "$status_json" | jq .
        echo
        catching_up=$(echo "$status_json" | jq -r '.result.sync_info.catching_up' 2>/dev/null)
        if [ "$catching_up" = "null" ] || [ -z "$catching_up" ]; then
            catching_up="unknown"
        fi
        echo "Local Limonata node block height: $node_height"
        network_height=$(get_network_height)
        if [ -n "$network_height" ]; then
            block_difference=$((network_height - node_height))
            echo "Network latest block height: $network_height"
            echo "Block Difference: $block_difference"
            if [ "$block_difference" -lt 0 ]; then
                echo -e "${YELLOW}A negative value is normal when the local Limonata node is slightly ahead of the public RPC.${RESET}"
            fi
        else
            echo -e "${YELLOW}Network latest block height: unavailable from $LIMONATA_EVM_RPC${RESET}"
        fi
        echo -e "Catching up: ${YELLOW}$catching_up${RESET}"
        if [ "$catching_up" = "false" ]; then
            echo -e "${GREEN}Node is fully synced.${RESET}"
        else
            echo -e "${YELLOW}Node is still syncing. Check again later.${RESET}"
        fi
    fi
    echo -e "${YELLOW}Press Enter to go back to Valley of Limonata main menu${RESET}"
    read -r
    menu
}

function show_logs() {
    trap 'echo -e "\nStopping logs and returning to main menu...";' INT
    sudo journalctl -u "$LIMONATA_SERVICE_NAME" -fn 100 -o cat || true
    trap - INT
    menu
}

function create_operator_key() {
    echo "Choose an option:"
    echo "1. Create a new operator key"
    echo "2. Recover an existing key from mnemonic"
    echo "3. Back"
    read -r -p "Enter your choice (1, 2, or 3): " choice

    case $choice in
        1)
            read -r -p "Enter key name (default 'operator'): " keyname
            keyname=${keyname:-operator}
            limonata_cmd keys add "$keyname"
            echo -e "\n${RED}WRITE DOWN THE MNEMONIC ABOVE AND STORE IT OFFLINE. It will not be shown again.${RESET}"
            ;;
        2)
            read -r -p "Enter key name (default 'operator'): " keyname
            keyname=${keyname:-operator}
            limonata_cmd keys add "$keyname" --recover
            ;;
        3)
            menu
            return
            ;;
        *)
            echo "Invalid choice. Please enter 1, 2, or 3."
            create_operator_key
            return
            ;;
    esac
    echo -e "\n${YELLOW}Get test LIMO for this address from the faucet: ${BLUE}https://faucet.limonata.xyz${RESET}"
    echo -e "${YELLOW}Press Enter to go back to main menu${RESET}"
    read -r
    menu
}

function show_validator_pubkey() {
    echo -e "${CYAN}Your validator consensus public key:${RESET}"
    limonata_cmd comet show-validator
    echo -e "\n${YELLOW}Use this pubkey in validator.json when creating your validator. Press Enter to go back to main menu...${RESET}"
    read -r
    menu
}

function create_validator() {
    if ! command -v bc &> /dev/null; then
        echo -e "${RED}bc is required but is not installed. Re-run the installer or install bc before creating a validator.${RESET}"
        menu
        return
    fi

    echo -e "${CYAN}Create Limonata Validator${RESET}"
    echo -e "${YELLOW}Requirements: node fully synced + operator key funded with test LIMO (https://faucet.limonata.xyz).${RESET}"
    if ! prompt_back_or_continue; then
        return
    fi

    read -r -p "Enter your key name (default 'operator'): " KEY_NAME
    KEY_NAME=${KEY_NAME:-operator}
    KEY_NAME=$(echo "$KEY_NAME" | tr -d '\r')
    if ! limonata_cmd keys show "$KEY_NAME" >/dev/null; then
        echo -e "${RED}Key '$KEY_NAME' was not found in the local keyring. Create or recover it with menu 2a first.${RESET}"
        menu
        return
    fi

    if [ "$(get_local_catching_up)" != "false" ]; then
        echo -e "${RED}The local node is not confirmed fully synced. Use menu 1d and wait for catching_up=false.${RESET}"
        menu
        return
    fi

    SAVED_MONIKER=${LIMONATA_MONIKER:-}
    while true; do
        if [ -n "$SAVED_MONIKER" ]; then
            read -r -p "Enter the validator moniker (default '$SAVED_MONIKER'): " LIMONATA_MONIKER
            LIMONATA_MONIKER=${LIMONATA_MONIKER:-$SAVED_MONIKER}
        else
            read -r -p "Enter the validator moniker: " LIMONATA_MONIKER
        fi
        [ -n "$LIMONATA_MONIKER" ] && break
        echo -e "${RED}Validator moniker cannot be empty.${RESET}"
    done
    while true; do
        read -r -p "Enter the amount to self-stake in LIMO (e.g., 1 for 1 LIMO): " STAKE_LIMO
        STAKE_LIMO="${STAKE_LIMO//,/.}"
        is_positive_decimal "$STAKE_LIMO" && break
        echo -e "${RED}Enter a positive numeric LIMO amount.${RESET}"
    done

    while true; do
        read -r -p "Enter commission rate (e.g., 0.10 for 10%, default 0.10): " COMMISSION_RATE
        COMMISSION_RATE=${COMMISSION_RATE:-0.10}
        is_rate "$COMMISSION_RATE" && break
        echo -e "${RED}Commission rate must be between 0 and 1.${RESET}"
    done
    while true; do
        read -r -p "Enter max commission rate (e.g., 0.20 for 20%, default 0.20): " MAX_COMMISSION_RATE
        MAX_COMMISSION_RATE=${MAX_COMMISSION_RATE:-0.20}
        is_rate "$MAX_COMMISSION_RATE" && break
        echo -e "${RED}Maximum commission rate must be between 0 and 1.${RESET}"
    done
    while true; do
        read -r -p "Enter max commission change rate (e.g., 0.01 for 1%/day, default 0.01): " MAX_CHANGE_RATE
        MAX_CHANGE_RATE=${MAX_CHANGE_RATE:-0.01}
        is_rate "$MAX_CHANGE_RATE" && break
        echo -e "${RED}Maximum commission change rate must be between 0 and 1.${RESET}"
    done
    if ! awk -v rate="$COMMISSION_RATE" -v max="$MAX_COMMISSION_RATE" -v change="$MAX_CHANGE_RATE" \
        'BEGIN { exit !(rate <= max && change <= max) }'; then
        echo -e "${RED}Commission rate and maximum daily change cannot exceed the maximum commission rate.${RESET}"
        menu
        return
    fi
    read -r -p "Enter validator website (optional): " WEBSITE
    read -r -p "Enter validator details (optional): " DETAILS

    # Convert LIMO to aLIMO (1 LIMO = 10^18 aLIMO)
    STAKE=$(echo "$STAKE_LIMO * 10^18" | bc)
    STAKE=${STAKE%%.*}
    if ! [[ "$STAKE" =~ ^[0-9]+$ ]] || ! [[ "$STAKE" =~ [1-9] ]]; then
        echo -e "${RED}The self-stake amount is smaller than 1 aLIMO or cannot be converted safely.${RESET}"
        menu
        return
    fi

    PUBKEY=$(limonata_cmd comet show-validator)
    if [ -z "$PUBKEY" ]; then
        echo -e "${RED}Error: could not read validator pubkey. Is the node initialized?${RESET}"
        menu
        return
    fi
    if ! echo "$PUBKEY" | jq -e . >/dev/null 2>&1; then
        echo -e "${RED}Error: validator public key is not valid JSON.${RESET}"
        menu
        return
    fi

    VALIDATOR_JSON=$(mktemp)
    jq -n \
        --argjson pubkey "$PUBKEY" \
        --arg amount "${STAKE}aLIMO" \
        --arg moniker "$LIMONATA_MONIKER" \
        --arg website "$WEBSITE" \
        --arg details "$DETAILS" \
        --arg commission_rate "$COMMISSION_RATE" \
        --arg commission_max_rate "$MAX_COMMISSION_RATE" \
        --arg commission_max_change_rate "$MAX_CHANGE_RATE" \
        '{
          pubkey: $pubkey,
          amount: $amount,
          moniker: $moniker,
          identity: "",
          website: $website,
          security: "",
          details: $details,
          "commission-rate": $commission_rate,
          "commission-max-rate": $commission_max_rate,
          "commission-max-change-rate": $commission_max_change_rate,
          "min-self-delegation": "1"
        }' > "$VALIDATOR_JSON"

    echo -e "${YELLOW}validator.json to be submitted:${RESET}"
    cat "$VALIDATOR_JSON"
    read -r -p $'\n\e[33mSubmit create-validator transaction? (yes/no): \e[0m' confirm
    if [[ "${confirm,,}" != "yes" ]]; then
        rm -f "$VALIDATOR_JSON"
        echo -e "${RED}Cancelled.${RESET}"
        menu
        return
    fi

    if limonata_cmd tx staking create-validator "$VALIDATOR_JSON" \
        --from "$KEY_NAME" \
        --chain-id "$LIMONATA_CHAIN_ID" \
        --gas auto --gas-adjustment 1.4 --gas-prices "$LIMONATA_STAKING_GAS_PRICE" -y; then
        echo -e "\n${GREEN}Create-validator transaction submitted successfully.${RESET}"
        echo -e "${YELLOW}Build a reliable track record, then apply at ${BLUE}https://limonata.xyz/#validator${RESET}${YELLOW} with your valoper address and a new, never-funded grant-wallet address.${RESET}"
    else
        echo -e "\n${RED}Create-validator transaction failed. Review the error above; no success was recorded.${RESET}"
    fi

    rm -f "$VALIDATOR_JSON"
    echo -e "${YELLOW}Press Enter to go back to main menu${RESET}"
    read -r
    menu
}

function query_balance() {
    echo -e "${CYAN}Select an option:${RESET}"
    echo "1. Query balance of a key in your local keyring"
    echo "2. Query balance of another address"
    echo "3. Back"
    read -r -p "Enter your choice (1, 2, or 3): " choice

    case $choice in
        1)
            read -r -p "Enter key name (default 'operator'): " keyname
            keyname=${keyname:-operator}
            address=$(limonata_cmd keys show "$keyname" -a)
            if [ -z "$address" ]; then
                echo -e "${RED}Key '$keyname' not found in keyring.${RESET}"
                menu
                return
            fi
            ;;
        2)
            read -r -p "Enter the address to query (cosmos1...): " address
            ;;
        3)
            menu
            return
            ;;
        *)
            echo -e "${RED}Invalid choice. Please enter 1, 2, or 3.${RESET}"
            query_balance
            return
            ;;
    esac

    echo -e "${CYAN}Fetching balance for $address...${RESET}"
    limonata_cmd query bank balances "$address"
    echo -e "\n${YELLOW}Note: amounts are in aLIMO (1 LIMO = 10^18 aLIMO).${RESET}"
    echo -e "${YELLOW}Press Enter to go back to main menu...${RESET}"
    read -r
    menu
}

function delegate_tokens() {
    if ! command -v bc &> /dev/null; then
        echo -e "${RED}bc is required but is not installed. Re-run the installer or install bc before delegating.${RESET}"
        menu
        return
    fi

    read -r -p "Enter your key name (default 'operator'): " KEY_NAME
    KEY_NAME=${KEY_NAME:-operator}
    if ! limonata_cmd keys show "$KEY_NAME" >/dev/null; then
        echo -e "${RED}Key '$KEY_NAME' was not found in the local keyring.${RESET}"
        menu
        return
    fi

    echo "Choose an option to delegate tokens:"
    echo "1. Delegate to self (your own validator)"
    echo "2. Delegate to another validator"
    echo "3. Back"
    read -r -p "Enter your choice (1/2/3): " CHOICE

    case $CHOICE in
        1)
            VALOPER=$(limonata_cmd keys show "$KEY_NAME" --bech val -a)
            if [ -z "$VALOPER" ]; then
                read -r -p "Could not derive valoper from key '$KEY_NAME'. Enter your valoper address: " VALOPER
            fi
            ;;
        2)
            read -r -p "Enter validator operator address (...valoper1...): " VALOPER
            ;;
        3)
            menu
            return
            ;;
        *)
            echo "Invalid choice. Please select a valid option."
            delegate_tokens
            return
            ;;
    esac

    if [ -z "$VALOPER" ]; then
        echo -e "${RED}Validator operator address cannot be empty.${RESET}"
        menu
        return
    fi
    if ! [[ "$VALOPER" =~ ^cosmosvaloper1[0-9a-z]+$ ]]; then
        echo -e "${RED}Invalid validator operator address. Expected a cosmosvaloper1... address.${RESET}"
        menu
        return
    fi
    while true; do
        read -r -p "Enter the amount to delegate in LIMO: " AMOUNT_LIMO
        AMOUNT_LIMO="${AMOUNT_LIMO//,/.}"
        is_positive_decimal "$AMOUNT_LIMO" && break
        echo -e "${RED}Enter a positive numeric LIMO amount.${RESET}"
    done
    AMOUNT=$(echo "$AMOUNT_LIMO * 10^18" | bc)
    AMOUNT=${AMOUNT%%.*}
    if ! [[ "$AMOUNT" =~ ^[0-9]+$ ]] || ! [[ "$AMOUNT" =~ [1-9] ]]; then
        echo -e "${RED}The delegation amount is smaller than 1 aLIMO or cannot be converted safely.${RESET}"
        menu
        return
    fi

    echo -e "\n${YELLOW}Delegation transaction review:${RESET}"
    echo -e "- From key: ${CYAN}$KEY_NAME${RESET}"
    echo -e "- Validator: ${CYAN}$VALOPER${RESET}"
    echo -e "- Amount: ${CYAN}${AMOUNT}aLIMO (${AMOUNT_LIMO} LIMO)${RESET}"
    echo -e "- Gas price: ${CYAN}${LIMONATA_STAKING_GAS_PRICE}${RESET}"
    read -r -p "Submit this delegation transaction? (yes/no): " delegate_confirm
    if [[ "${delegate_confirm,,}" != "yes" ]]; then
        echo -e "${GREEN}Delegation cancelled. No transaction was submitted.${RESET}"
        menu
        return
    fi

    if limonata_cmd tx staking delegate "$VALOPER" "${AMOUNT}aLIMO" \
         --from "$KEY_NAME" \
         --chain-id "$LIMONATA_CHAIN_ID" \
         --gas auto --gas-adjustment 1.4 --gas-prices "$LIMONATA_STAKING_GAS_PRICE" -y; then
         echo -e "${GREEN}Delegation transaction submitted successfully.${RESET}"
     else
         echo -e "${RED}Delegation transaction failed. Review the error above.${RESET}"
     fi

    echo -e "${YELLOW}Press Enter to go back to main menu${RESET}"
    read -r
    menu
}

function query_validator_status() {
    read -r -p "Enter validator operator address (cosmosvaloper1..., or leave empty to derive it from a key): " VALOPER
    if [ -z "$VALOPER" ]; then
        read -r -p "Enter key name (default 'operator'): " keyname
        keyname=${keyname:-operator}
        VALOPER=$(limonata_cmd keys show "$keyname" --bech val -a)
    fi
    if ! [[ "$VALOPER" =~ ^cosmosvaloper1[0-9a-z]+$ ]]; then
        echo -e "${RED}No valid cosmosvaloper1... address is available.${RESET}"
        menu
        return
    fi
    limonata_cmd query staking validator "$VALOPER"
    echo -e "\n${YELLOW}Press Enter to go back to main menu${RESET}"
    read -r
    menu
}

function backup_validator_key() {
    local source_key="$LIMONATA_HOME/config/priv_validator_key.json"
    local backup_key="$HOME/priv_validator_key.json"
    if [ -f "$source_key" ]; then
        if [ -e "$backup_key" ]; then
            read -r -p "A backup already exists at $backup_key. Type OVERWRITE to replace it: " backup_confirm
            if [ "$backup_confirm" != "OVERWRITE" ]; then
                echo -e "${GREEN}Backup cancelled. The existing backup was not changed.${RESET}"
                menu
                return
            fi
        fi
        install -m 600 "$source_key" "$backup_key"
        echo -e "\n${YELLOW}Your priv_validator_key.json file has been copied to $backup_key with mode 600.${RESET}"
        echo -e "${RED}Move it somewhere safe and offline.${RESET}"
    else
        echo -e "${RED}priv_validator_key.json not found. Deploy the node first.${RESET}"
    fi
    menu
}

function restart_limonata() {
    sudo systemctl daemon-reload
    if sudo systemctl restart "$LIMONATA_SERVICE_NAME" && systemctl is-active --quiet "$LIMONATA_SERVICE_NAME"; then
        echo -e "${GREEN}${LIMONATA_SERVICE_NAME}.service restarted successfully.${RESET}"
    else
        echo -e "${RED}Failed to restart ${LIMONATA_SERVICE_NAME}.service. Check menu 1e or journalctl.${RESET}"
    fi
    menu
}

function stop_limonata() {
    if sudo systemctl stop "$LIMONATA_SERVICE_NAME" && ! systemctl is-active --quiet "$LIMONATA_SERVICE_NAME"; then
        echo -e "${YELLOW}${LIMONATA_SERVICE_NAME}.service stopped successfully.${RESET}"
    else
        echo -e "${RED}Failed to stop ${LIMONATA_SERVICE_NAME}.service.${RESET}"
    fi
    menu
}

function delete_limonata_node() {
    if ! require_standard_limonata_home; then
        menu
        return
    fi
    echo -e "${YELLOW}You are about to delete the Limonata node.${RESET}"
    echo -e "${RED}BACKUP YOUR MNEMONIC AND priv_validator_key.json BEFORE YOU DO THIS.${RESET}"
    echo -e "${RED}This permanently removes ${LIMONATA_HOME}, the service, the binary, and saved LIMONATA_* environment variables.${RESET}"
    read -r -p "Type DELETE to confirm permanent deletion: " delete_confirm
    if [ "$delete_confirm" != "DELETE" ]; then
        echo -e "${GREEN}Deletion cancelled. No node data was changed.${RESET}"
        menu
        return
    fi
    sudo systemctl stop "$LIMONATA_SERVICE_NAME" || true
    sudo systemctl disable "$LIMONATA_SERVICE_NAME" || true
    sudo rm -f "/etc/systemd/system/${LIMONATA_SERVICE_NAME}.service"
    sudo systemctl daemon-reload
    sudo rm -rf "$LIMONATA_HOME"
    rm -f "$HOME/go/bin/limonatad"
    sudo rm -f /usr/local/bin/limonatad
    sed -i "/LIMONATA_/d" "$HOME/.bash_profile"
    hash -r
    echo -e "${RED}Limonata node deleted. Remember to clean up any keys you backed up elsewhere.${RESET}"
    menu
}

function show_endpoints() {
    echo -e "$ENDPOINTS"
    echo -e "${YELLOW}Press Enter to go back to Valley of Limonata main menu${RESET}"
    read -r
    menu
}

function show_guidelines() {
    echo -e "${CYAN}Guidelines on How to Use the Valley of Limonata${RESET}"
    echo -e "${GREEN}Navigation:${RESET}"
    echo " - Enter the number/letter pair (e.g., 1a) or type the number then the letter."
    echo " - Reply to normal confirmations with 'yes' or 'no'; press Enter to accept displayed defaults."
    echo " - Destructive actions require the exact words REDEPLOY or DELETE; backup replacement requires OVERWRITE."
    echo " - Run the script as the same user that owns ~/.limonatad to avoid permission issues."
    echo -e "${GREEN}Recommended flow for a new validator:${RESET}"
    echo " - 1a Deploy node -> wait until 1d shows catching_up=false"
    echo " - 3d Back up the validator key immediately after deployment"
    echo " - 2a Create operator key -> fund it via https://faucet.limonata.xyz"
    echo " - 2c Create validator -> build a reliable track record"
    echo " - Apply at https://limonata.xyz/#validator with the valoper address and a new, never-funded grant wallet"
    echo -e "${GREEN}Menu options:${RESET}"
    echo " - 1a Deploy/re-deploy the node with the reviewed binary and Cosmovisor; re-deploy permanently replaces existing node data."
    echo " - 1b Check the reviewed binary target; Cosmovisor-managed nodes refuse direct replacement."
    echo " - 1c Add peers manually or restore the official peer."
    echo " - 1d Show local RPC status, sync state, and the network height gap."
    echo " - 1e Follow the node service logs; press Ctrl+C to return."
    echo " - 2a Create a new operator key or recover one from a mnemonic."
    echo " - 2b Show the validator consensus public key."
    echo " - 2c Review and submit a create-validator transaction."
    echo " - 2d Query the balance of a key or address."
    echo " - 2e Review and submit a delegation transaction."
    echo " - 2f Query validator status by valoper address."
    echo " - 3a Restart the node service."
    echo " - 3b Stop the node service."
    echo " - 3c Permanently delete the node after explicit confirmation."
    echo " - 3d Back up priv_validator_key.json to your home directory."
    echo " - 4 Show official endpoints and useful links."
    echo " - 5 Show these guidelines."
    echo " - 6 Exit the tool."
    echo -e "${GREEN}Operations:${RESET}"
    echo " - Operator-facing limonatad path: $HOME/go/bin/limonatad."
    echo " - After deploying or updating, use 1d (status) and 1e (logs) to verify the node."
    echo " - Run 'source ~/.bash_profile' after exiting to refresh saved environment variables in your login shell."
    echo " - Stop the service before deleting or redeploying to prevent lock errors."
    echo -e "${GREEN}Safety:${RESET}"
    echo " - Never share private keys, mnemonics, or RPC auth details."
    echo " - Testnet tokens are valueless; stake delegated by the team remains team property."
    echo -e "${YELLOW}Press Enter to go back to Valley of Limonata main menu${RESET}"
    read -r
    menu
}

# Menu function
function menu() {
    local_height=$(get_local_height)
    [ -z "$local_height" ] && local_height="N/A (node not running)"
    network_height=$(get_network_height)
    [ -z "$network_height" ] && network_height="N/A ($LIMONATA_EVM_RPC unavailable)"
    block_gap="N/A"
    if [[ "$network_height" =~ ^[0-9]+$ && "$local_height" =~ ^[0-9]+$ ]]; then
        block_gap=$((network_height - local_height))
    fi
    echo -e "${ORANGE}Valley of Limonata Testnet${RESET}"
    echo "Main Menu:"
    echo -e "${GREEN}1. Node Interactions:${RESET}"
    echo "   a. Deploy/Re-deploy Limonata Node"
    echo "   b. Update Limonata Binary"
    echo "   c. Add Peers"
    echo "   d. Show Node Status"
    echo "   e. Show Node Logs"
    echo -e "${GREEN}2. Validator/Key Interactions:${RESET}"
    echo "   a. Create/Recover Operator Key"
    echo "   b. Show Validator Consensus Pubkey"
    echo "   c. Create Validator"
    echo "   d. Query Balance"
    echo "   e. Delegate Tokens"
    echo "   f. Query Validator Status"
    echo -e "${GREEN}3. Node Management:${RESET}"
    echo "   a. Restart Limonata Node"
    echo "   b. Stop Limonata Node"
    echo "   c. Delete Limonata Node (BACKUP YOUR MNEMONIC AND priv_validator_key.json BEFORE YOU DO THIS)"
    echo "   d. Backup Validator Key (store it to $HOME directory)"
    echo -e "${GREEN}4. Show Endpoints & Useful Links${RESET}"
    echo -e "${YELLOW}5. Show Guidelines${RESET}"
    echo -e "${RED}6. Exit${RESET}"

    echo -e "${GREEN}Latest Block Height:${RESET} ${CYAN}$network_height${RESET}"
    echo -e "Local Node Block Height: ${CYAN}$local_height${RESET}"
    echo -e "Block Difference: ${YELLOW}$block_gap${RESET}"
    if [[ "$block_gap" =~ ^- ]]; then
        echo -e "${YELLOW}A negative value is normal when the local Limonata node is slightly ahead of the public RPC.${RESET}"
    fi
    echo -e "\n${YELLOW}Please run the following command to apply the changes after exiting the script:${RESET}"
    echo -e "${GREEN}source ~/.bash_profile${RESET}"
    echo -e "${YELLOW}This ensures the environment variables are set in your current bash session.${RESET}"
    echo -e "${GREEN}Let's Buidl Limonata Together - Grand Valley${RESET}"
    read -r -p "Choose an option (e.g., 1a or 1 then a): " OPTION

    if [[ $OPTION =~ ^[1-3][a-z]$ ]]; then
        MAIN_OPTION=${OPTION:0:1}
        SUB_OPTION=${OPTION:1:1}
    else
        MAIN_OPTION=$OPTION
        if [[ $MAIN_OPTION =~ ^[1-3]$ ]]; then
            read -r -p "Choose a sub-option: " SUB_OPTION
        fi
    fi

    case $MAIN_OPTION in
        1)
            case $SUB_OPTION in
                a) deploy_limonata_node ;;
                b) update_limonata_binary ;;
                c) add_peers ;;
                d) show_node_status ;;
                e) show_logs ;;
                *) echo "Invalid sub-option. Please try again."; menu; return ;;
            esac
            ;;
        2)
            case $SUB_OPTION in
                a) create_operator_key ;;
                b) show_validator_pubkey ;;
                c) create_validator ;;
                d) query_balance ;;
                e) delegate_tokens ;;
                f) query_validator_status ;;
                *) echo "Invalid sub-option. Please try again."; menu; return ;;
            esac
            ;;
        3)
            case $SUB_OPTION in
                a) restart_limonata ;;
                b) stop_limonata ;;
                c) delete_limonata_node ;;
                d) backup_validator_key ;;
                *) echo "Invalid sub-option. Please try again."; menu; return ;;
            esac
            ;;
        4) show_endpoints ;;
        5) show_guidelines ;;
        6) exit 0 ;;
        *) echo "Invalid option. Please try again."; menu; return ;;
    esac
}

# Start menu
menu
