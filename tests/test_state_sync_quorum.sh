#!/bin/bash

set -euo pipefail

installer="resources/limonata_node_install_testnet.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

extract_function() {
    local name=$1
    awk -v name="$name" '
        $0 ~ "^" name "\\(\\) \\{" { found=1; depth=0 }
        found {
            print
            opens=gsub(/\{/, "{")
            closes=gsub(/\}/, "}")
            depth += opens - closes
            if (depth == 0) exit
        }
    ' "$installer"
}

eval "$(extract_function normalize_state_sync_rpc)"
eval "$(extract_function fetch_state_sync_rpc_height)"
eval "$(extract_function fetch_state_sync_commit_hash)"
eval "$(extract_function configure_state_sync)"

tmp=$(mktemp -d)
cleanup() {
    rm -rf "$tmp"
}
trap cleanup EXIT

mkdir -p "$tmp/bin"
cat > "$tmp/bin/curl" <<'EOF'
#!/bin/bash
set -euo pipefail

url=${!#}
primary='https://primary.example'
witness='https://witness.example'
chain='limonata_10777-1'

if [ "${FAKE_MODE:-ok}" = "witness-down" ] && [[ "$url" == "$witness"* ]]; then
    exit 22
fi
if [ "${FAKE_MODE:-ok}" = "wrong-chain" ] && [[ "$url" == "$witness/status" ]]; then
    chain='other-chain'
fi

case "$url" in
    "$primary/status")
        printf '{"result":{"node_info":{"network":"%s"},"sync_info":{"latest_block_height":"3303451","catching_up":false}}}\n' "$chain"
        ;;
    "$witness/status")
        printf '{"result":{"node_info":{"network":"%s"},"sync_info":{"latest_block_height":"3303453","catching_up":false}}}\n' "$chain"
        ;;
    "$primary/commit?height=3301000")
        printf '{"result":{"signed_header":{"header":{"chain_id":"limonata_10777-1","height":"3301000"},"commit":{"block_id":{"hash":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}}}}}\n'
        ;;
    "$witness/commit?height=3301000")
        hash='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
        [ "${FAKE_MODE:-ok}" != "hash-mismatch" ] || hash='BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'
        printf '{"result":{"signed_header":{"header":{"chain_id":"limonata_10777-1","height":"3301000"},"commit":{"block_id":{"hash":"%s"}}}}}\n' "$hash"
        ;;
    *)
        exit 22
        ;;
esac
EOF
chmod +x "$tmp/bin/curl"

make_config() {
    cat > "$tmp/config.toml" <<'EOF'
[statesync]
enable = false
rpc_servers = ""
trust_height = 0
trust_hash = ""
trust_period = "168h0m0s"

[p2p]
laddr = "tcp://0.0.0.0:26656"
EOF
    CFG="$tmp/config.toml"
}

export PATH="$tmp/bin:$PATH"
export LIMONATA_STATE_SYNC_PRIMARY_RPC='https://primary.example/'
export LIMONATA_STATE_SYNC_WITNESS_RPC='https://witness.example/'

make_config
FAKE_MODE=ok configure_state_sync >/dev/null || fail "matching independent RPCs were rejected"
grep -Fq 'rpc_servers = "https://primary.example,https://witness.example"' "$CFG" || fail "distinct RPCs were not written"
grep -Fq 'trust_height = 3301000' "$CFG" || fail "common trust height was not selected"
grep -Fq 'trust_hash = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"' "$CFG" || fail "agreed trust hash was not written"

make_config
set +e
FAKE_MODE=hash-mismatch configure_state_sync >/dev/null 2>&1
status=$?
set -e
[ "$status" -ne 0 ] || fail "hash disagreement was accepted"
grep -Fq 'enable = false' "$CFG" || fail "failed quorum mutated state-sync enablement"

make_config
set +e
FAKE_MODE=witness-down configure_state_sync >/dev/null 2>&1
status=$?
set -e
[ "$status" -ne 0 ] || fail "unavailable witness was accepted"

make_config
set +e
FAKE_MODE=wrong-chain configure_state_sync >/dev/null 2>&1
status=$?
set -e
[ "$status" -ne 0 ] || fail "wrong-chain witness was accepted"

make_config
LIMONATA_STATE_SYNC_WITNESS_RPC='https://primary.example/'
set +e
FAKE_MODE=ok configure_state_sync >/dev/null 2>&1
status=$?
set -e
[ "$status" -ne 0 ] || fail "duplicate RPC endpoints were accepted"

echo "State-sync quorum checks passed."
