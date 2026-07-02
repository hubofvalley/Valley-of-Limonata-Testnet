#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
ORANGE='\033[38;5;214m'
RESET='\033[0m'

# Service Name Detection - Ask Once, Remember Forever
source $HOME/.bash_profile 2>/dev/null

if [ -z "${LIMONATA_SERVICE_NAME:-}" ]; then
    echo -e "${YELLOW}Service name configuration not found.${RESET}"
    read -p "Enter Service Name (default 'limonatad'): " INPUT_SVC
    LIMONATA_SERVICE_NAME=${INPUT_SVC:-limonatad}
    echo "export LIMONATA_SERVICE_NAME=\"$LIMONATA_SERVICE_NAME\"" >> $HOME/.bash_profile
    export LIMONATA_SERVICE_NAME
fi

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

INTRO="
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
- current chain ID: ${CYAN}limonata_10777-1${RESET} (EVM chain ID: ${CYAN}10777${RESET})
- native denom: ${CYAN}aLIMO${RESET} (1 LIMO = 10^18 aLIMO)
- binary: ${CYAN}limonatad${RESET} (latest release)
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
- GitHub: ${BLUE}https://github.com/Limonata-Blockchain/limonata${RESET}

${GREEN}Network facts:${RESET}
- Chain ID: ${CYAN}limonata_10777-1${RESET} | EVM Chain ID: ${CYAN}10777${RESET} (hex: 0x2a19)
- Seed/peer: ${CYAN}4b154368aab24cb5b31c927efd50c73d0f4f9799@142.127.103.79:26656${RESET}
- Genesis: ${BLUE}https://limonata.xyz/genesis.json${RESET}
- No staking inflation (x/mint disabled) - validators earn tx fees + commission
- Zero-fee transactions (gas sponsored by protocol)

${GREEN}Connect with Grand Valley:${RESET}
- X: ${BLUE}https://x.com/bacvalley${RESET}
- GitHub: ${BLUE}https://github.com/hubofvalley${RESET}
- Email: ${BLUE}letsbuidltogether@grandvalleys.com${RESET}
"
# TODO-GV-ENDPOINT: tambahkan endpoint *-grandvalleys.com untuk Limonata setelah infra GV live.

# Display LOGO and wait for user input to continue
echo -e "$LOGO"
echo -e "$PRIVACY_SAFETY_STATEMENT"
echo -e "\n${YELLOW}Press Enter to continue...${RESET}"
read -r

# Display INTRO section and wait for user input to continue
echo -e "$INTRO"
echo -e "$ENDPOINTS"
echo -e "\n${YELLOW}Press Enter to continue${RESET}"
read -r

grep -q "LIMONATA_CHAIN_ID" $HOME/.bash_profile 2>/dev/null || echo "export LIMONATA_CHAIN_ID=\"limonata_10777-1\"" >> $HOME/.bash_profile
grep -q "LIMONATA_EVM_CHAIN_ID" $HOME/.bash_profile 2>/dev/null || echo "export LIMONATA_EVM_CHAIN_ID=\"10777\"" >> $HOME/.bash_profile
source $HOME/.bash_profile

function get_local_height() {
    limonatad status 2>/dev/null | jq -r '.sync_info.latest_block_height // .SyncInfo.latest_block_height // empty' 2>/dev/null
}

function prompt_back_or_continue() {
    read -p "Press Enter to continue or type 'back' to go back to the menu: " user_choice
    if [[ ${user_choice,,} == "back" ]]; then
        menu
        return 1
    fi
    return 0
}

function deploy_limonata_node() {
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

    echo -e "\n${GREEN}Port Configuration:${RESET}"
    echo -e "Ports will be adjusted based on your input (example if you enter 38):"
    echo -e "  • ${CYAN}38657${RESET} (RPC) <-- 26657"
    echo -e "  • ${CYAN}38656${RESET} (P2P) <-- 26656"
    echo -e "  • ${CYAN}38545${RESET} (EVM-RPC) <-- 8545"
    echo -e "  • ${CYAN}38546${RESET} (EVM WebSocket) <-- 8546"

    echo -e "\n${GREEN}Directories:${RESET}"
    echo -e "  • ${CYAN}$HOME/.limonatad${RESET}"

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
    read -p $'\n\e[33mDo you want to proceed with installation? (yes/no): \e[0m' confirm

    if [[ "${confirm,,}" != "yes" ]]; then
        echo -e "${RED}Installation cancelled by user.${RESET}"
        menu
        return
    fi

    echo -e "\n${GREEN}Starting installation...${RESET}"
    echo -e "${YELLOW}This may take 1-5 minutes. Please don't interrupt the process.${RESET}"
    sleep 2

    bash <(curl -s https://raw.githubusercontent.com/hubofvalley/Valley-of-Limonata-Testnet/main/resources/limonata_node_install_testnet.sh)
    menu
}

function update_limonata_binary() {
    echo -e "${YELLOW}You are about to update your Limonata node binary to the latest release.${RESET}"
    if ! prompt_back_or_continue; then
        return
    fi
    bash <(curl -s https://raw.githubusercontent.com/hubofvalley/Valley-of-Limonata-Testnet/main/resources/limonata_update.sh)
    menu
}

function add_peers() {
    echo "Select an option:"
    echo "1. Add peers manually"
    echo "2. Reset to official seed peer"
    echo "3. Back"
    read -p "Enter your choice (1, 2, or 3): " choice

    CFG=$HOME/.limonatad/config/config.toml
    if [ ! -f "$CFG" ]; then
        echo -e "${RED}config.toml not found at $CFG. Deploy the node first.${RESET}"
        menu
        return
    fi

    case $choice in
        1)
            read -p "Enter peers (comma-separated id@host:port): " peers
            echo "You have entered the following peers: $peers"
            read -p "Do you want to proceed? (yes/no): " confirm
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
    node_height=$(get_local_height)
    if [ -z "$node_height" ]; then
        echo -e "${RED}Cannot reach local node RPC. Is ${LIMONATA_SERVICE_NAME}.service running?${RESET}"
    else
        catching_up=$(limonatad status 2>/dev/null | jq -r '.sync_info.catching_up // .SyncInfo.catching_up // "unknown"')
        echo "Local Limonata node block height: $node_height"
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
    sudo journalctl -u ${LIMONATA_SERVICE_NAME} -fn 100 -o cat || true
    trap - INT
    menu
}

function create_operator_key() {
    echo "Choose an option:"
    echo "1. Create a new operator key"
    echo "2. Recover an existing key from mnemonic"
    echo "3. Back"
    read -p "Enter your choice (1, 2, or 3): " choice

    case $choice in
        1)
            read -p "Enter key name (default 'operator'): " keyname
            keyname=${keyname:-operator}
            limonatad keys add "$keyname"
            echo -e "\n${RED}WRITE DOWN THE MNEMONIC ABOVE AND STORE IT OFFLINE. It will not be shown again.${RESET}"
            ;;
        2)
            read -p "Enter key name (default 'operator'): " keyname
            keyname=${keyname:-operator}
            limonatad keys add "$keyname" --recover
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
    limonatad comet show-validator
    echo -e "\n${YELLOW}Use this pubkey in validator.json when creating your validator. Press Enter to go back to main menu...${RESET}"
    read -r
    menu
}

function create_validator() {
    if ! command -v bc &> /dev/null; then
        echo "bc is not installed. Installing bc..."
        sudo apt-get update
        sudo apt-get install -y bc
    fi

    echo -e "${CYAN}Create Limonata Validator${RESET}"
    echo -e "${YELLOW}Requirements: node fully synced + operator key funded with test LIMO (https://faucet.limonata.xyz).${RESET}"
    if ! prompt_back_or_continue; then
        return
    fi

    read -p "Enter your key name (default 'operator'): " KEY_NAME
    KEY_NAME=${KEY_NAME:-operator}
    read -p "Enter the LIMONATA_MONIKER for your validator: " LIMONATA_MONIKER
    read -p "Enter the amount to self-stake in LIMO (e.g., 1 for 1 LIMO): " STAKE_LIMO
    STAKE_LIMO="${STAKE_LIMO//,/.}"

    read -p "Enter commission rate (e.g., 0.10 for 10%, default 0.10): " COMMISSION_RATE
    COMMISSION_RATE=${COMMISSION_RATE:-0.10}
    read -p "Enter max commission rate (e.g., 0.20 for 20%, default 0.20): " MAX_COMMISSION_RATE
    MAX_COMMISSION_RATE=${MAX_COMMISSION_RATE:-0.20}
    read -p "Enter max commission change rate (e.g., 0.01 for 1%/day, default 0.01): " MAX_CHANGE_RATE
    MAX_CHANGE_RATE=${MAX_CHANGE_RATE:-0.01}
    read -p "Enter validator website (optional): " WEBSITE
    read -p "Enter validator details (optional): " DETAILS

    # Convert LIMO to aLIMO (1 LIMO = 10^18 aLIMO)
    STAKE=$(echo "$STAKE_LIMO * 10^18" | bc)
    STAKE=${STAKE%%.*}

    PUBKEY=$(limonatad comet show-validator)
    if [ -z "$PUBKEY" ]; then
        echo -e "${RED}Error: could not read validator pubkey. Is the node initialized?${RESET}"
        menu
        return
    fi

    VALIDATOR_JSON=$(mktemp)
    cat > "$VALIDATOR_JSON" <<EOF
{
  "pubkey": $PUBKEY,
  "amount": "${STAKE}aLIMO",
  "moniker": "$LIMONATA_MONIKER",
  "identity": "",
  "website": "$WEBSITE",
  "security": "",
  "details": "$DETAILS",
  "commission-rate": "$COMMISSION_RATE",
  "commission-max-rate": "$MAX_COMMISSION_RATE",
  "commission-max-change-rate": "$MAX_CHANGE_RATE",
  "min-self-delegation": "1"
}
EOF

    echo -e "${YELLOW}validator.json to be submitted:${RESET}"
    cat "$VALIDATOR_JSON"
    read -p $'\n\e[33mSubmit create-validator transaction? (yes/no): \e[0m' confirm
    if [[ "${confirm,,}" != "yes" ]]; then
        rm -f "$VALIDATOR_JSON"
        echo -e "${RED}Cancelled.${RESET}"
        menu
        return
    fi

    limonatad tx staking create-validator "$VALIDATOR_JSON" \
        --from "$KEY_NAME" \
        --chain-id "$LIMONATA_CHAIN_ID" \
        --gas auto --gas-adjustment 1.3 --fees 0aLIMO -y

    rm -f "$VALIDATOR_JSON"
    echo -e "\n${GREEN}Transaction submitted. Send your operator and validator addresses to the Limonata team for stake delegation.${RESET}"
    echo -e "${YELLOW}Press Enter to go back to main menu${RESET}"
    read -r
    menu
}

function query_balance() {
    echo -e "${CYAN}Select an option:${RESET}"
    echo "1. Query balance of a key in your local keyring"
    echo "2. Query balance of another address"
    echo "3. Back"
    read -p "Enter your choice (1, 2, or 3): " choice

    case $choice in
        1)
            read -p "Enter key name (default 'operator'): " keyname
            keyname=${keyname:-operator}
            address=$(limonatad keys show "$keyname" -a 2>/dev/null)
            if [ -z "$address" ]; then
                echo -e "${RED}Key '$keyname' not found in keyring.${RESET}"
                menu
                return
            fi
            ;;
        2)
            read -p "Enter the address to query (limo1.../cosmos1...): " address
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
    limonatad query bank balances "$address"
    echo -e "\n${YELLOW}Note: amounts are in aLIMO (1 LIMO = 10^18 aLIMO).${RESET}"
    echo -e "${YELLOW}Press Enter to go back to main menu...${RESET}"
    read -r
    menu
}

function delegate_tokens() {
    if ! command -v bc &> /dev/null; then
        echo "bc is not installed. Installing bc..."
        sudo apt-get update
        sudo apt-get install -y bc
    fi

    echo "Choose an option to delegate tokens:"
    echo "1. Delegate to self (your own validator)"
    echo "2. Delegate to another validator"
    echo "3. Back"
    read -p "Enter your choice (1/2/3): " CHOICE

    case $CHOICE in
        1)
            VALOPER=$(limonatad keys show operator --bech val -a 2>/dev/null)
            if [ -z "$VALOPER" ]; then
                read -p "Could not derive valoper from key 'operator'. Enter your valoper address: " VALOPER
            fi
            ;;
        2)
            read -p "Enter validator operator address (...valoper1...): " VALOPER
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

    read -p "Enter your key name (default 'operator'): " KEY_NAME
    KEY_NAME=${KEY_NAME:-operator}
    read -p "Enter the amount to delegate in LIMO: " AMOUNT_LIMO
    AMOUNT_LIMO="${AMOUNT_LIMO//,/.}"
    AMOUNT=$(echo "$AMOUNT_LIMO * 10^18" | bc)
    AMOUNT=${AMOUNT%%.*}

    limonatad tx staking delegate "$VALOPER" "${AMOUNT}aLIMO" \
        --from "$KEY_NAME" \
        --chain-id "$LIMONATA_CHAIN_ID" \
        --gas auto --gas-adjustment 1.3 --fees 0aLIMO -y

    echo -e "${YELLOW}Press Enter to go back to main menu${RESET}"
    read -r
    menu
}

function query_validator_status() {
    read -p "Enter validator operator address (...valoper1..., leave empty to derive from key 'operator'): " VALOPER
    if [ -z "$VALOPER" ]; then
        VALOPER=$(limonatad keys show operator --bech val -a 2>/dev/null)
    fi
    if [ -z "$VALOPER" ]; then
        echo -e "${RED}No valoper address available.${RESET}"
        menu
        return
    fi
    limonatad query staking validator "$VALOPER"
    echo -e "\n${YELLOW}Press Enter to go back to main menu${RESET}"
    read -r
    menu
}

function backup_validator_key() {
    if [ -f "$HOME/.limonatad/config/priv_validator_key.json" ]; then
        cp $HOME/.limonatad/config/priv_validator_key.json $HOME/priv_validator_key.json
        echo -e "\n${YELLOW}Your priv_validator_key.json file has been copied to $HOME${RESET}"
        echo -e "${RED}Move it somewhere safe and offline.${RESET}"
    else
        echo -e "${RED}priv_validator_key.json not found. Deploy the node first.${RESET}"
    fi
    menu
}

function restart_limonata() {
    sudo systemctl daemon-reload
    sudo systemctl restart ${LIMONATA_SERVICE_NAME}
    echo -e "${GREEN}${LIMONATA_SERVICE_NAME}.service restarted.${RESET}"
    menu
}

function stop_limonata() {
    sudo systemctl stop ${LIMONATA_SERVICE_NAME}
    echo -e "${YELLOW}${LIMONATA_SERVICE_NAME}.service stopped.${RESET}"
    menu
}

function delete_limonata_node() {
    echo -e "${YELLOW}You are about to delete the Limonata node.${RESET}"
    echo -e "${RED}BACKUP YOUR MNEMONIC AND priv_validator_key.json BEFORE YOU DO THIS.${RESET}"
    if ! prompt_back_or_continue; then
        return
    fi
    sudo systemctl stop ${LIMONATA_SERVICE_NAME} || true
    sudo systemctl disable ${LIMONATA_SERVICE_NAME} || true
    sudo rm -f /etc/systemd/system/${LIMONATA_SERVICE_NAME}.service
    sudo systemctl daemon-reload
    sudo rm -rf $HOME/.limonatad
    sudo rm -f /usr/local/bin/limonatad
    sed -i "/LIMONATA_/d" "$HOME/.bash_profile"
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
    echo " - Reply to prompts with 'yes' or 'no'; press Enter to accept defaults."
    echo " - Run the script as the same user that owns ~/.limonatad to avoid permission issues."
    echo -e "${GREEN}Recommended flow for a new validator:${RESET}"
    echo " - 1a Deploy node -> wait until 1d shows catching_up=false"
    echo " - 2a Create operator key -> fund it via https://faucet.limonata.xyz"
    echo " - 2c Create validator -> send operator + valoper addresses to the Limonata team for delegation"
    echo " - 3d Backup validator key immediately after deploy"
    echo -e "${GREEN}Operations:${RESET}"
    echo " - After deploy/update, use menu 1d (status) and 1e (logs) to verify the node."
    echo " - Run 'source ~/.bash_profile' after exiting to refresh environment variables."
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

    echo -e "Local Node Block Height: ${GREEN}$local_height${RESET}"
    echo -e "\n${YELLOW}Please run the following command to apply the changes after exiting the script:${RESET}"
    echo -e "${GREEN}source ~/.bash_profile${RESET}"
    echo -e "${YELLOW}This ensures the environment variables are set in your current bash session.${RESET}"
    echo -e "${GREEN}Let's Buidl Limonata Together - Grand Valley${RESET}"
    read -p "Choose an option (e.g., 1a or 1 then a): " OPTION

    if [[ $OPTION =~ ^[1-6][a-z]$ ]]; then
        MAIN_OPTION=${OPTION:0:1}
        SUB_OPTION=${OPTION:1:1}
    else
        MAIN_OPTION=$OPTION
        if [[ $MAIN_OPTION =~ ^[1-3]$ ]]; then
            read -p "Choose a sub-option: " SUB_OPTION
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
                *) echo "Invalid sub-option. Please try again." ;;
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
                *) echo "Invalid sub-option. Please try again." ;;
            esac
            ;;
        3)
            case $SUB_OPTION in
                a) restart_limonata ;;
                b) stop_limonata ;;
                c) delete_limonata_node ;;
                d) backup_validator_key ;;
                *) echo "Invalid sub-option. Please try again." ;;
            esac
            ;;
        4) show_endpoints ;;
        5) show_guidelines ;;
        6) exit 0 ;;
        *) echo "Invalid option. Please try again." ;;
    esac
}

# Start menu
menu
