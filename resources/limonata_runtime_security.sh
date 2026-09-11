#!/usr/bin/env bash

set -euo pipefail

LIMONATA_HOME=${LIMONATA_HOME:-$HOME/.limonatad}
LIMONATA_BIN=${LIMONATA_BIN:-$HOME/go/bin/limonatad}
GO_BIN=${GO_BIN:-go}

readonly GRPC_ADVISORY_ID="CVE-2026-84304"
readonly GRPC_ADVISORY_URL="https://github.com/grpc/grpc-go/security/advisories/GHSA-vp52-pcj8-j9qc"
readonly GRPC_FIRST_FIXED_VERSION="1.83.1"
readonly JSONRPC_UPSTREAM_PR_URL="https://github.com/Limonata-Blockchain/limonata/pull/13"

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
Baconvalley Limonata Runtime Security Preflight

Read-only preflight for the active Limonata binary and local app.toml. It checks
embedded gRPC-Go build metadata against the published CVE-2026-84304 boundary,
then correlates an affected gRPC server with the configured listener address. It
also reports public EVM JSON-RPC/WS signing-surface configuration that deserves
keyring review under Limonata upstream PR #13.

This command never changes node data, configuration, services, keys, firewall
rules, or chain state.

Environment overrides:
  LIMONATA_HOME  Node home (default: $HOME/.limonatad)
  LIMONATA_BIN   Active binary (default: $HOME/go/bin/limonatad)
  GO_BIN         Go command used for 'go version -m' (default: go)

Exit codes:
  0  No hard failure or unknown required check (warnings may be present)
  1  Known affected gRPC server is configured on a non-loopback listener
  2  No hard failure, but a required binary/config check is unknown
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

printf 'Baconvalley Limonata Runtime Security Preflight\n'
printf 'Node home: %s\n' "$LIMONATA_HOME"
printf 'Binary: %s\n\n' "$LIMONATA_BIN"

toml_value() {
    local file=$1 section=$2 key=$3
    awk -v section="$section" -v key="$key" '
        function trim(s) {
            sub(/^[[:space:]]+/, "", s)
            sub(/[[:space:]]+$/, "", s)
            return s
        }
        $0 ~ "^[[:space:]]*\\[" section "\\][[:space:]]*$" {
            in_section=1
            next
        }
        in_section && $0 ~ "^[[:space:]]*\\[" {
            in_section=0
        }
        in_section {
            line=$0
            if (line ~ "^[[:space:]]*" key "[[:space:]]*=") {
                sub("^[[:space:]]*" key "[[:space:]]*=[[:space:]]*", "", line)
                line=trim(line)
                if (line ~ /^\".*\"[[:space:]]*$/) {
                    sub(/^\"/, "", line)
                    sub(/\"[[:space:]]*$/, "", line)
                } else {
                    sub(/[[:space:]]+#.*/, "", line)
                    line=trim(line)
                }
                print line
                exit
            }
        }
    ' "$file"
}

is_loopback_listener() {
    local address=${1#tcp://}
    case "$address" in
        localhost|localhost:*|127.*|127.*:*|'[::1]'|'[::1]':*|::1|unix:*|unix://*) return 0 ;;
        *) return 1 ;;
    esac
}

semver_le() {
    local left=${1#v} right=${2#v}
    local lmajor lminor lpatch rmajor rminor rpatch
    if ! [[ "$left" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        return 2
    fi
    lmajor=${BASH_REMATCH[1]}; lminor=${BASH_REMATCH[2]}; lpatch=${BASH_REMATCH[3]}
    if ! [[ "$right" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        return 2
    fi
    rmajor=${BASH_REMATCH[1]}; rminor=${BASH_REMATCH[2]}; rpatch=${BASH_REMATCH[3]}

    if (( lmajor != rmajor )); then (( lmajor < rmajor )); return; fi
    if (( lminor != rminor )); then (( lminor < rminor )); return; fi
    (( lpatch <= rpatch ))
}

api_has_signing_namespace() {
    local api=$1 item
    IFS=',' read -r -a items <<<"$api"
    for item in "${items[@]}"; do
        item=${item//[[:space:]]/}
        case "$item" in
            eth|personal) return 0 ;;
        esac
    done
    return 1
}

if [ ! -x "$LIMONATA_BIN" ]; then
    unknown "Limonata binary is missing or not executable: $LIMONATA_BIN"
    grpc_version=""
else
    build_info=$("$GO_BIN" version -m "$LIMONATA_BIN" 2>/dev/null || true)
    grpc_version=$(awk '$1 == "dep" && $2 == "google.golang.org/grpc" { print $3; exit }' <<<"$build_info")
    if [ -z "$build_info" ]; then
        unknown "Could not read Go build metadata from the active binary."
    elif [ -z "$grpc_version" ]; then
        unknown "Embedded build metadata did not expose google.golang.org/grpc."
    else
        info "Embedded google.golang.org/grpc version: $grpc_version"
    fi
fi

app_toml="$LIMONATA_HOME/config/app.toml"
grpc_enable=""
grpc_address=""
jsonrpc_enable=""
jsonrpc_address=""
jsonrpc_ws_address=""
jsonrpc_api=""

if [ ! -f "$app_toml" ]; then
    unknown "app.toml is missing: $app_toml"
else
    grpc_enable=$(toml_value "$app_toml" grpc enable)
    grpc_address=$(toml_value "$app_toml" grpc address)
    jsonrpc_enable=$(toml_value "$app_toml" json-rpc enable)
    jsonrpc_address=$(toml_value "$app_toml" json-rpc address)
    jsonrpc_ws_address=$(toml_value "$app_toml" json-rpc ws-address)
    jsonrpc_api=$(toml_value "$app_toml" json-rpc api)
fi

if [ -n "$grpc_version" ]; then
    normalized_grpc_version=${grpc_version#v}
    set +e
    semver_le "$normalized_grpc_version" "1.83.0"
    semver_status=$?
    set -e
    case "$semver_status" in
        0)
            warn "google.golang.org/grpc $grpc_version is within the affected range for $GRPC_ADVISORY_ID (fixed in v$GRPC_FIRST_FIXED_VERSION)."
            case "$grpc_enable" in
                false)
                    pass "gRPC server is disabled in app.toml; this listener does not expose the affected server path."
                    ;;
                true)
                    if [ -z "$grpc_address" ]; then
                        unknown "gRPC is enabled but its configured address could not be read."
                    elif is_loopback_listener "$grpc_address"; then
                        pass "gRPC is configured loopback-only at $grpc_address."
                    else
                        fail "Affected gRPC-Go server is configured on non-loopback listener $grpc_address. Keep it private or use a coordinated Limonata release carrying the upstream fix."
                    fi
                    ;;
                *)
                    unknown "Could not establish whether the gRPC server is enabled in app.toml."
                    ;;
            esac
            info "Advisory: $GRPC_ADVISORY_URL"
            ;;
        1)
            pass "google.golang.org/grpc $grpc_version is newer than the published $GRPC_ADVISORY_ID affected range."
            ;;
        *)
            unknown "Could not compare embedded gRPC-Go version '$grpc_version' with the advisory boundary."
            ;;
    esac
fi

case "$jsonrpc_enable" in
    false)
        pass "EVM JSON-RPC is disabled in app.toml."
        ;;
    true)
        if [ -z "$jsonrpc_address" ] || [ -z "$jsonrpc_ws_address" ]; then
            unknown "EVM JSON-RPC is enabled but HTTP/WS listener configuration is incomplete."
        else
            public_jsonrpc=false
            if ! is_loopback_listener "$jsonrpc_address"; then public_jsonrpc=true; fi
            if ! is_loopback_listener "$jsonrpc_ws_address"; then public_jsonrpc=true; fi
            if [ "$public_jsonrpc" = false ]; then
                pass "EVM JSON-RPC HTTP/WS listeners are configured loopback-only."
            elif api_has_signing_namespace "$jsonrpc_api"; then
                warn "EVM JSON-RPC exposes a signing-capable namespace on a non-loopback listener. Limonata upstream PR #13 documents a signing risk when this is combined with a non-empty keyring; this checker intentionally does not inspect keys."
                info "Upstream reference: $JSONRPC_UPSTREAM_PR_URL"
            else
                warn "EVM JSON-RPC is configured on a non-loopback listener. No eth/personal signing namespace was detected in the parsed API list."
            fi
        fi
        ;;
    *)
        if [ -f "$app_toml" ]; then
            unknown "Could not establish whether EVM JSON-RPC is enabled in app.toml."
        fi
        ;;
esac

printf '\nSummary: %d fail, %d unknown, %d warning(s).\n' "$fail_count" "$unknown_count" "$warn_count"
if (( fail_count > 0 )); then
    exit 1
fi
if (( unknown_count > 0 )); then
    exit 2
fi
exit 0
