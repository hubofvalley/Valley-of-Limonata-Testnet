#!/bin/bash
set -euo pipefail

# Exercise the real read-only wrapper functions without sourcing its interactive
# menu, profile writes, node operations or service-management functions.
wrapper=resources/valleyofLimonata.sh
fail() { echo "FAIL: $*" >&2; exit 1; }
eval "$(sed -n '/^function hex_to_dec() {/,/^}/p' "$wrapper")"
eval "$(sed -n '/^function get_network_height() {/,/^}/p' "$wrapper")"
type get_network_height >/dev/null || fail 'network status function missing'

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat >"$tmp/bin/curl" <<'EOF'
#!/bin/bash
payload=''
while [ "$#" -gt 0 ]; do
    if [ "$1" = '-d' ]; then payload=$2; shift 2; else shift; fi
done
case "$payload" in
    *'"eth_chainId"'*)
        echo chain >> "$CALL_LOG"
        case "${FAKE_MODE:-ok}" in
            chain-down) exit 22 ;;
            mainnet) echo '{"jsonrpc":"2.0","id":1,"result":"0x5129"}' ;;
            malformed-chain) echo '{"jsonrpc":"2.0","id":1,"result":"bad"}' ;;
            error-chain) echo '{"jsonrpc":"2.0","id":1,"error":{"code":-1},"result":"0x2a19"}' ;;
            wrong-type) echo '{"jsonrpc":"2.0","id":1,"result":10777}' ;;
            *) echo '{"jsonrpc":"2.0","id":1,"result":"0x2a19"}' ;;
        esac
        ;;
    *'"eth_blockNumber"'*)
        echo block >> "$CALL_LOG"
        case "${FAKE_MODE:-ok}" in
            block-down) exit 22 ;;
            malformed-block) echo '{"jsonrpc":"2.0","id":1,"result":"not-hex"}' ;;
            oversized-block) echo '{"jsonrpc":"2.0","id":1,"result":"0x20000000000000"}' ;;
            block-error) echo '{"jsonrpc":"2.0","id":1,"error":{"code":-1},"result":"0x100"}' ;;
            *) echo '{"jsonrpc":"2.0","id":1,"result":"0x100"}' ;;
        esac
        ;;
    *) exit 22 ;;
esac
EOF
chmod +x "$tmp/bin/curl"
export PATH="$tmp/bin:$PATH" CALL_LOG="$tmp/calls" LIMONATA_EVM_RPC='https://rpc.example'
export LIMONATA_EVM_CHAIN_ID=10777

success() {
    local value
    : > "$CALL_LOG"
    value=$(FAKE_MODE="$1" get_network_height 2>"$tmp/stderr") || fail "rejected valid RPC: $1"
    [ "$value" = "$2" ] || fail "wrong height for $1: $value"
    [ "$(cat "$CALL_LOG")" = "$(printf 'chain\nblock')" ] || fail 'RPC check order incorrect'
}

unknown() {
    local value status
    : > "$CALL_LOG"
    set +e
    value=$(FAKE_MODE="$1" get_network_height 2>"$tmp/stderr")
    status=$?
    set -e
    [ "$status" -ne 0 ] || fail "false-ready on $1"
    [ -z "$value" ] || fail "leaked network height on $1"
    if [ "$2" = 'pre-height' ]; then
        ! grep -q block "$CALL_LOG" || fail "queried height after unverified chain: $1"
    fi
}

success ok 256
unknown mainnet pre-height
grep -Fq 'EVM RPC chain mismatch: expected 10777, received 20777' "$tmp/stderr" || fail 'wrong chain lacks explanation'
unknown chain-down pre-height
unknown malformed-chain pre-height
unknown error-chain pre-height
unknown wrong-type pre-height
unknown block-down post-chain
unknown malformed-block post-chain
unknown oversized-block post-chain
unknown block-error post-chain

# Expected chain is configuration-derived, not implicitly accepted as mainnet.
LIMONATA_EVM_CHAIN_ID=20777
success mainnet 256
LIMONATA_EVM_CHAIN_ID=invalid
unknown ok pre-height

echo 'Network status chain-identity tests passed.'
