#!/usr/bin/env bash

set -euo pipefail

LIMONATA_HOME=${LIMONATA_HOME:-$HOME/.limonatad}
LIMONATA_SERVICE_NAME=${LIMONATA_SERVICE_NAME:-limonatad}
LIMONATA_BIN=${LIMONATA_BIN:-$HOME/go/bin/limonatad}
LIMONATA_EXPECTED_CHAIN_ID=${LIMONATA_EXPECTED_CHAIN_ID:-}
SYSTEMCTL_BIN=${SYSTEMCTL_BIN:-systemctl}
CURL_BIN=${CURL_BIN:-curl}

fail_count=0
unknown_count=0
warn_count=0

pass() { printf '[PASS] %s\n' "$*"; }
warn() { warn_count=$((warn_count + 1)); printf '[WARN] %s\n' "$*"; }
fail() { fail_count=$((fail_count + 1)); printf '[FAIL] %s\n' "$*"; }
unknown() { unknown_count=$((unknown_count + 1)); printf '[UNKNOWN] %s\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }

usage() {
    cat <<'EOF'
Baconvalley Limonata Upgrade Readiness

Read-only preflight for a Valley-managed Limonata node. It inspects the
effective Cosmovisor service environment, local node status, current on-chain
upgrade plan, and local upgrade-binary staging. It never changes node data,
configuration, services, keys, or chain state.

Environment overrides:
  LIMONATA_HOME               Node home (default: $HOME/.limonatad)
  LIMONATA_SERVICE_NAME       systemd service name (default: limonatad)
  LIMONATA_BIN                Operator-facing binary (default: $HOME/go/bin/limonatad)
  LIMONATA_EXPECTED_CHAIN_ID  Optional expected chain ID override
  SYSTEMCTL_BIN               systemctl-compatible reader for tests
  CURL_BIN                    curl-compatible reader for tests

Exit codes:
  0  No hard failures or unknown checks (warnings may be present)
  1  One or more hard readiness failures
  2  No hard failure, but at least one required check is unknown
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    usage
    exit 0
fi

if [ "$#" -ne 0 ]; then
    usage >&2
    exit 1
fi

if ! [[ "$LIMONATA_SERVICE_NAME" =~ ^[A-Za-z0-9_.@-]+$ ]]; then
    printf '[FAIL] Invalid service name: %s\n' "$LIMONATA_SERVICE_NAME" >&2
    exit 1
fi

printf 'Baconvalley Limonata Upgrade Readiness\n'
printf 'Node home: %s\n\n' "$LIMONATA_HOME"

service_environment=""
if service_environment=$(
    "$SYSTEMCTL_BIN" show "${LIMONATA_SERVICE_NAME}.service" --property=Environment --value 2>/dev/null
); then
    if [ -n "$service_environment" ]; then
        pass "Loaded effective environment for ${LIMONATA_SERVICE_NAME}.service."
    else
        unknown "The service environment is empty; Cosmovisor policy cannot be verified."
    fi
else
    unknown "Could not read ${LIMONATA_SERVICE_NAME}.service; Cosmovisor policy cannot be verified."
fi

service_env_value() {
    local key=$1 token value=""
    for token in $service_environment; do
        token=${token#\"}
        token=${token%\"}
        case "$token" in
            "$key="*) value=${token#*=} ;;
        esac
    done
    printf '%s' "$value"
}

if [ -n "$service_environment" ]; then
    daemon_name=$(service_env_value DAEMON_NAME)
    daemon_home=$(service_env_value DAEMON_HOME)
    allow_download=$(service_env_value DAEMON_ALLOW_DOWNLOAD_BINARIES)
    checksum_required=$(service_env_value DAEMON_DOWNLOAD_MUST_HAVE_CHECKSUM)
    skip_backup=$(service_env_value UNSAFE_SKIP_BACKUP)
    backup_dir=$(service_env_value DAEMON_DATA_BACKUP_DIR)

    if [ "$daemon_name" = "limonatad" ]; then
        pass "Cosmovisor daemon name is limonatad."
    elif [ -n "$daemon_name" ]; then
        fail "Cosmovisor daemon name is '$daemon_name', expected limonatad."
    else
        unknown "DAEMON_NAME is not explicit in the service environment."
    fi

    if [ "$daemon_home" = "$LIMONATA_HOME" ]; then
        pass "DAEMON_HOME matches the inspected Limonata home."
    elif [ -n "$daemon_home" ]; then
        fail "DAEMON_HOME points to '$daemon_home', not '$LIMONATA_HOME'."
    else
        unknown "DAEMON_HOME is not explicit in the service environment."
    fi

    case "$allow_download" in
        false)
            pass "Cosmovisor binary auto-download is disabled."
            ;;
        true)
            fail "Cosmovisor binary auto-download is enabled on a validator-oriented Valley service."
            ;;
        "")
            warn "DAEMON_ALLOW_DOWNLOAD_BINARIES is unset; Cosmovisor defaults to false, but the Valley policy is not explicit."
            ;;
        *)
            fail "DAEMON_ALLOW_DOWNLOAD_BINARIES has unexpected value '$allow_download'."
            ;;
    esac

    case "$checksum_required" in
        true)
            pass "Cosmovisor download checksum enforcement is enabled."
            ;;
        false)
            if [ "$allow_download" = "true" ]; then
                fail "Binary auto-download is enabled without mandatory checksums."
            else
                warn "DAEMON_DOWNLOAD_MUST_HAVE_CHECKSUM is false; downloads are currently disabled, but the defense-in-depth gate is not active."
            fi
            ;;
        "")
            if [ "$allow_download" = "true" ]; then
                fail "Binary auto-download is enabled while checksum enforcement is unset."
            else
                warn "DAEMON_DOWNLOAD_MUST_HAVE_CHECKSUM is unset; Cosmovisor defaults to false."
            fi
            ;;
        *)
            fail "DAEMON_DOWNLOAD_MUST_HAVE_CHECKSUM has unexpected value '$checksum_required'."
            ;;
    esac

    case "$skip_backup" in
        true)
            warn "Cosmovisor automatic data backup is disabled (UNSAFE_SKIP_BACKUP=true); rollback depends on a separate verified recovery path."
            ;;
        false|"")
            pass "Cosmovisor automatic data backup is enabled by policy/default."
            ;;
        *)
            fail "UNSAFE_SKIP_BACKUP has unexpected value '$skip_backup'."
            ;;
    esac

    if [ "$skip_backup" != "true" ]; then
        if [ -z "$backup_dir" ]; then
            backup_dir=$LIMONATA_HOME
            info "DAEMON_DATA_BACKUP_DIR is unset; Cosmovisor will use DAEMON_HOME."
        fi

        backup_probe=$backup_dir
        while [ ! -e "$backup_probe" ] && [ "$backup_probe" != "/" ]; do
            backup_probe=$(dirname "$backup_probe")
        done

        if [ -d "$backup_probe" ] && [ -d "$LIMONATA_HOME/data" ]; then
            data_kib=$(du -sk "$LIMONATA_HOME/data" 2>/dev/null | awk '{print $1}' || true)
            free_kib=$(df -Pk "$backup_probe" 2>/dev/null | awk 'NR==2 {print $4}' || true)
            if [[ "$data_kib" =~ ^[0-9]+$ ]] && [[ "$free_kib" =~ ^[0-9]+$ ]]; then
                info "Current data size: ${data_kib} KiB; free space at backup destination filesystem: ${free_kib} KiB."
                if [ "$free_kib" -lt "$data_kib" ]; then
                    fail "Free space is smaller than the current data directory; a full Cosmovisor backup cannot fit."
                else
                    pass "Free space is at least the current data-directory size."
                fi
            else
                unknown "Could not measure data size and backup filesystem free space."
            fi
        elif [ ! -d "$LIMONATA_HOME/data" ]; then
            unknown "Limonata data directory is missing; backup headroom cannot be evaluated."
        else
            unknown "No existing parent for backup destination '$backup_dir'; backup headroom cannot be evaluated."
        fi
    fi
fi

config_file="$LIMONATA_HOME/config/config.toml"
rpc_port=""
if [ -f "$config_file" ]; then
    rpc_port=$(awk '
        /^\[rpc\]/ { in_rpc=1; next }
        /^\[/ { in_rpc=0 }
        in_rpc && /^[[:space:]]*laddr[[:space:]]*=/ {
            line=$0
            sub(/^[^=]*=[[:space:]]*"tcp:\/\//, "", line)
            sub(/".*/, "", line)
            n=split(line, parts, ":")
            if (n >= 2) print parts[n]
            exit
        }
    ' "$config_file")
fi

if ! [[ "$rpc_port" =~ ^[0-9]+$ ]] || [ "$rpc_port" -lt 1 ] || [ "$rpc_port" -gt 65535 ]; then
    unknown "Could not derive the local CometBFT RPC port from config.toml."
    rpc_port=""
fi

genesis_chain_id=""
if [ -f "$LIMONATA_HOME/config/genesis.json" ]; then
    genesis_chain_id=$(jq -r '.chain_id // empty' "$LIMONATA_HOME/config/genesis.json" 2>/dev/null || true)
fi
expected_chain_id=${LIMONATA_EXPECTED_CHAIN_ID:-$genesis_chain_id}
if [ -z "$expected_chain_id" ]; then
    unknown "Could not derive an expected chain ID from genesis.json."
fi

node_height=""
node_chain_id=""
catching_up=""
if [ -n "$rpc_port" ]; then
    status_payload=$("$CURL_BIN" -fsS --max-time 8 "http://127.0.0.1:${rpc_port}/status" 2>/dev/null || true)
    if jq -e '.result.node_info.network and .result.sync_info.latest_block_height' >/dev/null 2>&1 <<<"$status_payload"; then
        node_chain_id=$(jq -r '.result.node_info.network' <<<"$status_payload")
        node_height=$(jq -r '.result.sync_info.latest_block_height' <<<"$status_payload")
        catching_up=$(jq -r '.result.sync_info.catching_up' <<<"$status_payload")
        if [ -n "$expected_chain_id" ] && [ "$node_chain_id" != "$expected_chain_id" ]; then
            fail "Local node reports chain '$node_chain_id', expected '$expected_chain_id'."
        else
            pass "Local CometBFT RPC is reachable on chain '$node_chain_id' at height $node_height."
        fi
        if [ "$catching_up" = "false" ]; then
            pass "Local node reports catching_up=false."
        elif [ "$catching_up" = "true" ]; then
            warn "Local node is still catching up; do not treat it as upgrade-ready yet."
        else
            unknown "Local node returned an unrecognized catching_up state."
        fi
    else
        unknown "Local CometBFT RPC did not return a valid status response."
    fi
fi

resolved_binary=$(readlink -f "$LIMONATA_BIN" 2>/dev/null || true)
expected_current="$LIMONATA_HOME/cosmovisor/current/bin/limonatad"
if [ -x "$LIMONATA_BIN" ]; then
    if [ "$resolved_binary" = "$expected_current" ]; then
        pass "Operator binary resolves to Cosmovisor current/bin."
    else
        warn "Operator binary does not resolve to '$expected_current'; this may be a legacy or non-Valley layout."
    fi
    current_version=$("$LIMONATA_BIN" version 2>/dev/null | head -n 1 || true)
    info "Current binary version: ${current_version:-unknown}."
else
    unknown "Limonata binary is not executable at '$LIMONATA_BIN'."
fi

if [ -x "$LIMONATA_BIN" ] && [ -n "$rpc_port" ] && [ -n "$node_chain_id" ]; then
    plan_json=$("$LIMONATA_BIN" query upgrade plan \
        --home "$LIMONATA_HOME" \
        --node "tcp://127.0.0.1:${rpc_port}" \
        --chain-id "$node_chain_id" \
        -o json 2>/dev/null || true)

    if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$plan_json"; then
        unknown "Could not query the current on-chain upgrade plan from the local node."
    else
        plan_name=$(jq -r '.plan.name // empty' <<<"$plan_json")
        plan_height=$(jq -r '.plan.height // empty' <<<"$plan_json")
        if [ -z "$plan_name" ] && [ -z "$plan_height" ]; then
            pass "No current on-chain upgrade plan is scheduled."
        elif [ -n "$plan_name" ] && [[ "$plan_height" =~ ^[0-9]+$ ]]; then
            info "Current upgrade plan: '$plan_name' at height $plan_height."
            if [[ "$node_height" =~ ^[0-9]+$ ]]; then
                if [ "$plan_height" -gt "$node_height" ]; then
                    info "Blocks remaining to planned height: $((plan_height - node_height))."
                else
                    warn "The planned height is not ahead of the current local height."
                fi
            fi

            if [[ "$plan_name" =~ ^[A-Za-z0-9._-]+$ ]]; then
                normalized_name=$(printf '%s' "$plan_name" | tr '[:upper:]' '[:lower:]')
                staged_binary="$LIMONATA_HOME/cosmovisor/upgrades/${normalized_name}/bin/limonatad"
                if [ -x "$staged_binary" ]; then
                    staged_sha=$(sha256sum "$staged_binary" | awk '{print $1}')
                    staged_version=$("$staged_binary" version 2>/dev/null | head -n 1 || true)
                    pass "Upgrade binary is staged at '$staged_binary'."
                    info "Staged binary version: ${staged_version:-unknown}; SHA256: $staged_sha."
                else
                    fail "No executable upgrade binary is staged at '$staged_binary'."
                fi
            else
                unknown "Upgrade name contains characters whose Cosmovisor path normalization is not handled by this checker; staged-binary status is unknown."
            fi
        else
            fail "Upgrade plan response is malformed: name/height are incomplete or invalid."
        fi
    fi
fi

printf '\nSummary: %d failure(s), %d warning(s), %d unknown check(s).\n' "$fail_count" "$warn_count" "$unknown_count"
if [ "$fail_count" -gt 0 ]; then
    exit 1
fi
if [ "$unknown_count" -gt 0 ]; then
    exit 2
fi
exit 0
