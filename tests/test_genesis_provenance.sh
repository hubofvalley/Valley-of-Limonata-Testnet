#!/bin/bash

set -euo pipefail

installer="resources/limonata_node_install_testnet.sh"
versions="VERSIONS.json"
expected_sha="bb76a6d8abbb1bdeaa41d92811066b16bd6a48f58f7136e3fcb71226b6af4569"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

[ -f "$installer" ] || fail "installer missing"
[ -f "$versions" ] || fail "VERSIONS.json missing"

grep -Fq "readonly LIMONATA_GENESIS_SHA256=\"${expected_sha}\"" "$installer" \
    || fail "installer genesis digest is not pinned"
jq -e --arg sha "$expected_sha" '.network_facts.genesis_sha256 == $sha' "$versions" >/dev/null \
    || fail "VERSIONS.json genesis digest does not match installer"
grep -Fq 'readonly LIMONATA_GENESIS_URL="https://limonata.xyz/genesis.json"' "$installer" \
    || fail "installer canonical genesis URL is not explicit"

# The mutable URL must never write directly into the node home. The candidate is
# verified in the temporary workdir first, then installed only after digest and
# chain-id gates pass.
if grep -Fq 'curl -fsSL https://limonata.xyz/genesis.json -o "$LIMONATA_HOME/config/genesis.json"' "$installer"; then
    fail "installer still writes mutable genesis directly into node home"
fi

download_line=$(grep -nF 'curl -fsSL "$LIMONATA_GENESIS_URL" -o "$GENESIS_CANDIDATE"' "$installer" | cut -d: -f1)
hash_line=$(grep -nF 'GENESIS_ACTUAL_SHA256=$(sha256sum "$GENESIS_CANDIDATE"' "$installer" | cut -d: -f1)
hash_gate_line=$(grep -nF 'if [ "$GENESIS_ACTUAL_SHA256" != "$LIMONATA_GENESIS_SHA256" ]; then' "$installer" | cut -d: -f1)
chain_line=$(grep -nF 'GENESIS_CHAIN_ID=$(jq -r' "$installer" | cut -d: -f1)
chain_gate_line=$(grep -nF 'if [ "$GENESIS_CHAIN_ID" != "limonata_10777-1" ]; then' "$installer" | cut -d: -f1)
install_line=$(grep -nF 'install -m 0644 "$GENESIS_CANDIDATE" "$LIMONATA_HOME/config/genesis.json"' "$installer" | cut -d: -f1)
validate_line=$(grep -nF '"$LIMONATA_BIN" --home "$LIMONATA_HOME" genesis validate-genesis' "$installer" | cut -d: -f1)

for value in "$download_line" "$hash_line" "$hash_gate_line" "$chain_line" "$chain_gate_line" "$install_line" "$validate_line"; do
    [[ "$value" =~ ^[0-9]+$ ]] || fail "genesis provenance sequence is incomplete"
done

[ "$download_line" -lt "$hash_line" ] || fail "genesis hash occurs before download"
[ "$hash_line" -lt "$hash_gate_line" ] || fail "genesis digest is not checked after hashing"
[ "$hash_gate_line" -lt "$chain_line" ] || fail "chain-id is inspected before digest gate"
[ "$chain_line" -lt "$chain_gate_line" ] || fail "chain-id is not checked after parsing"
[ "$chain_gate_line" -lt "$install_line" ] || fail "genesis is installed before provenance gates pass"
[ "$install_line" -lt "$validate_line" ] || fail "semantic genesis validation does not follow installation"

grep -Fq 'Pinned genesis SHA256 mismatch. Refusing installation.' "$installer" \
    || fail "digest mismatch is not fail-closed"
grep -Fq 'Genesis chain-id mismatch. Refusing installation.' "$installer" \
    || fail "chain-id mismatch is not fail-closed"

echo "Genesis provenance contract checks passed."
