#!/bin/bash

set -euo pipefail

echo -e "\n--- Limonata Binary Update ---"

LOGO="
 __
/__ ._ _. ._   _|   \\  / _. | |  _
\_| | (_| | | (_|    \\/ (_| | | (/_ \\/
                                    /
"
echo "$LOGO"

# shellcheck disable=SC1091
source "$HOME/.bash_profile" 2>/dev/null
LIMONATA_SERVICE_NAME=${LIMONATA_SERVICE_NAME:-limonatad}
LIMONATA_HOME=${LIMONATA_HOME:-$HOME/.limonatad}
LIMONATA_TARGET_VERSION=${LIMONATA_TARGET_VERSION:-limonata-v0.3.6}

if ! [[ "$LIMONATA_SERVICE_NAME" =~ ^[A-Za-z0-9_.@-]+$ ]]; then
    echo "Invalid service name: $LIMONATA_SERVICE_NAME"
    exit 1
fi

resolved_binary=$(readlink -f /usr/local/bin/limonatad 2>/dev/null || true)
if [ -n "$resolved_binary" ] && [[ "$resolved_binary" == "$LIMONATA_HOME/cosmovisor/current/bin/limonatad" ]]; then
    echo "This node is managed by Cosmovisor."
    echo "Current binary: $resolved_binary"
    echo "Reviewed target: $LIMONATA_TARGET_VERSION"
    echo
    current_version=$(limonatad --home "$LIMONATA_HOME" version 2>/dev/null || limonatad version 2>/dev/null || true)
    echo "Current version: ${current_version:-unknown}"

    if grep -Eq '(^|[^0-9])v?0\.3\.6([^0-9]|$)' <<<"$current_version"; then
        echo "Already running the reviewed v0.3.6 target. No update is required."
        exit 0
    fi

    echo "Refusing a direct binary replacement on a Cosmovisor-managed node."
    echo "A future coordinated upgrade must be staged under the exact on-chain upgrade name"
    echo "with reviewed release metadata; /usr/local/bin/limonatad must remain the current symlink."
    exit 2
fi

# Legacy direct-binary installations retain the old manual updater for compatibility.
# New Valley installations do not enter this path; they are Cosmovisor-managed from genesis.
echo "Legacy direct-binary installation detected."
echo "Current version:"
limonatad --home "$LIMONATA_HOME" version 2>/dev/null || limonatad version 2>/dev/null || echo "limonatad not found"

echo
read -r -p "Update this legacy installation to the latest official release? (yes/no): " confirm
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
