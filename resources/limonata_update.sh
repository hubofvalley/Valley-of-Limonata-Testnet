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
LIMONATA_BIN="$HOME/go/bin/limonatad"
LEGACY_LIMONATA_BIN="/usr/local/bin/limonatad"

if ! [[ "$LIMONATA_SERVICE_NAME" =~ ^[A-Za-z0-9_.@-]+$ ]]; then
    echo "Invalid service name: $LIMONATA_SERVICE_NAME"
    exit 1
fi

resolved_binary=$(readlink -f "$LIMONATA_BIN" 2>/dev/null || true)
if [ -n "$resolved_binary" ] && [[ "$resolved_binary" == "$LIMONATA_HOME/cosmovisor/current/bin/limonatad" ]]; then
    echo "This node is managed by Cosmovisor."
    echo "CLI binary: $LIMONATA_BIN"
    echo "Current binary: $resolved_binary"
    echo "Reviewed target: $LIMONATA_TARGET_VERSION"
    echo
    current_version=$("$LIMONATA_BIN" --home "$LIMONATA_HOME" version 2>/dev/null || "$LIMONATA_BIN" version 2>/dev/null || true)
    echo "Current version: ${current_version:-unknown}"

    if grep -Eq '(^|[^0-9])v?0\.3\.6([^0-9]|$)' <<<"$current_version"; then
        echo "Already running the reviewed v0.3.6 target. No update is required."
        exit 0
    fi

    echo "Refusing a direct binary replacement on a Cosmovisor-managed node."
    echo "A future coordinated upgrade must be staged under the exact on-chain upgrade name"
    echo "with reviewed release metadata; ~/go/bin/limonatad must remain the current symlink."
    exit 2
fi

# Legacy direct-binary installations retain the old manual updater for compatibility.
# New Valley installations do not enter this path; they are Cosmovisor-managed from genesis.
if [ -x "$LIMONATA_BIN" ] && [ ! -L "$LIMONATA_BIN" ]; then
    legacy_binary="$LIMONATA_BIN"
elif [ -x "$LEGACY_LIMONATA_BIN" ] && [ ! -L "$LEGACY_LIMONATA_BIN" ]; then
    legacy_binary="$LEGACY_LIMONATA_BIN"
else
    echo "No supported Limonata binary installation was detected."
    exit 1
fi

echo "Legacy direct-binary installation detected at: $legacy_binary"
echo "Current version:"
"$legacy_binary" --home "$LIMONATA_HOME" version 2>/dev/null || "$legacy_binary" version 2>/dev/null || echo "version unavailable"

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

cp "$legacy_binary" "$BACKUP_BINARY"
sudo systemctl stop "$LIMONATA_SERVICE_NAME"

if [[ "$legacy_binary" == "$HOME"/* ]]; then
    install -m 0755 "$UPDATE_TMP/limonatad" "$legacy_binary"
else
    sudo install -m 0755 "$UPDATE_TMP/limonatad" "$legacy_binary"
fi

echo "Installed version:"
"$legacy_binary" --home "$LIMONATA_HOME" version

sudo systemctl daemon-reload
if sudo systemctl restart "$LIMONATA_SERVICE_NAME" && systemctl is-active --quiet "$LIMONATA_SERVICE_NAME"; then
    echo "Limonata binary updated and service restarted successfully!"
else
    echo "Service failed to start after the update."
    echo "Restoring the previous binary..."
    if [[ "$legacy_binary" == "$HOME"/* ]]; then
        install -m 0755 "$BACKUP_BINARY" "$legacy_binary"
    else
        sudo install -m 0755 "$BACKUP_BINARY" "$legacy_binary"
    fi
    sudo systemctl restart "$LIMONATA_SERVICE_NAME" || true
    echo "Check logs with: sudo journalctl -u ${LIMONATA_SERVICE_NAME} -fn 100"
    exit 1
fi

echo "sudo journalctl -u ${LIMONATA_SERVICE_NAME} -fn 100"
echo "Let's Buidl Limonata Together"
