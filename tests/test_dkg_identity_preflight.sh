#!/usr/bin/env bash

set -euo pipefail

script="resources/limonata_dkg_identity_preflight.sh"
fail() {
    echo "FAIL: $*" >&2
    exit 1
}

[ -x "$script" ] || fail "DKG identity preflight is missing or not executable"

tmp=$(mktemp -d)
cleanup() {
    rm -rf "$tmp"
}
trap cleanup EXIT

make_binary() {
    local path=$1 version=$2 commit=$3
    cat > "$path" <<EOF_BIN
#!/usr/bin/env bash
if [ "\${1:-}" = "version" ] && [ "\${2:-}" = "--long" ]; then
    cat <<'EOF_VERSION'
version: $version
commit: $commit
EOF_VERSION
    exit 0
fi
exit 1
EOF_BIN
    chmod +x "$path"
}

write_config() {
    local path=$1 key_file=$2 laddr=$3
    mkdir -p "$(dirname "$path")"
    cat > "$path" <<EOF_CONFIG
proxy_app = "tcp://127.0.0.1:26658"
priv_validator_key_file = "$key_file"
priv_validator_laddr = "$laddr"

[rpc]
laddr = "tcp://127.0.0.1:26657"
EOF_CONFIG
}

reviewed_commit="effa377d673fc6f0fb307a78ca54e037e53060f7"

case1="$tmp/case1"
mkdir -p "$case1/home/config" "$case1/home/identity" "$case1/bin"
make_binary "$case1/bin/limonatad" "v0.3.6" "$reviewed_commit"
write_config "$case1/home/config/config.toml" "identity/consensus.json" "tcp://127.0.0.1:1234"
printf 'DO-NOT-READ\n' > "$case1/home/identity/consensus.json"
set +e
LIMONATA_HOME="$case1/home" LIMONATA_BIN="$case1/bin/limonatad" bash "$script" > "$case1/out" 2>&1
status=$?
set -e
[ "$status" -eq 0 ] || fail "remote signer with existing identity path did not exit 0"
grep -Fq '[PASS] Remote-signer DKG identity path exists as a regular file.' "$case1/out" || fail "existing identity path was not reported"
grep -Fq 'File contents were intentionally not read.' "$case1/out" || fail "privacy boundary warning is missing"

case2="$tmp/case2"
mkdir -p "$case2/home/config" "$case2/bin"
make_binary "$case2/bin/limonatad" "v0.3.6" "$reviewed_commit"
write_config "$case2/home/config/config.toml" "config/priv_validator_key.json" "tcp://127.0.0.1:1234"
set +e
LIMONATA_HOME="$case2/home" LIMONATA_BIN="$case2/bin/limonatad" bash "$script" > "$case2/out" 2>&1
status=$?
set -e
[ "$status" -eq 1 ] || fail "missing remote-signer identity path did not fail closed"
grep -Fq '[FAIL] Remote signer is configured but the Limonata DKG identity path does not exist.' "$case2/out" || fail "missing path failure message is absent"

case3="$tmp/case3"
mkdir -p "$case3/home/config" "$case3/bin" "$case3/external"
make_binary "$case3/bin/limonatad" "0.3.6" "$reviewed_commit"
printf 'DO-NOT-READ\n' > "$case3/external/identity.json"
write_config "$case3/home/config/config.toml" "$case3/external/identity.json" "tcp://127.0.0.1:1234"
LIMONATA_HOME="$case3/home" LIMONATA_BIN="$case3/bin/limonatad" bash "$script" > "$case3/out" 2>&1 || fail "absolute identity path was rejected"
grep -Fq "Configured DKG identity path: $case3/external/identity.json" "$case3/out" || fail "absolute path resolution is wrong"

case4="$tmp/case4"
mkdir -p "$case4/home/config" "$case4/bin"
make_binary "$case4/bin/limonatad" "v0.3.6" "1111111111111111111111111111111111111111"
write_config "$case4/home/config/config.toml" "config/priv_validator_key.json" "tcp://127.0.0.1:1234"
set +e
LIMONATA_HOME="$case4/home" LIMONATA_BIN="$case4/bin/limonatad" bash "$script" > "$case4/out" 2>&1
status=$?
set -e
[ "$status" -eq 2 ] || fail "unreviewed commit did not return UNKNOWN"
grep -Fq '[UNKNOWN] No DKG identity rule is encoded' "$case4/out" || fail "unreviewed commit did not explain UNKNOWN"
if grep -Fq '[FAIL] Remote signer is configured' "$case4/out"; then
    fail "unreviewed source was incorrectly hard-classified"
fi

case5="$tmp/case5"
mkdir -p "$case5/home/config" "$case5/bin"
make_binary "$case5/bin/limonatad" "v0.3.6" "$reviewed_commit"
write_config "$case5/home/config/config.toml" "config/priv_validator_key.json" ""
LIMONATA_HOME="$case5/home" LIMONATA_BIN="$case5/bin/limonatad" bash "$script" > "$case5/out" 2>&1 || fail "full-node ambiguous case should remain warning-only"
grep -Fq '[WARN] Local priv-validator identity path is absent.' "$case5/out" || fail "full-node ambiguity warning is missing"

echo "DKG identity preflight checks passed."
