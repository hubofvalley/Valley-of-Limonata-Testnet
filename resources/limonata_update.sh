#!/bin/bash

set -e

echo -e "\n--- Limonata Binary Update ---"

LOGO="
 __
/__ ._ _. ._   _|   \  / _. | |  _
\_| | (_| | | (_|    \/ (_| | | (/_ \/
                                    /
"
echo "$LOGO"

source $HOME/.bash_profile 2>/dev/null
LIMONATA_SERVICE_NAME=${LIMONATA_SERVICE_NAME:-limonatad}

echo "Current version:"
limonatad --home "${LIMONATA_HOME:-$HOME/.limonatad}" version 2>/dev/null || limonatad version 2>/dev/null || echo "limonatad not found"

read -p "Update to the latest official release? (yes/no): " confirm
if [[ "${confirm,,}" != "yes" ]]; then
    echo "Update cancelled."
    exit 0
fi

# Stop service
sudo systemctl stop ${LIMONATA_SERVICE_NAME}

# Download and install latest prebuilt binary
cd $HOME
curl -sL https://github.com/Limonata-Blockchain/limonata/releases/latest/download/limonatad-linux-amd64.tar.gz | tar xz
sudo install limonatad /usr/local/bin/
rm -f $HOME/limonatad

echo "New version:"
limonatad --home "${LIMONATA_HOME:-$HOME/.limonatad}" version

# Restart service
sudo systemctl daemon-reload
sudo systemctl restart ${LIMONATA_SERVICE_NAME}

if systemctl is-active --quiet ${LIMONATA_SERVICE_NAME}; then
    echo "Limonata binary updated and service restarted successfully!"
else
    echo "Service failed to start after update. Check logs:"
fi
echo "sudo journalctl -u ${LIMONATA_SERVICE_NAME} -fn 100"
echo "Let's Buidl Limonata Together"
