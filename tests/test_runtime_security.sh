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
fi
GO
chmod +x "$tmp/bin/go"

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
    "$@" bash "$script" >"$output" 2>&1
}

write_config true 'localhost:9090' true '127.0.0.1:8545' '127.0.0.1:8546' 'eth,net,web3'
if ! run_case "$tmp/loopback.out" env FAKE_GRPC_VERSION=v1.80.0; then
    fail "affected loopback configuration should return success with a warning"
fi
grep -Fq '[WARN] google.golang.org/grpc v1.80.0 is within the affected range for CVE-2026-84304' "$tmp/loopback.out" || fail "missing affected dependency warning"
grep -Fq '[PASS] gRPC is configured loopback-only at localhost:9090.' "$tmp/loopback.out" || fail "loopback gRPC was not accepted"
grep -Fq '[PASS] EVM JSON-RPC HTTP/WS listeners are configured loopback-only.' "$tmp/loopback.out" || fail "loopback JSON-RPC was not accepted"

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
grep -Fq 'does not claim current live exploitability' "$tmp/state-db-affected.out" || fail "missing source-equivalence limitation"

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
