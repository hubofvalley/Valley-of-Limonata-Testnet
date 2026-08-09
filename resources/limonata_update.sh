#!/bin/bash

set -euo pipefail

echo -e "\n--- Limonata Binary Update ---"

LOGO="
 __
/__ ._ _. ._   _|   \  / _. | |  _
\_| | (_| | | (_|    \/ (_| | | (/_ \/
                                    /
"
echo "$LOGO"

# shellcheck disable=SC1091
source "$HOME/.bash_profile" 2>/dev/null
LIMONATA_SERVICE_NAME=${LIMONATA_SERVICE_NAME:-limonatad}
LIMONATA_HOME=${LIMONATA_HOME:-$HOME/.limonatad}

if ! [[ "$LIMONATA_SERVICE_NAME" =~ ^[A-Za-z0-9_.@-]+$ ]]; then
    echo "Invalid service name: $LIMONATA_SERVICE_NAME"
    exit 1
fi

echo "Current version:"
limonatad --home "$LIMONATA_HOME" version 2>/dev/null || limonatad version 2>/dev/null || echo "limonatad not found"

read -r -p "Update to the latest official release? (yes/no): " confirm
if [[ "${confirm,,}" != "yes" ]]; then
    echo "Update cancelled."
    exit 0
fi

UPDATE_TMP=$(mktemp -d)
BACKUP_BINARY="$UPDATE_TMP/limonatad.previous"
cleanup() {
    rm -rf "$UPDATE_TMP"
}
trap cleanup EXIT

echo "Downloading and verifying the latest official release..."
curl -fsSL \
    https://github.com/Limonata-Blockchain/limonata/releases/latest/download/limonatad-linux-amd64.tar.gz \
    -o "$UPDATE_TMP/limonatad-linux-amd64.tar.gz"
curl -fsSL \
    https://github.com/Limonata-Blockchain/limonata/releases/latest/download/SHA256SUMS.txt \
    -o "$UPDATE_TMP/SHA256SUMS.txt"
(
    cd "$UPDATE_TMP"
    grep '  limonatad-linux-amd64.tar.gz$' SHA256SUMS.txt | sha256sum -c -
    tar xzf limonatad-linux-amd64.tar.gz
)

if [ ! -x "$UPDATE_TMP/limonatad" ]; then
    echo "Verified archive does not contain an executable limonatad binary."
    exit 1
fi

echo "Target version:"
"$UPDATE_TMP/limonatad" version

if [ -x /usr/local/bin/limonatad ]; then
    cp /usr/local/bin/limonatad "$BACKUP_BINARY"
fi

sudo systemctl stop "$LIMONATA_SERVICE_NAME"
sudo install "$UPDATE_TMP/limonatad" /usr/local/bin/limonatad

echo "Installed version:"
limonatad --home "$LIMONATA_HOME" version

sudo systemctl daemon-reload
if sudo systemctl restart "$LIMONATA_SERVICE_NAME" && systemctl is-active --quiet "$LIMONATA_SERVICE_NAME"; then
    echo "Limonata binary updated and service restarted successfully!"
else
    echo "Service failed to start after the update."
    if [ -x "$BACKUP_BINARY" ]; then
        echo "Restoring the previous binary..."
        sudo install "$BACKUP_BINARY" /usr/local/bin/limonatad
        sudo systemctl restart "$LIMONATA_SERVICE_NAME" || true
    fi
    echo "Check logs with: sudo journalctl -u ${LIMONATA_SERVICE_NAME} -fn 100"
    exit 1
fi

echo "sudo journalctl -u ${LIMONATA_SERVICE_NAME} -fn 100"
echo "Let's Buidl Limonata Together"
