#!/usr/bin/env bash
set -euo pipefail

# Exercise the actual updater post-stop section using sandboxed executables
# and systemd mocks. Never execute downloads, service or node operations.
cd "$(dirname "$0")/.."
updater="resources/limonata_update.sh"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

for marker in 'restore_previous_binary() {' 'abort_and_restore() {' \
    'installed binary version command failed' 'systemd daemon-reload failed'; do
    grep -Fq "$marker" "$updater" || { echo "Missing updater guard: $marker"; exit 1; }
done
{
    printf 'set -euo pipefail\n'
    printf 'UPDATE_IN_PROGRESS=0\n'
    sed -n '/^cleanup() {/,/^}/p' "$updater"
    printf 'trap cleanup EXIT\n'
    sed -n '/^restore_previous_binary() {/,/^}/p' "$updater"
    sed -n '/^abort_and_restore() {/,/^}/p' "$updater"
    sed -n '/^cp "\$legacy_binary" "\$BACKUP_BINARY"$/,$p' "$updater"
} > "$tmp/post-stop-under-test.sh"
bash -n "$tmp/post-stop-under-test.sh"

run_case() {
    local scenario=$1 expected_restarts=$2 dir="$tmp/$1" rc=0 actual_restarts
    mkdir -p "$dir/home/go/bin" "$dir/update" "$dir/mock"
    cat > "$dir/home/go/bin/limonatad" <<'SH'
#!/bin/sh
echo v0.3.5
SH
    chmod 0755 "$dir/home/go/bin/limonatad"
    cp "$dir/home/go/bin/limonatad" "$dir/original"
    cat > "$dir/update/limonatad" <<'SH'
#!/bin/sh
case "${STAGED_VERSION_MODE:-good}" in
    fail) exit 33 ;;
    wrong) echo v0.3.5 ;;
    *) echo v0.3.6 ;;
esac
SH
    chmod 0755 "$dir/update/limonatad"
    cat > "$dir/mock/sudo" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$MOCK_LOG"
case "$*" in
    "systemctl stop limonatad") exit 0 ;;
    "systemctl daemon-reload") [ "${FAIL_DAEMON_RELOAD:-0}" != 1 ] ;;
    "systemctl restart limonatad")
        if [ "${FAIL_ALL_RESTART:-0}" = 1 ]; then exit 1; fi
        if [ "${FAIL_FIRST_RESTART:-0}" = 1 ] && [ ! -e "$MOCK_DIR/restart-failed" ]; then
            : > "$MOCK_DIR/restart-failed"; exit 1
        fi
        exit 0 ;;
    *) echo "Unexpected sudo invocation" >&2; exit 98 ;;
esac
SH
    cat > "$dir/mock/systemctl" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$MOCK_LOG"
if [ "$*" = "is-active --quiet limonatad" ]; then
    if [ "${FAIL_FIRST_ACTIVE:-0}" = 1 ] && [ ! -e "$MOCK_DIR/active-failed" ]; then
        : > "$MOCK_DIR/active-failed"; exit 1
    fi
    exit 0
fi
echo "Unexpected systemctl invocation" >&2
exit 98
SH
    cat > "$dir/mock/install" <<'SH'
#!/usr/bin/env bash
if [ "${FAIL_FIRST_INSTALL:-0}" = 1 ] && [ ! -e "$MOCK_DIR/install-failed" ]; then
    : > "$MOCK_DIR/install-failed"; exit 1
fi
if [ "${FAIL_SECOND_INSTALL:-0}" = 1 ]; then
    if [ -e "$MOCK_DIR/install-first-done" ]; then exit 1; fi
    : > "$MOCK_DIR/install-first-done"
fi
exec /usr/bin/install "$@"
SH
    chmod 0755 "$dir/mock/"*

    (
        export HOME="$dir/home" PATH="$dir/mock:$PATH" MOCK_DIR="$dir" MOCK_LOG="$dir/log"
        export legacy_binary="$dir/home/go/bin/limonatad" UPDATE_TMP="$dir/update"
        export BACKUP_BINARY="$dir/update/limonatad.previous" LIMONATA_HOME="$dir/home/.limonatad"
        export LIMONATA_SERVICE_NAME=limonatad
        case "$scenario" in
            version-exit) export STAGED_VERSION_MODE=fail ;;
            version-wrong) export STAGED_VERSION_MODE=wrong ;;
            install-error) export FAIL_FIRST_INSTALL=1 ;;
            daemon-error) export FAIL_DAEMON_RELOAD=1 ;;
            restart-error) export FAIL_FIRST_RESTART=1 ;;
            inactive-error) export FAIL_FIRST_ACTIVE=1 ;;
            restore-error) export STAGED_VERSION_MODE=fail FAIL_SECOND_INSTALL=1 ;;
            rollback-restart-error) export FAIL_ALL_RESTART=1 ;;
            success) : ;;
            *) exit 2 ;;
        esac
        bash "$tmp/post-stop-under-test.sh"
    ) > "$dir/output" 2>&1 || rc=$?

    if [ "$scenario" = success ]; then
        [ "$rc" -eq 0 ] || { cat "$dir/output"; exit 1; }
        grep -Fq 'echo v0.3.6' "$dir/home/go/bin/limonatad" || { echo "Target not installed"; exit 1; }
    else
        [ "$rc" -ne 0 ] || { echo "False success: $scenario"; exit 1; }
        if [ "$scenario" = restore-error ] || [ "$scenario" = rollback-restart-error ]; then
            grep -Fq 'CRITICAL: Rollback incomplete' "$dir/output" || { cat "$dir/output"; exit 1; }
            grep -Fq 'Original binary backup retained for manual recovery' "$dir/output" || {
                cat "$dir/output"; exit 1;
            }
            cmp -s "$dir/original" "$dir/update/limonatad.previous" || {
                echo "Recovery backup lost: $scenario"; exit 1;
            }
        else
            cmp -s "$dir/original" "$dir/home/go/bin/limonatad" || {
                echo "Previous binary not restored: $scenario"; exit 1;
            }
            [ ! -e "$dir/update" ] || {
                echo "Temporary update files not cleaned: $scenario"; exit 1;
            }
        fi
    fi
    actual_restarts=$(grep -c '^systemctl restart limonatad$' "$dir/log" || true)
    [ "$actual_restarts" -eq "$expected_restarts" ] || {
        echo "Unexpected restart count: $scenario $actual_restarts"; cat "$dir/log"; exit 1;
    }
    echo "PASS: $scenario"
}

run_case success 1
run_case version-exit 1
run_case version-wrong 1
run_case install-error 1
run_case daemon-error 1
run_case restart-error 2
run_case inactive-error 2
run_case restore-error 0
run_case rollback-restart-error 2
echo "PASS: 9 sandbox-only legacy updater rollback scenarios"
