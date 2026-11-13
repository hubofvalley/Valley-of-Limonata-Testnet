#!/usr/bin/env bash
set -euo pipefail

installer="resources/limonata_node_install_testnet.sh"
manifest="VERSIONS.json"
expected_sha="bb76a6d8abbb1bdeaa41d92811066b16bd6a48f58f7136e3fcb71226b6af4569"

fail() { echo "FAIL: $*" >&2; exit 1; }

grep -Fq "readonly LIMONATA_GENESIS_SHA256=\"$expected_sha\"" "$installer" || fail "installer genesis pin missing"
grep -Fq 'readonly LIMONATA_GENESIS_URL="https://limonata.xyz/genesis.json"' "$installer" || fail "genesis source unpinned"
jq -e --arg sha "$expected_sha" '.network_facts.genesis_sha256 == $sha' "$manifest" >/dev/null || fail "manifest/installer digest mismatch"
! grep -Fq 'curl -fsSL https://limonata.xyz/genesis.json -o "$LIMONATA_HOME/config/genesis.json"' "$installer" || fail "mutable genesis written directly into node home"

# The download, verification gate and install must run in that order.
line_of() { grep -nF "$1" "$installer" | head -n 1 | cut -d: -f1; }
fetch_line=$(line_of '"$LIMONATA_GENESIS_URL" -o "$GENESIS_CANDIDATE"')
verify_line=$(line_of 'if ! verify_genesis_candidate "$GENESIS_CANDIDATE"; then')
install_line=$(line_of 'install -m 0644 "$GENESIS_CANDIDATE" "$LIMONATA_HOME/config/genesis.json"')
validate_line=$(line_of '"$LIMONATA_BIN" --home "$LIMONATA_HOME" genesis validate-genesis')
cosmovisor_line=$(grep -n '^install_cosmovisor$' "$installer" | head -n 1 | cut -d: -f1)
binary_line=$(line_of 'install -m 0755 "$STAGED_BINARY" "$LIMONATA_BIN"')
init_line=$(line_of '"$LIMONATA_BIN" --home "$LIMONATA_HOME" init')
[[ "$fetch_line" =~ ^[0-9]+$ && "$verify_line" =~ ^[0-9]+$ && "$cosmovisor_line" =~ ^[0-9]+$ && "$binary_line" =~ ^[0-9]+$ && "$init_line" =~ ^[0-9]+$ && "$install_line" =~ ^[0-9]+$ && "$validate_line" =~ ^[0-9]+$ ]] || fail "genesis provenance sequence missing"
((fetch_line < verify_line && verify_line < cosmovisor_line && cosmovisor_line < binary_line && binary_line < init_line && init_line < install_line && install_line < validate_line)) || fail "genesis was fetched or validated after executable installation or node initialization"

# Extract and execute only the small pure validation helper; never source the
# interactive installer, open a node home or contact a network.
helper=$(awk '/^verify_genesis_candidate\(\) \{/ {inside=1} inside {print} inside && /^}/ {exit}' "$installer")
[[ "$helper" == *'verify_genesis_candidate()'* ]] || fail "helper not found"
eval "$helper"

temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT
printf '{"chain_id":"limonata_10777-1"}\n' > "$temp_dir/valid.json"
LIMONATA_GENESIS_SHA256=$(sha256sum "$temp_dir/valid.json" | awk '{print $1}')
verify_genesis_candidate "$temp_dir/valid.json" || fail "valid genesis rejected"

printf 'changed\n' >> "$temp_dir/valid.json"
if verify_genesis_candidate "$temp_dir/valid.json" > "$temp_dir/output" 2>&1; then
    fail "modified genesis accepted"
fi
grep -Fq 'Pinned genesis SHA256 mismatch' "$temp_dir/output" || fail "digest rejection not explained"

# Current mutable upstream URL serves a different chain. This must fail on
# provenance, not silently stage a mainnet genesis for the testnet installer.
printf '{"chain_id":"limonata_20777-1"}\n' > "$temp_dir/mainnet.json"
LIMONATA_GENESIS_SHA256="$expected_sha"
if verify_genesis_candidate "$temp_dir/mainnet.json" > "$temp_dir/output" 2>&1; then
    fail "mainnet genesis accepted by testnet installer"
fi
grep -Fq 'Pinned genesis SHA256 mismatch' "$temp_dir/output" || fail "wrong-network digest mismatch not explained"
grep -Fq 'reviewed testnet source' "$temp_dir/output" || fail "operator guidance missing on upstream genesis transition"

printf '{"chain_id":"unexpected-chain"}\n' > "$temp_dir/wrong-chain.json"
LIMONATA_GENESIS_SHA256=$(sha256sum "$temp_dir/wrong-chain.json" | awk '{print $1}')
if verify_genesis_candidate "$temp_dir/wrong-chain.json" > "$temp_dir/output" 2>&1; then
    fail "wrong-chain genesis accepted despite matching candidate digest"
fi
grep -Fq 'Genesis chain-id mismatch' "$temp_dir/output" || fail "chain rejection not explained"

printf '{invalid json' > "$temp_dir/malformed.json"
LIMONATA_GENESIS_SHA256=$(sha256sum "$temp_dir/malformed.json" | awk '{print $1}')
if verify_genesis_candidate "$temp_dir/malformed.json" > "$temp_dir/output" 2>&1; then
    fail "malformed genesis accepted"
fi
grep -Fq 'Malformed genesis JSON' "$temp_dir/output" || fail "JSON rejection not explained"

if verify_genesis_candidate "$temp_dir/missing.json" > "$temp_dir/output" 2>&1; then
    fail "missing genesis accepted"
fi
echo "Genesis provenance conformance and negative fixtures passed."
