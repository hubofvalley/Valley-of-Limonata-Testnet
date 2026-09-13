#!/usr/bin/env bash

set -euo pipefail

LIMONATA_HOME=${LIMONATA_HOME:-$HOME/.limonatad}
LIMONATA_BIN=${LIMONATA_BIN:-$HOME/go/bin/limonatad}
GO_BIN=${GO_BIN:-go}
CURL_BIN=${CURL_BIN:-curl}
JQ_BIN=${JQ_BIN:-jq}
LIMONATA_REST=${LIMONATA_REST:-https://rest.limonata.xyz}
LIMONATA_REST_TIMEOUT=${LIMONATA_REST_TIMEOUT:-10}

readonly GRPC_ADVISORY_ID="CVE-2026-84304"
readonly GRPC_ADVISORY_URL="https://github.com/grpc/grpc-go/security/advisories/GHSA-vp52-pcj8-j9qc"
readonly GRPC_FIRST_FIXED_VERSION="1.83.1"
readonly STATE_DB_ADVISORY_ID="GHSA-367m-g444-9mg3"
readonly STATE_DB_ADVISORY_URL="https://github.com/cosmos/evm/security/advisories/GHSA-367m-g444-9mg3"
readonly REVIEWED_LIMONATA_VERSION="0.3.6"
readonly REVIEWED_LIMONATA_COMMIT="effa377d673fc6f0fb307a78ca54e037e53060f7"
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
an exact reviewed Limonata release/commit against a published critical Cosmos EVM
StateDB advisory, checks embedded gRPC-Go build metadata against the published
CVE-2026-84304 boundary, and correlates listener-related findings with local
configuration. It also reports public EVM JSON-RPC/WS signing-surface
configuration that deserves keyring review under Limonata upstream PR #13.

This command never changes node data, configuration, services, keys, firewall
rules, or chain state.

Environment overrides:
  LIMONATA_HOME  Node home (default: $HOME/.limonatad)
  LIMONATA_BIN   Active binary (default: $HOME/go/bin/limonatad)
  GO_BIN         Go command used for 'go version -m' (default: go)
  CURL_BIN       curl command used for read-only live queries (default: curl)
  JQ_BIN         jq command used for JSON parsing (default: jq)
  LIMONATA_REST  Public REST endpoint used for live-chain correlation
                 (default: https://rest.limonata.xyz)
  LIMONATA_REST_TIMEOUT
                 Per-request timeout in seconds (default: 10)

Exit codes:
  0  No hard failure or unknown required check (warnings may be present)
  1  At least one verified hard security finding is present
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

is_loopback_listener() {
    local address=${1#tcp://} host octet

    case "$address" in
        unix:*|unix://*) return 0 ;;
        \[*\]:*)
            host=${address%%]*}
            host=${host#\[}
            ;;
        *:*) host=${address%:*} ;;
        *) host=$address ;;
    esac

    case "$host" in
        localhost|::1) return 0 ;;
    esac

    if [[ "$host" =~ ^127\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
        for octet in "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"; do
            (( octet <= 255 )) || return 1
        done
        return 0
    fi
    return 1
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

grpc_version=""
release_version=""
release_commit=""
state_db_exact_match=false
if [ ! -x "$LIMONATA_BIN" ]; then
    unknown "Limonata binary is missing or not executable: $LIMONATA_BIN"
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

    release_output=$("$LIMONATA_BIN" version --long 2>/dev/null || "$LIMONATA_BIN" version 2>/dev/null || true)
    release_version=$(version_long_value "$release_output" version)
    release_commit=$(version_long_value "$release_output" commit)
    if [ -z "$release_version" ]; then
        unknown "Could not read the Limonata release version from 'version --long'."
    else
        info "Limonata release version: $release_version"
    fi
fi

if [ -n "$release_version" ]; then
    normalized_release_version=${release_version#v}
    if [ "$normalized_release_version" = "$REVIEWED_LIMONATA_VERSION" ]; then
        if [ -z "$release_commit" ]; then
            unknown "Limonata v$REVIEWED_LIMONATA_VERSION is active but its source commit could not be established; refusing to guess $STATE_DB_ADVISORY_ID applicability."
        elif [ "$release_commit" = "$REVIEWED_LIMONATA_COMMIT" ]; then
            state_db_exact_match=true
            fail "Active Limonata v$REVIEWED_LIMONATA_VERSION commit $REVIEWED_LIMONATA_COMMIT matches the reviewed source state covered by critical $STATE_DB_ADVISORY_ID (non-atomic StateDB commit). A coordinated Limonata release carrying the upstream atomic-commit fix is required before this preflight can report security-ready."
            info "This is a source-equivalence finding for the exact reviewed commit; it does not claim current live exploitability."
            info "Advisory: $STATE_DB_ADVISORY_URL"
        else
            unknown "Limonata v$REVIEWED_LIMONATA_VERSION reports unexpected commit $release_commit; refusing to apply the reviewed $STATE_DB_ADVISORY_ID verdict to different source."
        fi
    else
        info "No source-level $STATE_DB_ADVISORY_ID verdict is encoded for Limonata $release_version; only the exact reviewed v$REVIEWED_LIMONATA_VERSION commit is classified by this check."
    fi
fi

rest_get() {
    local path=$1
    "$CURL_BIN" -fsS --max-time "$LIMONATA_REST_TIMEOUT" "${LIMONATA_REST%/}${path}"
}

if [ "$state_db_exact_match" = true ]; then
    live_state_complete=true
    live_chain=""
    live_app_version=""
    erc20_enabled=""
    permissionless_registration=""
    enabled_ibc_pairs=""
    open_transfer_channels=""

    if node_info_json=$(rest_get '/cosmos/base/tendermint/v1beta1/node_info' 2>/dev/null); then
        live_chain=$("$JQ_BIN" -r '.default_node_info.network // empty' <<<"$node_info_json" 2>/dev/null || true)
        live_app_version=$("$JQ_BIN" -r '.application_version.version // empty' <<<"$node_info_json" 2>/dev/null || true)
        if [ "$live_chain" != "limonata_10777-1" ]; then
            unknown "Live REST endpoint did not prove the expected Limonata chain ID; refusing to use it for $STATE_DB_ADVISORY_ID exposure correlation."
            live_state_complete=false
        elif [ "${live_app_version#v}" != "$REVIEWED_LIMONATA_VERSION" ]; then
            unknown "Live REST endpoint reports application version '${live_app_version:-unknown}', not reviewed v$REVIEWED_LIMONATA_VERSION; refusing to mix release assumptions."
            live_state_complete=false
        else
            pass "Live REST endpoint reports expected chain limonata_10777-1 and application v$REVIEWED_LIMONATA_VERSION."
        fi
    else
        unknown "Could not query live Limonata node info from $LIMONATA_REST."
        live_state_complete=false
    fi

    if erc20_params_json=$(rest_get '/cosmos/evm/erc20/v1/params' 2>/dev/null); then
        erc20_enabled=$("$JQ_BIN" -r 'if (.params | type) == "object" and (.params | has("enable_erc20")) then .params.enable_erc20 else empty end' <<<"$erc20_params_json" 2>/dev/null || true)
        permissionless_registration=$("$JQ_BIN" -r 'if (.params | type) == "object" and (.params | has("permissionless_registration")) then .params.permissionless_registration else empty end' <<<"$erc20_params_json" 2>/dev/null || true)
        if [[ "$erc20_enabled" != "true" && "$erc20_enabled" != "false" ]] || [[ "$permissionless_registration" != "true" && "$permissionless_registration" != "false" ]]; then
            unknown "Live x/erc20 params response is missing expected boolean fields."
            live_state_complete=false
        fi
    else
        unknown "Could not query live x/erc20 params from $LIMONATA_REST."
        live_state_complete=false
    fi

    if token_pairs_json=$(rest_get '/cosmos/evm/erc20/v1/token_pairs?pagination.limit=200' 2>/dev/null); then
        enabled_ibc_pairs=$("$JQ_BIN" -r '[.token_pairs[]? | select(.enabled == true and ((.denom | type) == "string") and (.denom | startswith("ibc/")))] | length' <<<"$token_pairs_json" 2>/dev/null || true)
        if ! [[ "$enabled_ibc_pairs" =~ ^[0-9]+$ ]]; then
            unknown "Live x/erc20 token-pair response could not be parsed safely."
            live_state_complete=false
        fi
    else
        unknown "Could not query live x/erc20 token pairs from $LIMONATA_REST."
        live_state_complete=false
    fi

    if channels_json=$(rest_get '/ibc/core/channel/v1/channels?pagination.limit=200' 2>/dev/null); then
        open_transfer_channels=$("$JQ_BIN" -r '[.channels[]? | select(.state == "STATE_OPEN" and .port_id == "transfer")] | length' <<<"$channels_json" 2>/dev/null || true)
        if ! [[ "$open_transfer_channels" =~ ^[0-9]+$ ]]; then
            unknown "Live IBC channel response could not be parsed safely."
            live_state_complete=false
        fi
    else
        unknown "Could not query live IBC channels from $LIMONATA_REST."
        live_state_complete=false
    fi

    if [ "$live_state_complete" = true ]; then
        info "Live x/erc20: enabled=$erc20_enabled permissionless_registration=$permissionless_registration enabled_ibc_token_pairs=$enabled_ibc_pairs."
        info "Live IBC: open transfer channels=$open_transfer_channels."
        if [ "$erc20_enabled" = true ] && [ "$permissionless_registration" = true ] && (( open_transfer_channels > 0 )); then
            fail "The exact affected v$REVIEWED_LIMONATA_VERSION source is active locally and the live Limonata chain exposes the observable $STATE_DB_ADVISORY_ID preconditions: x/erc20 is enabled, permissionless ERC20 registration is enabled, and at least one ICS20 transfer channel is open. Treat the advisory as operationally urgent until a coordinated fixed release is available."
            info "This check correlates published advisory preconditions with read-only chain state; it does not reproduce the exploit or claim that exploitation has occurred."
        else
            info "The live chain did not expose every observable $STATE_DB_ADVISORY_ID precondition checked by this tool; the exact-source critical finding still applies until a coordinated fixed release is available."
        fi
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
