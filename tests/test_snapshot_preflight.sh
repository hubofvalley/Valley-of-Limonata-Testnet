#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/repo/resources" "$tmp/fixtures" "$tmp/fake-bin" "$tmp/state"
cp "$root/VERSIONS.json" "$tmp/repo/VERSIONS.json"
cp "$root/resources/limonata_snapshot_preflight.sh" "$tmp/repo/resources/"

cat > "$tmp/fake-bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
dest='' url='' is_head=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output) dest=$2; shift 2 ;;
        --head) is_head=1; shift ;;
        https://*) url=$1; shift ;;
        *) shift ;;
    esac
done
[ -n "$dest" ] || exit 90
case "$url" in
    */snapshot.json)
        if [ "${MOCK_ROTATE:-0}" = 1 ] && [ -f "$MOCK_STATE/metadata_seen" ]; then
            cp "$MOCK_FIXTURES/metadata-rotated.json" "$dest"
        else
            : > "$MOCK_STATE/metadata_seen"
            cp "$MOCK_FIXTURES/metadata.json" "$dest"
        fi
        ;;
    */SHA256SUMS) cp "$MOCK_FIXTURES/SHA256SUMS" "$dest" ;;
    *.tar.lz4)
        [ "$is_head" = 1 ] || exit 91
        [ "${MOCK_HEAD_FAIL:-0}" != 1 ] || exit 22
        cp "$MOCK_FIXTURES/headers" "$dest"
        printf '200'
        ;;
    *rpc-limonata.posthuman.digital/status) cp "$MOCK_FIXTURES/rpc-b.json" "$dest" ;;
    *cosmos-rpc.limonata.xyz/status) cp "$MOCK_FIXTURES/rpc-a.json" "$dest" ;;
    *) exit 92 ;;
esac
MOCK
chmod +x "$tmp/fake-bin/curl"

digest=5b4dee0d19a954c47927d68f3dc12fb780976587c7d9f13824e5a02ce7828d1b
reset_fixtures() {
    rm -f "$tmp/state/metadata_seen"
    cat > "$tmp/fixtures/metadata.json" <<EOF
{"snapshot_name":"limonata_10777-1-latest.tar.lz4","snapshot_height":4789771,"snapshot_size_bytes":44529407354,"snapshot_sha256":"$digest","chain_id":"limonata_10777-1","snapshot_layout":["data"],"snapshot_compression":"lz4"}
EOF
    cp "$tmp/fixtures/metadata.json" "$tmp/fixtures/metadata-rotated.json"
    printf '%s  %s\n' "$digest" 'limonata_10777-1-latest.tar.lz4' > "$tmp/fixtures/SHA256SUMS"
    printf 'HTTP/2 200\r\nContent-Length: 44529407354\r\n\r\n' > "$tmp/fixtures/headers"
    printf '%s\n' '{"result":{"node_info":{"network":"limonata_10777-1"},"sync_info":{"latest_block_height":"4795141","catching_up":false}}}' > "$tmp/fixtures/rpc-a.json"
    cp "$tmp/fixtures/rpc-a.json" "$tmp/fixtures/rpc-b.json"
}

run_case() {
    env -u MOCK_ROTATE -u MOCK_HEAD_FAIL \
        MOCK_FIXTURES="$tmp/fixtures" MOCK_STATE="$tmp/state" \
        PATH="$tmp/fake-bin:$PATH" \
        bash "$tmp/repo/resources/limonata_snapshot_preflight.sh" > "$tmp/result" 2>&1
}

expect_unknown() {
    local name=$1
    if run_case; then
        printf 'FAIL: %s unexpectedly passed\n' "$name" >&2
        exit 1
    fi
    grep -Fq 'STATUS: UNKNOWN' "$tmp/result" || {
        printf 'FAIL: %s did not explain UNKNOWN\n' "$name" >&2
        cat "$tmp/result" >&2
        exit 1
    }
    printf 'PASS: %s refused\n' "$name"
}

reset_fixtures
run_case || { cat "$tmp/result" >&2; exit 1; }
grep -Fq 'STATUS: PRECHECK_PASS (metadata consistency only)' "$tmp/result"
grep -Fq 'ARCHIVE_INTEGRITY: UNVERIFIED' "$tmp/result"
grep -Fq 'RESTORE_READINESS: UNKNOWN' "$tmp/result"
printf 'PASS: matching provider metadata, manifest, HEAD and two public RPCs\n'

reset_fixtures
jq '.chain_id="other-chain"' "$tmp/fixtures/metadata.json" > "$tmp/fixtures/changed" && mv "$tmp/fixtures/changed" "$tmp/fixtures/metadata.json"
expect_unknown 'wrong metadata chain'

reset_fixtures
jq '.snapshot_name="../wrong.tar.lz4"' "$tmp/fixtures/metadata.json" > "$tmp/fixtures/changed" && mv "$tmp/fixtures/changed" "$tmp/fixtures/metadata.json"
expect_unknown 'traversal filename'

reset_fixtures
jq '.snapshot_sha256="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' "$tmp/fixtures/metadata.json" > "$tmp/fixtures/changed" && mv "$tmp/fixtures/changed" "$tmp/fixtures/metadata.json"
expect_unknown 'mismatching SHA256SUMS'

reset_fixtures
: > "$tmp/fixtures/SHA256SUMS"
expect_unknown 'missing checksum entry'

reset_fixtures
printf '%s  %s\n' "$digest" 'limonata_10777-1-latest.tar.lz4' >> "$tmp/fixtures/SHA256SUMS"
expect_unknown 'duplicate checksum entries'

reset_fixtures
printf 'HTTP/2 200\r\nContent-Length: 44\r\n\r\n' > "$tmp/fixtures/headers"
expect_unknown 'archive content-length mismatch'

reset_fixtures
: > "$tmp/fixtures/headers"
expect_unknown 'missing archive content-length'

reset_fixtures
jq '.result.node_info.network="other-chain"' "$tmp/fixtures/rpc-b.json" > "$tmp/fixtures/changed" && mv "$tmp/fixtures/changed" "$tmp/fixtures/rpc-b.json"
expect_unknown 'second RPC chain mismatch'

reset_fixtures
jq '.result.sync_info.catching_up=true' "$tmp/fixtures/rpc-a.json" > "$tmp/fixtures/changed" && mv "$tmp/fixtures/changed" "$tmp/fixtures/rpc-a.json"
expect_unknown 'catching-up RPC'

reset_fixtures
jq '.result.sync_info.latest_block_height="4789770"' "$tmp/fixtures/rpc-a.json" > "$tmp/fixtures/changed" && mv "$tmp/fixtures/changed" "$tmp/fixtures/rpc-a.json"
expect_unknown 'RPC behind snapshot'

reset_fixtures
jq '.result.sync_info.catching_up=null' "$tmp/fixtures/rpc-a.json" > "$tmp/fixtures/changed" && mv "$tmp/fixtures/changed" "$tmp/fixtures/rpc-a.json"
expect_unknown 'missing RPC sync status'

reset_fixtures
jq '.snapshot_height=4789800' "$tmp/fixtures/metadata.json" > "$tmp/fixtures/metadata-rotated.json"
export MOCK_ROTATE=1 MOCK_FIXTURES="$tmp/fixtures" MOCK_STATE="$tmp/state"
if PATH="$tmp/fake-bin:$PATH" bash "$tmp/repo/resources/limonata_snapshot_preflight.sh" > "$tmp/result" 2>&1; then
    echo 'FAIL: rotating metadata passed' >&2; exit 1
fi
grep -Fq 'snapshot metadata changed during preflight' "$tmp/result" || { cat "$tmp/result" >&2; exit 1; }
unset MOCK_ROTATE
printf 'PASS: metadata rotation refused\n'

reset_fixtures
jq '.network_facts.snapshot_url="UNKNOWN"' "$tmp/repo/VERSIONS.json" > "$tmp/repo/changed" && mv "$tmp/repo/changed" "$tmp/repo/VERSIONS.json"
expect_unknown 'unconfigured provider'

printf 'Snapshot metadata preflight regression checks passed.\n'
