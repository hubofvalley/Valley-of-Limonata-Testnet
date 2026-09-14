#!/usr/bin/env bash

set -euo pipefail

LIMONATA_HOME=${LIMONATA_HOME:-$HOME/.limonatad}
LIMONATA_BIN=${LIMONATA_BIN:-$HOME/go/bin/limonatad}
LIMONATA_CONFIG=${LIMONATA_CONFIG:-$LIMONATA_HOME/config/config.toml}

readonly REVIEWED_LIMONATA_VERSION="0.3.6"
readonly REVIEWED_LIMONATA_COMMIT="effa377d673fc6f0fb307a78ca54e037e53060f7"
readonly UPSTREAM_FIX_COMMIT="e03a0f992b8934cf92091838abb196516738b04e"

fail_count=0
unknown_count=0
warn_count=0

pass() { printf '[PASS] %s\n' "$*"; }
warn() { warn_count=$((warn_count + 1)); printf '[WARN] %s\n' "$*"; }
fail() { fail_count=$((fail_count + 1)); printf '[FAIL] %s\n' "$*"; }
unknown() { unknown_count=$((unknown_count + 1)); printf '[UNKNOWN] %s\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }

usage() {
    cat <<'USAGE'
Baconvalley Limonata DKG Identity Preflight

Read-only preflight for a Limonata validator's DKG self-identity prerequisite.
It is designed for the reviewed Limonata v0.3.6 release, especially nodes using
a remote signer such as Horcrux.

Limonata's transparent DKG must still resolve the validator's consensus identity
from the configured priv_validator_key_file path even when priv_validator_laddr
points at a remote signer. A validator can otherwise keep signing blocks while
silently contributing no DKG encryption key, dealings, or decryption shares.

For safety, this checker NEVER opens or parses the priv-validator identity file.
It checks only configuration and filesystem metadata. It therefore cannot prove
that the file's address field is correct or that the node is actively
participating in the DKG.

Environment overrides:
  LIMONATA_HOME    Node home (default: $HOME/.limonatad)
  LIMONATA_BIN     Active binary (default: $HOME/go/bin/limonatad)
  LIMONATA_CONFIG  CometBFT config.toml (default: $LIMONATA_HOME/config/config.toml)

Exit codes:
  0  Reviewed rule checked with no verified hard failure (warnings may remain)
  1  Verified remote-signer DKG identity prerequisite failure
  2  Required release/config state could not be established safely
USAGE
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    usage
    exit 0
fi
if [ "$#" -ne 0 ]; then
    usage >&2
    exit 1
fi

version_long_value() {
    local output=$1 key=$2
    awk -F: -v key="$key" '
        function trim(s) {
            sub(/^[[:space:]]+/, "", s)
            sub(/[[:space:]]+$/, "", s)
            return s
        }
        {
            field=trim($1)
            if (field == key) {
                sub(/^[^:]*:[[:space:]]*/, "", $0)
                print trim($0)
                exit
            }
        }
    ' <<<"$output"
}

toml_root_value() {
    local file=$1 key=$2
    awk -v key="$key" '
        function trim(s) {
            sub(/^[[:space:]]+/, "", s)
            sub(/[[:space:]]+$/, "", s)
            return s
        }
        /^[[:space:]]*\[/ { exit }
        {
            line=$0
            if (line ~ "^[[:space:]]*" key "[[:space:]]*=") {
                sub("^[[:space:]]*" key "[[:space:]]*=[[:space:]]*", "", line)
                sub(/[[:space:]]+#.*/, "", line)
                line=trim(line)
                if (line ~ /^\".*\"[[:space:]]*$/) {
                    sub(/^\"/, "", line)
                    sub(/\"[[:space:]]*$/, "", line)
                }
                print line
                exit
            }
        }
    ' "$file"
}

resolve_home_path() {
    local value=$1
    if [[ "$value" = /* ]]; then
        printf '%s\n' "$value"
    else
        printf '%s/%s\n' "${LIMONATA_HOME%/}" "$value"
    fi
}

printf 'Baconvalley Limonata DKG Identity Preflight\n'
printf 'Node home: %s\n' "$LIMONATA_HOME"
printf 'Config: %s\n' "$LIMONATA_CONFIG"
printf 'Binary: %s\n\n' "$LIMONATA_BIN"

reviewed_release=false
if [ ! -x "$LIMONATA_BIN" ]; then
    unknown "Limonata binary is missing or not executable: $LIMONATA_BIN"
else
    version_output=$("$LIMONATA_BIN" version --long 2>/dev/null || true)
    release_version=$(version_long_value "$version_output" version)
    release_commit=$(version_long_value "$version_output" commit)

    if [ -z "$release_version" ] || [ -z "$release_commit" ]; then
        unknown "Could not establish both release version and source commit from 'limonatad version --long'."
    elif [ "${release_version#v}" = "$REVIEWED_LIMONATA_VERSION" ] && [ "$release_commit" = "$REVIEWED_LIMONATA_COMMIT" ]; then
        reviewed_release=true
        pass "Active binary is reviewed Limonata v$REVIEWED_LIMONATA_VERSION commit $REVIEWED_LIMONATA_COMMIT."
    else
        unknown "No DKG identity rule is encoded for Limonata version '$release_version' commit '$release_commit'; refusing to assume current semantics."
    fi
fi

if [ ! -f "$LIMONATA_CONFIG" ]; then
    unknown "CometBFT config is missing: $LIMONATA_CONFIG"
else
    priv_validator_key_file=$(toml_root_value "$LIMONATA_CONFIG" priv_validator_key_file)
    priv_validator_laddr=$(toml_root_value "$LIMONATA_CONFIG" priv_validator_laddr)

    if [ -z "$priv_validator_key_file" ]; then
        priv_validator_key_file="config/priv_validator_key.json"
        info "priv_validator_key_file was not readable from config; mirroring Limonata's default path fallback."
    fi

    identity_path=$(resolve_home_path "$priv_validator_key_file")
    info "Configured DKG identity path: $identity_path"

    if [ "$reviewed_release" = true ]; then
        if [ -n "$priv_validator_laddr" ]; then
            info "Remote signer configuration detected via priv_validator_laddr."
            if [ ! -e "$identity_path" ]; then
                fail "Remote signer is configured but the Limonata DKG identity path does not exist. In reviewed v$REVIEWED_LIMONATA_VERSION, this can leave a validator bonded and signing while silently contributing no DKG key, dealings, or decryption shares."
                info "Limonata upstream fix reference: $UPSTREAM_FIX_COMMIT"
                info "Do not restore signing-key material merely to satisfy this check; obtain current upstream guidance for a safe address-only identity representation."
            elif [ ! -f "$identity_path" ]; then
                fail "Remote signer is configured but the DKG identity path is not a regular file: $identity_path"
            else
                pass "Remote-signer DKG identity path exists as a regular file."
                warn "File contents were intentionally not read. Confirm separately that its address field is the validator's real consensus address; path existence alone does not prove DKG participation."
            fi
        else
            info "No remote signer listener is configured in config.toml."
            if [ -f "$identity_path" ]; then
                pass "Local priv-validator identity path exists."
            else
                warn "Local priv-validator identity path is absent. This can be normal for a non-validator full node, but DKG validator identity cannot be established from this preflight."
            fi
        fi
    fi
fi

printf '\nSummary: FAIL=%d WARN=%d UNKNOWN=%d\n' "$fail_count" "$warn_count" "$unknown_count"

if (( fail_count > 0 )); then
    exit 1
fi
if (( unknown_count > 0 )); then
    exit 2
fi
exit 0
