#!/usr/bin/env bash

set -euo pipefail

script="resources/limonata_runtime_security.sh"

tmp=$(mktemp -d)
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

[ -f "$script" ] || fail "runtime security preflight missing"

mkdir -p "$tmp/home/config" "$tmp/bin"
cat > "$tmp/bin/limonatad" <<'BIN'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "version" ]; then
    printf 'name: limonatad\n'
    printf 'version: %s\n' "${FAKE_LIMONATA_VERSION:-v0.3.7}"
    printf 'commit: %s\n' "${FAKE_LIMONATA_COMMIT:-1111111111111111111111111111111111111111}"
    exit 0
fi
exit 0
BIN
chmod +x "$tmp/bin/limonatad"

cat > "$tmp/bin/go" <<'GO'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" != "version" ] || [ "${2:-}" != "-m" ]; then
    exit 64
fi
printf '%s: go1.26.5\n' "${3:-binary}"
if [ "${FAKE_NO_GRPC_DEP:-0}" != "1" ]; then
    printf '\tdep\tgoogle.golang.org/grpc\t%s\n' "${FAKE_GRPC_VERSION:-v1.80.0}"
    if [ "${FAKE_GRPC_REPLACEMENT:-0}" = "1" ]; then
        printf '\t=>\tgoogle.golang.org/grpc\t%s\n' "${FAKE_GRPC_REPLACEMENT_VERSION:-v1.80.0}"
    fi
fi
if [ "${FAKE_NO_COSMOS_SDK_DEP:-0}" != "1" ]; then
    printf '\tdep\tgithub.com/cosmos/cosmos-sdk\t%s\n' "${FAKE_COSMOS_SDK_VERSION:-v0.54.3}"
fi
if [ "${FAKE_NO_COMPRESS_DEP:-0}" != "1" ]; then
    printf '\tdep\tgithub.com/klauspost/compress\t%s\n' "${FAKE_COMPRESS_VERSION:-v1.18.6}"
    if [ "${FAKE_COMPRESS_REPLACEMENT:-0}" = "1" ]; then
        printf '\t=>\tgithub.com/klauspost/compress\tv1.20.2\n'
    fi
fi
GO
chmod +x "$tmp/bin/go"

cat > "$tmp/bin/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
url=${@: -1}
if [ "${FAKE_LIVE_QUERY_FAIL:-0}" = "1" ]; then
    exit 22
fi
case "$url" in
    */cosmos/base/tendermint/v1beta1/node_info)
        printf '{"default_node_info":{"network":"%s"},"application_version":{"version":"%s"}}\n' \
            "${FAKE_LIVE_CHAIN:-limonata_10777-1}" "${FAKE_LIVE_APP_VERSION:-v0.3.6}"
        ;;
    */cosmos/evm/erc20/v1/params)
        printf '{"params":{"enable_erc20":%s,"permissionless_registration":%s}}\n' \
            "${FAKE_ERC20_ENABLED:-true}" "${FAKE_PERMISSIONLESS_REGISTRATION:-true}"
        ;;
    *'/cosmos/evm/erc20/v1/token_pairs?pagination.limit=200')
        if [ "${FAKE_IBC_TOKEN_PAIR:-1}" = "1" ]; then
            printf '{"token_pairs":[{"denom":"ibc/ABC","enabled":true}]}\n'
        else
            printf '{"token_pairs":[]}\n'
        fi
        ;;
    *'/ibc/core/channel/v1/channels?pagination.limit=200')
        if [ "${FAKE_OPEN_TRANSFER_CHANNEL:-1}" = "1" ]; then
            printf '{"channels":[{"state":"STATE_OPEN","port_id":"transfer","channel_id":"channel-0"}]}\n'
        else
            printf '{"channels":[]}\n'
        fi
        ;;
    *)
        exit 22
        ;;
esac
CURL
chmod +x "$tmp/bin/curl"

write_config() {
    local grpc_enable=$1 grpc_address=$2 json_enable=$3 json_address=$4 json_ws=$5 json_api=$6
    cat > "$tmp/home/config/app.toml" <<CFG
[grpc]
enable = $grpc_enable
address = "$grpc_address"

[json-rpc]
enable = $json_enable
api = "$json_api"
address = "$json_address"
ws-address = "$json_ws"
CFG
}

run_case() {
    local output=$1
    shift
    LIMONATA_HOME="$tmp/home" \
    LIMONATA_BIN="$tmp/bin/limonatad" \
    GO_BIN="$tmp/bin/go" \
    CURL_BIN="$tmp/bin/curl" \
    "$@" bash "$script" >"$output" 2>&1
}

write_config true 'localhost:9090' true '127.0.0.1:8545' '127.0.0.1:8546' 'eth,net,web3'
if ! run_case "$tmp/loopback.out" env FAKE_GRPC_VERSION=v1.80.0; then
    fail "affected loopback configuration should return success with a warning"
fi
grep -Fq '[WARN] google.golang.org/grpc v1.80.0 is within the affected range for CVE-2026-84304' "$tmp/loopback.out" || fail "missing affected dependency warning"
grep -Fq '[PASS] gRPC is configured loopback-only at localhost:9090.' "$tmp/loopback.out" || fail "loopback gRPC was not accepted"
grep -Fq '[PASS] EVM JSON-RPC HTTP/WS listeners are configured loopback-only.' "$tmp/loopback.out" || fail "loopback JSON-RPC was not accepted"
grep -Fq '[WARN] Embedded github.com/klauspost/compress v1.18.6 is in the published affected range for GHSA-fpmh-frq8-7rj8' "$tmp/loopback.out" || fail "known affected Limonata dependency must warn"
grep -Fq 'does not establish that a Limonata runtime path accepts such frames' "$tmp/loopback.out" || fail "missing zstd reachability qualification"

# The advisory is version-based, not proof of Limonata-specific exploitability.
# Boundary, patched, unknown-version and missing-metadata cases must remain
# deterministic without decoding any untrusted input or running real binaries.
if ! run_case "$tmp/zstd-last-affected.out" env FAKE_GRPC_VERSION=v1.83.1 FAKE_COMPRESS_VERSION=v1.20.1; then
    fail "last affected zstd library version should warn, not claim exploitation"
fi
grep -Fq '[WARN] Embedded github.com/klauspost/compress v1.20.1 is in the published affected range' "$tmp/zstd-last-affected.out" || fail "missing last affected zstd boundary"

if ! run_case "$tmp/zstd-fixed.out" env FAKE_GRPC_VERSION=v1.83.1 FAKE_COMPRESS_VERSION=v1.20.2; then
    fail "first patched zstd library version should pass the advisory boundary"
fi
grep -Fq '[PASS] Embedded github.com/klauspost/compress v1.20.2 is outside the published GHSA-fpmh-frq8-7rj8 affected version range.' "$tmp/zstd-fixed.out" || fail "first patched zstd boundary not recognized"
if grep -Fq '[WARN] Embedded github.com/klauspost/compress v1.20.2' "$tmp/zstd-fixed.out"; then
    fail "patched zstd dependency must not be reported as affected"
fi

set +e
run_case "$tmp/zstd-missing.out" env FAKE_GRPC_VERSION=v1.83.1 FAKE_NO_COMPRESS_DEP=1
status=$?
set -e
[ "$status" -eq 2 ] || fail "missing embedded compression dependency must be UNKNOWN, not PASS"
grep -Fq '[UNKNOWN] Embedded build metadata did not expose github.com/klauspost/compress' "$tmp/zstd-missing.out" || fail "missing compression metadata must be reported"

set +e
run_case "$tmp/zstd-malformed.out" env FAKE_GRPC_VERSION=v1.83.1 FAKE_COMPRESS_VERSION=vunknown
status=$?
set -e
[ "$status" -eq 2 ] || fail "unparseable compression version must be UNKNOWN"
grep -Fq "[UNKNOWN] Could not compare embedded github.com/klauspost/compress version 'vunknown'" "$tmp/zstd-malformed.out" || fail "malformed compression version not reported"

set +e
run_case "$tmp/zstd-replaced.out" env FAKE_GRPC_VERSION=v1.83.1 FAKE_COMPRESS_REPLACEMENT=1
status=$?
set -e
[ "$status" -eq 2 ] || fail "module replacement must be UNKNOWN rather than classify the replaced original version"
grep -Fq '[UNKNOWN] Embedded github.com/klauspost/compress has a replacement module' "$tmp/zstd-replaced.out" || fail "replacement module metadata not reported"
if grep -Fq '[WARN] Embedded github.com/klauspost/compress' "$tmp/zstd-replaced.out"; then
    fail "replaced module must not use the original dependency version for vulnerability classification"
fi

write_config true '0.0.0.0:9090' true '127.0.0.1:8545' '127.0.0.1:8546' 'eth,net,web3'
set +e
run_case "$tmp/public-grpc.out" env FAKE_GRPC_VERSION=v1.80.0
status=$?
set -e
[ "$status" -eq 1 ] || fail "affected public gRPC listener should fail"
grep -Fq '[FAIL] Affected gRPC-Go server is configured on non-loopback listener 0.0.0.0:9090.' "$tmp/public-grpc.out" || fail "missing public gRPC failure"

write_config true '127.0.0.1.evil.example:9090' true '127.0.0.1:8545' '127.0.0.1:8546' 'eth,net,web3'
set +e
run_case "$tmp/deceptive-host.out" env FAKE_GRPC_VERSION=v1.80.0
status=$?
set -e
[ "$status" -eq 1 ] || fail "hostname beginning with 127. must not be treated as loopback"
grep -Fq '[FAIL] Affected gRPC-Go server is configured on non-loopback listener 127.0.0.1.evil.example:9090.' "$tmp/deceptive-host.out" || fail "deceptive hostname was not rejected"

write_config true '0.0.0.0:9090' true '127.0.0.1:8545' '127.0.0.1:8546' 'eth,net,web3'
if ! run_case "$tmp/patched.out" env FAKE_GRPC_VERSION=v1.83.1; then
    fail "patched gRPC version should not fail the known gRPC advisory gate"
fi
grep -Fq '[PASS] google.golang.org/grpc v1.83.1 is newer than the published CVE-2026-84304 affected range.' "$tmp/patched.out" || fail "patched gRPC version not recognized"

# The dep line is the original module requirement; an immediately following
# => line indicates replacement code. Neither original version is safe to
# classify without inspecting the replacement's source and provenance.
write_config true '0.0.0.0:9090' true '127.0.0.1:8545' '127.0.0.1:8546' 'eth,net,web3'
set +e
run_case "$tmp/grpc-replaced-old.out" env FAKE_GRPC_VERSION=v1.83.1 FAKE_GRPC_REPLACEMENT=1 FAKE_GRPC_REPLACEMENT_VERSION=v1.80.0
status=$?
set -e
[ "$status" -eq 2 ] || fail "a patched gRPC dep replaced by older code must be UNKNOWN, never PASS"
grep -Fq '[UNKNOWN] Embedded google.golang.org/grpc has a replacement module' "$tmp/grpc-replaced-old.out" || fail "missing gRPC replacement warning"
if grep -Fq '[PASS] google.golang.org/grpc v1.83.1' "$tmp/grpc-replaced-old.out"; then
    fail "replaced gRPC module must not be reported patched from the original dep version"
fi

set +e
run_case "$tmp/grpc-replaced-new.out" env FAKE_GRPC_VERSION=v1.80.0 FAKE_GRPC_REPLACEMENT=1 FAKE_GRPC_REPLACEMENT_VERSION=v1.83.1
status=$?
set -e
[ "$status" -eq 2 ] || fail "an affected gRPC dep replaced by other code must be UNKNOWN, not the original version verdict"
grep -Fq '[UNKNOWN] Embedded google.golang.org/grpc has a replacement module' "$tmp/grpc-replaced-new.out" || fail "missing gRPC replacement UNKNOWN"
if grep -Fq '[FAIL] Affected gRPC-Go server' "$tmp/grpc-replaced-new.out"; then
    fail "replaced gRPC module must not be classified from the original version"
fi

write_config true 'localhost:9090' true '0.0.0.0:8545' '0.0.0.0:8546' 'eth,net,web3'
if ! run_case "$tmp/public-jsonrpc.out" env FAKE_GRPC_VERSION=v1.83.1; then
    fail "public JSON-RPC signing-surface signal should warn without hard-failing absent keyring evidence"
fi
grep -Fq '[WARN] EVM JSON-RPC exposes a signing-capable namespace on a non-loopback listener.' "$tmp/public-jsonrpc.out" || fail "missing JSON-RPC signing-surface warning"

write_config false 'localhost:9090' false '127.0.0.1:8545' '127.0.0.1:8546' 'eth,net,web3'
set +e
run_case "$tmp/no-dep.out" env FAKE_NO_GRPC_DEP=1
status=$?
set -e
[ "$status" -eq 2 ] || fail "missing embedded gRPC metadata should return UNKNOWN exit 2"
grep -Fq '[UNKNOWN] Embedded build metadata did not expose google.golang.org/grpc.' "$tmp/no-dep.out" || fail "missing build metadata UNKNOWN"

write_config false 'localhost:9090' false '127.0.0.1:8545' '127.0.0.1:8546' 'eth,net,web3'
set +e
run_case "$tmp/state-db-affected.out" env \
    FAKE_GRPC_VERSION=v1.83.1 \
    FAKE_LIMONATA_VERSION=v0.3.6 \
    FAKE_LIMONATA_COMMIT=effa377d673fc6f0fb307a78ca54e037e53060f7
status=$?
set -e
[ "$status" -eq 1 ] || fail "reviewed v0.3.6 commit should fail the critical StateDB advisory gate"
grep -Fq '[FAIL] Active Limonata v0.3.6 commit effa377d673fc6f0fb307a78ca54e037e53060f7 matches the reviewed source state covered by critical GHSA-367m-g444-9mg3' "$tmp/state-db-affected.out" || fail "missing critical StateDB source-equivalence failure"
grep -Fq '[FAIL] The exact reviewed Limonata v0.3.6 binary embeds Cosmos SDK v0.54.3. Upstream v0.54.4 is an explicit state-breaking security patch release' "$tmp/state-db-affected.out" || fail "missing Cosmos SDK security patch-line finding"
grep -Fq 'not a claim that a specific Cosmos SDK vulnerability is exploitable on Limonata' "$tmp/state-db-affected.out" || fail "missing Cosmos SDK patch-line limitation"
grep -Fq '[PASS] Live REST endpoint reports expected chain limonata_10777-1 and application v0.3.6.' "$tmp/state-db-affected.out" || fail "missing live chain identity proof"
grep -Fq 'the live Limonata chain exposes the observable GHSA-367m-g444-9mg3 preconditions' "$tmp/state-db-affected.out" || fail "missing live StateDB exposure correlation"
grep -Fq 'does not reproduce the exploit or claim that exploitation has occurred' "$tmp/state-db-affected.out" || fail "missing live-exposure limitation"

write_config false 'localhost:9090' false '127.0.0.1:8545' '127.0.0.1:8546' 'eth,net,web3'
set +e
run_case "$tmp/state-db-no-open-channel.out" env \
    FAKE_GRPC_VERSION=v1.83.1 \
    FAKE_LIMONATA_VERSION=v0.3.6 \
    FAKE_LIMONATA_COMMIT=effa377d673fc6f0fb307a78ca54e037e53060f7 \
    FAKE_OPEN_TRANSFER_CHANNEL=0
status=$?
set -e
[ "$status" -eq 1 ] || fail "exact affected source should still fail when one live exposure precondition is absent"
grep -Fq 'did not expose every observable GHSA-367m-g444-9mg3 precondition checked by this tool' "$tmp/state-db-no-open-channel.out" || fail "missing absent-live-precondition result"
if grep -Fq 'the live Limonata chain exposes the observable GHSA-367m-g444-9mg3 preconditions' "$tmp/state-db-no-open-channel.out"; then
    fail "closed transfer channels must not be reported as full observable live preconditions"
fi

write_config false 'localhost:9090' false '127.0.0.1:8545' '127.0.0.1:8546' 'eth,net,web3'
set +e
run_case "$tmp/state-db-wrong-live-chain.out" env \
    FAKE_GRPC_VERSION=v1.83.1 \
    FAKE_LIMONATA_VERSION=v0.3.6 \
    FAKE_LIMONATA_COMMIT=effa377d673fc6f0fb307a78ca54e037e53060f7 \
    FAKE_LIVE_CHAIN=other-chain
status=$?
set -e
[ "$status" -eq 1 ] || fail "exact affected source should remain a hard failure when live endpoint identity is unknown"
grep -Fq '[UNKNOWN] Live REST endpoint did not prove the expected Limonata chain ID' "$tmp/state-db-wrong-live-chain.out" || fail "wrong live chain should be UNKNOWN"
if grep -Fq 'the live Limonata chain exposes the observable GHSA-367m-g444-9mg3 preconditions' "$tmp/state-db-wrong-live-chain.out"; then
    fail "wrong-chain REST data must not be used for live exposure correlation"
fi

write_config false 'localhost:9090' false '127.0.0.1:8545' '127.0.0.1:8546' 'eth,net,web3'
set +e
run_case "$tmp/state-db-unexpected-sdk.out" env \
    FAKE_GRPC_VERSION=v1.83.1 \
    FAKE_LIMONATA_VERSION=v0.3.6 \
    FAKE_LIMONATA_COMMIT=effa377d673fc6f0fb307a78ca54e037e53060f7 \
    FAKE_COSMOS_SDK_VERSION=v0.54.4
status=$?
set -e
[ "$status" -eq 1 ] || fail "exact affected source should remain a hard failure when embedded Cosmos SDK metadata is unexpected"
grep -Fq '[UNKNOWN] The exact reviewed Limonata v0.3.6 binary embeds unexpected Cosmos SDK version v0.54.4' "$tmp/state-db-unexpected-sdk.out" || fail "unexpected Cosmos SDK version should be UNKNOWN"

write_config false 'localhost:9090' false '127.0.0.1:8545' '127.0.0.1:8546' 'eth,net,web3'
set +e
run_case "$tmp/state-db-missing-sdk.out" env \
    FAKE_GRPC_VERSION=v1.83.1 \
    FAKE_LIMONATA_VERSION=v0.3.6 \
    FAKE_LIMONATA_COMMIT=effa377d673fc6f0fb307a78ca54e037e53060f7 \
    FAKE_NO_COSMOS_SDK_DEP=1
status=$?
set -e
[ "$status" -eq 1 ] || fail "exact affected source should remain a hard failure when Cosmos SDK build metadata is missing"
grep -Fq '[UNKNOWN] The exact reviewed Limonata v0.3.6 binary did not expose github.com/cosmos/cosmos-sdk build metadata' "$tmp/state-db-missing-sdk.out" || fail "missing Cosmos SDK metadata should be UNKNOWN"

write_config false 'localhost:9090' false '127.0.0.1:8545' '127.0.0.1:8546' 'eth,net,web3'
set +e
run_case "$tmp/state-db-unexpected-commit.out" env \
    FAKE_GRPC_VERSION=v1.83.1 \
    FAKE_LIMONATA_VERSION=v0.3.6 \
    FAKE_LIMONATA_COMMIT=2222222222222222222222222222222222222222
status=$?
set -e
[ "$status" -eq 2 ] || fail "v0.3.6 with an unexpected commit should be UNKNOWN"
grep -Fq '[UNKNOWN] Limonata v0.3.6 reports unexpected commit 2222222222222222222222222222222222222222' "$tmp/state-db-unexpected-commit.out" || fail "missing unexpected-commit UNKNOWN"

echo "Runtime security preflight checks passed."
