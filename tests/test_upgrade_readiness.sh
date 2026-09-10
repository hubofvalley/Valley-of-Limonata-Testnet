#!/usr/bin/env bash

set -euo pipefail

checker="resources/limonata_upgrade_readiness.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

tmp=$(mktemp -d)
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

mkdir -p "$tmp/bin" "$tmp/home/.limonatad/config" "$tmp/home/.limonatad/data"

cat > "$tmp/home/.limonatad/config/config.toml" <<'EOF'
[rpc]
laddr = "tcp://127.0.0.1:38657"
EOF
cat > "$tmp/home/.limonatad/config/genesis.json" <<'EOF'
{"chain_id":"limonata_10777-1"}
EOF

cat > "$tmp/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${FAKE_POLICY:-safe}" in
    safe) printf '%s\n' 'DAEMON_NAME=limonatad DAEMON_HOME='"$LIMONATA_HOME"' DAEMON_ALLOW_DOWNLOAD_BINARIES=false DAEMON_DOWNLOAD_MUST_HAVE_CHECKSUM=true DAEMON_DATA_BACKUP_DIR='"$LIMONATA_HOME"'/cosmovisor/backup UNSAFE_SKIP_BACKUP=false' ;;
    skip-backup) printf '%s\n' 'DAEMON_NAME=limonatad DAEMON_HOME='"$LIMONATA_HOME"' DAEMON_ALLOW_DOWNLOAD_BINARIES=false DAEMON_DOWNLOAD_MUST_HAVE_CHECKSUM=true DAEMON_DATA_BACKUP_DIR='"$LIMONATA_HOME"'/cosmovisor/backup UNSAFE_SKIP_BACKUP=true' ;;
    unsafe-download) printf '%s\n' 'DAEMON_NAME=limonatad DAEMON_HOME='"$LIMONATA_HOME"' DAEMON_ALLOW_DOWNLOAD_BINARIES=true DAEMON_DOWNLOAD_MUST_HAVE_CHECKSUM=false DAEMON_DATA_BACKUP_DIR='"$LIMONATA_HOME"'/cosmovisor/backup UNSAFE_SKIP_BACKUP=true' ;;
    unavailable) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/systemctl"

cat > "$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ "${FAKE_RPC:-ok}" != "down" ] || exit 22
printf '%s\n' '{"result":{"node_info":{"network":"limonata_10777-1"},"sync_info":{"latest_block_height":"3344000","catching_up":false}}}'
EOF
chmod +x "$tmp/bin/curl"

cat > "$tmp/bin/limonatad" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "version" ]; then echo 'v0.3.6'; exit 0; fi
if [[ " $* " == *" query upgrade plan "* ]]; then
    case "${FAKE_PLAN:-none}" in
        none) echo '{}' ;;
        scheduled) echo '{"plan":{"name":"next-upgrade-v1","height":"3350000","info":""}}' ;;
        malformed) echo '{"plan":{"name":"next-upgrade-v1","height":"not-a-height"}}' ;;
        unavailable) exit 1 ;;
    esac
    exit 0
fi
exit 1
EOF
chmod +x "$tmp/bin/limonatad"

run_checker() {
    HOME="$tmp/home" \
    LIMONATA_HOME="$tmp/home/.limonatad" \
    LIMONATA_BIN="$tmp/bin/limonatad" \
    SYSTEMCTL_BIN="$tmp/bin/systemctl" \
    CURL_BIN="$tmp/bin/curl" \
    bash "$checker"
}

FAKE_POLICY=skip-backup FAKE_PLAN=none run_checker > "$tmp/skip-backup.out"
grep -Fq '[WARN] Cosmovisor automatic data backup is disabled' "$tmp/skip-backup.out" || fail "skip-backup policy was not surfaced"
grep -Fq '[PASS] No current on-chain upgrade plan is scheduled.' "$tmp/skip-backup.out" || fail "no-plan state was not detected"

set +e
FAKE_POLICY=unsafe-download FAKE_PLAN=none run_checker > "$tmp/unsafe-download.out"
status=$?
set -e
[ "$status" -eq 1 ] || fail "unsafe download policy did not fail readiness"
grep -Fq '[FAIL] Cosmovisor binary auto-download is enabled' "$tmp/unsafe-download.out" || fail "unsafe auto-download was not reported"
grep -Fq '[FAIL] Binary auto-download is enabled without mandatory checksums.' "$tmp/unsafe-download.out" || fail "missing checksum gate was not reported"

set +e
FAKE_POLICY=safe FAKE_PLAN=scheduled run_checker > "$tmp/missing-stage.out"
status=$?
set -e
[ "$status" -eq 1 ] || fail "scheduled upgrade without a staged binary did not fail readiness"
grep -Fq '[FAIL] No executable upgrade binary is staged' "$tmp/missing-stage.out" || fail "missing staged binary was not reported"

mkdir -p "$tmp/home/.limonatad/cosmovisor/upgrades/next-upgrade-v1/bin"
cp "$tmp/bin/limonatad" "$tmp/home/.limonatad/cosmovisor/upgrades/next-upgrade-v1/bin/limonatad"
chmod +x "$tmp/home/.limonatad/cosmovisor/upgrades/next-upgrade-v1/bin/limonatad"
FAKE_POLICY=safe FAKE_PLAN=scheduled run_checker > "$tmp/staged.out"
grep -Fq '[PASS] Upgrade binary is staged' "$tmp/staged.out" || fail "staged upgrade binary was not accepted"
grep -Fq 'SHA256:' "$tmp/staged.out" || fail "staged binary hash was not reported"

set +e
FAKE_POLICY=safe FAKE_RPC=down FAKE_PLAN=none run_checker > "$tmp/rpc-down.out"
status=$?
set -e
[ "$status" -eq 2 ] || fail "unavailable local RPC did not produce UNKNOWN exit status"
grep -Fq '[UNKNOWN] Local CometBFT RPC did not return a valid status response.' "$tmp/rpc-down.out" || fail "unavailable local RPC was not reported as UNKNOWN"

set +e
FAKE_POLICY=safe FAKE_PLAN=malformed run_checker > "$tmp/malformed-plan.out"
status=$?
set -e
[ "$status" -eq 1 ] || fail "malformed plan did not fail readiness"
grep -Fq '[FAIL] Upgrade plan response is malformed' "$tmp/malformed-plan.out" || fail "malformed plan was not reported"

echo "Upgrade-readiness checks passed."
