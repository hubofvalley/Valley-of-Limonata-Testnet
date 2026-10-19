#!/usr/bin/env bash

# Read-only metadata preflight. This never downloads or extracts the snapshot.
set -euo pipefail

die() {
    printf 'STATUS: UNKNOWN — %s\n' "$*" >&2
    exit 1
}

for tool in curl jq awk cmp; do
    command -v "$tool" >/dev/null 2>&1 || die "missing command: $tool"
done

readonly REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly VERSIONS="$REPO_ROOT/VERSIONS.json"
[ -f "$VERSIONS" ] || die "missing VERSIONS.json"

manifest_value() {
    jq -er "$1 | select(type == \"string\" and length > 0)" "$VERSIONS" 2>/dev/null
}

chain_id=$(manifest_value '.chain.chain_id') || die "missing manifest chain ID"
snapshot_base=$(manifest_value '.network_facts.snapshot_url') || die "missing snapshot provider"
rpc_a=$(manifest_value '.network_facts.state_sync_rpc') || die "missing primary CometBFT RPC"
rpc_b=$(manifest_value '.network_facts.snapshot_secondary_rpc') || die "missing secondary CometBFT RPC"

# No override accepting local or arbitrary remote URLs: only reviewed manifest hosts.
for endpoint in "$snapshot_base" "$rpc_a" "$rpc_b"; do
    [[ "$endpoint" =~ ^https://[A-Za-z0-9.-]+$ ]] || die "invalid reviewed HTTPS endpoint"
done
[ "$rpc_a" != "$rpc_b" ] || die "RPC URLs must be distinct"

tmp=$(mktemp -d) || die "cannot allocate temporary directory"
trap 'rm -rf -- "$tmp"' EXIT

fetch_small() {
    local url=$1 dest=$2
    curl --fail --silent --show-error --proto '=https' --proto-redir '=https' \
        --max-redirs 0 --connect-timeout 5 --max-time 15 --max-filesize 131072 \
        --output "$dest" "$url" || die "public metadata request failed"
}

fetch_small "$snapshot_base/snapshot.json" "$tmp/metadata.json"
fetch_small "$snapshot_base/SHA256SUMS" "$tmp/checksums"

jq -e --arg chain "$chain_id" '
    type == "object" and .chain_id == $chain and
    .snapshot_layout == ["data"] and .snapshot_compression == "lz4"
' "$tmp/metadata.json" >/dev/null || die "unexpected snapshot chain, layout, or compression"

name=$(jq -er '.snapshot_name | select(type == "string")' "$tmp/metadata.json") || die "missing snapshot name"
[[ "$name" =~ ^[A-Za-z0-9_.-]+$ && "$name" == "${chain_id}-"*.tar.lz4 ]] || die "unsafe snapshot filename"

height=$(jq -er '.snapshot_height | select(type == "number" and . > 0 and . == floor) | tostring' "$tmp/metadata.json") || die "invalid snapshot height"
size=$(jq -er '.snapshot_size_bytes | select(type == "number" and . > 0 and . == floor and . < 9007199254740992) | tostring' "$tmp/metadata.json") || die "invalid snapshot size"
digest=$(jq -er '.snapshot_sha256 | select(type == "string")' "$tmp/metadata.json") || die "missing snapshot digest"
[[ "$height" =~ ^[1-9][0-9]*$ && "$size" =~ ^[1-9][0-9]*$ ]] || die "non-integer snapshot height or size"
[[ "$digest" =~ ^[0-9A-Fa-f]{64}$ ]] || die "invalid snapshot SHA-256"

match_count=$(awk -v name="$name" 'NF == 2 && $2 == name { n++ } END { print n+0 }' "$tmp/checksums")
[ "$match_count" = 1 ] || die "snapshot checksum manifest has missing or duplicate filename"
manifest_digest=$(awk -v name="$name" 'NF == 2 && $2 == name { print $1 }' "$tmp/checksums")
[[ "$manifest_digest" =~ ^[0-9A-Fa-f]{64}$ ]] || die "invalid SHA256SUMS entry"
[[ "${manifest_digest,,}" == "${digest,,}" ]] || die "metadata and checksum manifest disagree"

# HEAD only: never stream any part of the multi-gigabyte archive.
head_status=$(curl --head --fail --silent --show-error --proto '=https' \
    --proto-redir '=https' --max-redirs 0 --connect-timeout 5 --max-time 15 \
    --output "$tmp/headers" --write-out '%{http_code}' \
    "$snapshot_base/$name") || die "archive HEAD request failed"
[ "$head_status" = 200 ] || die "archive HEAD did not return HTTP 200"
http_size=$(awk '{ gsub("\r", ""); if ($1 ~ /^HTTP\//) value=""; if (tolower($1) == "content-length:") value=$2 } END { print value }' "$tmp/headers")
[[ "$http_size" =~ ^[1-9][0-9]*$ ]] || die "archive HEAD missing valid Content-Length"
[ "$http_size" = "$size" ] || die "archive size does not match metadata"

check_rpc() {
    local endpoint=$1 response=$2 rpc_chain rpc_height syncing
    fetch_small "$endpoint/status" "$response"
    rpc_chain=$(jq -er '.result.node_info.network | select(type == "string")' "$response") || die "RPC chain ID unavailable"
    rpc_height=$(jq -er '.result.sync_info.latest_block_height | select(type == "string" or type == "number") | tostring' "$response") || die "RPC height unavailable"
    syncing=$(jq -r '.result.sync_info.catching_up | select(type == "boolean")' "$response") || die "RPC sync status unavailable"
    [ "$rpc_chain" = "$chain_id" ] || die "public RPC chain ID mismatch"
    [[ "$rpc_height" =~ ^[1-9][0-9]*$ ]] || die "invalid public RPC height"
    [[ "$syncing" == false || "$syncing" == true ]] || die "RPC sync status unavailable"
    [ "$syncing" = false ] || die "public RPC is catching up"
    [ "$rpc_height" -ge "$height" ] || die "snapshot height exceeds public RPC height"
    printf '%s' "$rpc_height"
}

height_a=$(check_rpc "$rpc_a" "$tmp/rpc-a.json") || die "primary RPC check failed"
height_b=$(check_rpc "$rpc_b" "$tmp/rpc-b.json") || die "secondary RPC check failed"

# A rotating latest alias may change during the preflight. Refuse such a race.
fetch_small "$snapshot_base/snapshot.json" "$tmp/metadata-again.json"
fetch_small "$snapshot_base/SHA256SUMS" "$tmp/checksums-again"
cmp -s "$tmp/metadata.json" "$tmp/metadata-again.json" || die "snapshot metadata changed during preflight"
cmp -s "$tmp/checksums" "$tmp/checksums-again" || die "checksum manifest changed during preflight"

printf 'STATUS: PRECHECK_PASS (metadata consistency only)\n'
printf 'CHAIN_ID: %s\nSNAPSHOT: %s\nHEIGHT: %s\nARCHIVE_SIZE_BYTES: %s\n' "$chain_id" "$name" "$height" "$size"
printf 'SHA256_EXPECTED: %s\nRPC_HEIGHTS: %s, %s\n' "${digest,,}" "$height_a" "$height_b"
printf 'ARCHIVE_INTEGRITY: UNVERIFIED — archive bytes were not downloaded or hashed.\n'
printf 'RESTORE_READINESS: UNKNOWN — do not restore without a full post-download checksum and validator-state recovery review.\n'
