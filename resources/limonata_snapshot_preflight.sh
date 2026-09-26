#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
VERSIONS_FILE=${LIMONATA_VERSIONS_FILE:-"$SCRIPT_DIR/../VERSIONS.json"}
SNAPSHOT_BASE_URL=${LIMONATA_SNAPSHOT_BASE_URL:-${1:-}}
RPC_URL=${LIMONATA_RPC_URL:-}
HTTP_TIMEOUT=${LIMONATA_PREFLIGHT_HTTP_TIMEOUT:-15}
fail_count=0
unknown_count=0

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; fail_count=$((fail_count + 1)); }
unknown() { printf 'UNKNOWN: %s\n' "$*" >&2; unknown_count=$((unknown_count + 1)); }
note() { printf 'NOTE: %s\n' "$*"; }

for cmd in jq curl awk date; do
  command -v "$cmd" >/dev/null 2>&1 || { printf 'Missing required command: %s\n' "$cmd" >&2; exit 2; }
done

if [ -z "$SNAPSHOT_BASE_URL" ]; then
  echo "Set LIMONATA_SNAPSHOT_BASE_URL or pass the provider base URL as argument." >&2
  exit 2
fi
SNAPSHOT_BASE_URL=${SNAPSHOT_BASE_URL%/}

if [ ! -r "$VERSIONS_FILE" ] || ! jq -e . "$VERSIONS_FILE" >/dev/null 2>&1; then
  echo "VERSIONS manifest unavailable or invalid: $VERSIONS_FILE" >&2
  exit 2
fi

EXPECTED_CHAIN_ID=$(jq -r '.chain.chain_id // empty' "$VERSIONS_FILE")
[ -n "$EXPECTED_CHAIN_ID" ] || { echo "VERSIONS manifest is missing .chain.chain_id" >&2; exit 2; }

if [ -z "$RPC_URL" ]; then
  RPC_URL=$(jq -r '.network_facts.state_sync_rpc // empty' "$VERSIONS_FILE")
fi
[ -n "$RPC_URL" ] || { echo "No read-only RPC configured." >&2; exit 2; }
RPC_URL=${RPC_URL%/}

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
metadata="$workdir/snapshot.json"
checksums="$workdir/SHA256SUMS"
status_json="$workdir/status.json"

if ! curl -fsSL --max-time "$HTTP_TIMEOUT" "$SNAPSHOT_BASE_URL/snapshot.json" -o "$metadata"; then
  unknown "snapshot metadata is unavailable"
fi
if ! curl -fsSL --max-time "$HTTP_TIMEOUT" "$SNAPSHOT_BASE_URL/SHA256SUMS" -o "$checksums"; then
  unknown "checksum manifest is unavailable"
fi

if [ ! -s "$metadata" ]; then
  printf 'RESULT: UNKNOWN (%d required source(s) unavailable)\n' "$unknown_count" >&2
  exit 2
fi
if ! jq -e . "$metadata" >/dev/null 2>&1; then
  echo "RESULT: FAIL (snapshot metadata is invalid JSON)" >&2
  exit 1
fi

filename=$(jq -r '.filename // .file // .archive // empty' "$metadata")
chain_id=$(jq -r '.chain_id // empty' "$metadata")
height=$(jq -r '.height // empty' "$metadata")
size=$(jq -r '.size // .size_bytes // empty' "$metadata")
timestamp=$(jq -r '.timestamp // .created_at // empty' "$metadata")
compression=$(jq -r '.compression // empty' "$metadata")
sha256=$(jq -r '.sha256 // .checksum_sha256 // empty' "$metadata" | tr '[:upper:]' '[:lower:]')
layout_has_data=$(jq -r 'if (.layout | type) == "array" then (.layout | index("data") != null) else false end' "$metadata" 2>/dev/null || printf false)

if [[ "$filename" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.tar\.lz4$ ]] && [[ "$filename" != *".."* ]]; then pass "safe archive filename"; else fail "archive filename is missing or unsafe"; fi
[ "$chain_id" = "$EXPECTED_CHAIN_ID" ] && pass "chain ID matches $EXPECTED_CHAIN_ID" || fail "chain ID mismatch"
[[ "$height" =~ ^[0-9]+$ ]] && [ "$height" -gt 0 ] && pass "positive snapshot height" || fail "invalid snapshot height"
[[ "$size" =~ ^[0-9]+$ ]] && [ "$size" -gt 0 ] && pass "positive snapshot size" || fail "invalid snapshot size"
[[ "$sha256" =~ ^[0-9a-f]{64}$ ]] && pass "valid metadata SHA-256" || fail "invalid metadata SHA-256"
[ "$compression" = "lz4" ] && pass "lz4 compression" || fail "unexpected compression"
[ "$layout_has_data" = true ] && pass "data layout declared" || fail "data layout missing"
date -u -d "$timestamp" +%s >/dev/null 2>&1 && pass "parseable timestamp" || fail "invalid timestamp"

if [ -s "$checksums" ] && [[ "$sha256" =~ ^[0-9a-f]{64}$ ]] && [ -n "$filename" ]; then
  manifest_sha=$(awk -v target="$filename" '{ name=$2; sub(/^\*/, "", name); if (name == target) { print tolower($1); exit } }' "$checksums")
  [ -n "$manifest_sha" ] || fail "SHA256SUMS entry missing"
  [ -z "$manifest_sha" ] || { [ "$manifest_sha" = "$sha256" ] && pass "metadata checksum matches SHA256SUMS" || fail "metadata checksum disagrees with SHA256SUMS"; }
fi

if headers=$(curl -fsSI --max-time "$HTTP_TIMEOUT" "$SNAPSHOT_BASE_URL/$filename" 2>/dev/null); then
  content_length=$(printf '%s\n' "$headers" | awk 'BEGIN{IGNORECASE=1} /^Content-Length:/ {gsub("\r", "", $2); print $2; exit}')
  if [ -z "$content_length" ]; then
    unknown "archive HEAD response lacks Content-Length"
  elif [[ "$size" =~ ^[0-9]+$ ]] && [ "$content_length" = "$size" ]; then
    pass "archive Content-Length matches metadata"
  else
    fail "archive Content-Length mismatch"
  fi
else
  unknown "archive HEAD request failed"
fi

if curl -fsSL --max-time "$HTTP_TIMEOUT" "$RPC_URL/status" -o "$status_json"; then
  if ! jq -e . "$status_json" >/dev/null 2>&1; then
    fail "RPC status is invalid JSON"
  else
    live_chain_id=$(jq -r '.result.node_info.network // empty' "$status_json")
    live_height=$(jq -r '.result.sync_info.latest_block_height // empty' "$status_json")
    catching_up=$(jq -r '.result.sync_info.catching_up // empty | tostring' "$status_json")
    [ "$live_chain_id" = "$EXPECTED_CHAIN_ID" ] || fail "RPC chain ID mismatch"
    if ! [[ "$live_height" =~ ^[0-9]+$ ]] || [ "$live_height" -le 0 ]; then
      fail "RPC height invalid"
    elif [ "$catching_up" != "false" ]; then
      unknown "RPC is catching up or sync state is unknown"
    elif [[ "$height" =~ ^[0-9]+$ ]] && [ "$height" -gt "$live_height" ]; then
      fail "snapshot height is ahead of live RPC height"
    else
      pass "snapshot height is not ahead of live chain"
    fi
  fi
else
  unknown "read-only RPC status is unavailable"
fi

note "This validates provider metadata consistency only; it does not authenticate the provider as Limonata upstream."
note "Before restore, independently hash the downloaded archive bytes and compare them with the reviewed SHA-256."

if [ "$fail_count" -gt 0 ]; then
  printf 'RESULT: FAIL (%d failed, %d unknown)\n' "$fail_count" "$unknown_count" >&2
  exit 1
fi
if [ "$unknown_count" -gt 0 ]; then
  printf 'RESULT: UNKNOWN (%d check(s) unavailable)\n' "$unknown_count" >&2
  exit 2
fi
echo "RESULT: PASS"
