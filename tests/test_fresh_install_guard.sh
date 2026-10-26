#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
installer="$root/resources/limonata_node_install_testnet.sh"
wrapper="$root/resources/valleyofLimonata.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Exercise the real preflight function with a fake systemctl; no node or service
# is started, deleted, or modified by these tests.
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/home/go/bin" "$tmp/fake-bin"
awk '/^guard_fresh_limonata_install\(\) \{$/{inside=1} inside {print} inside && /^}$/{exit}' "$installer" > "$tmp/guard.sh"
grep -Fq 'guard_fresh_limonata_install() {' "$tmp/guard.sh" || fail "missing guard"
# shellcheck disable=SC1091
source "$tmp/guard.sh"
cat > "$tmp/fake-bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
[ "$MOCK_LOAD_STATE" != "ERROR" ] || exit 1
printf '%s\n' "$MOCK_LOAD_STATE"
MOCK
cat > "$tmp/fake-bin/sudo" <<'MOCK'
#!/usr/bin/env bash
printf 'unexpected sudo call\n' >> "$MOCK_SUDO_LOG"
exit 99
MOCK
chmod +x "$tmp/fake-bin/systemctl" "$tmp/fake-bin/sudo"
export HOME="$tmp/home" LIMONATA_SERVICE_NAME="limonatad"
LIMONATA_BIN="$HOME/go/bin/limonatad"
export MOCK_LOAD_STATE=not-found MOCK_SUDO_LOG="$tmp/sudo.log"
export PATH="$tmp/fake-bin:$PATH"

allowed() { guard_fresh_limonata_install || fail "$1 should allow a fresh install"; }
refused() { if guard_fresh_limonata_install > /dev/null 2>&1; then fail "$1 should refuse"; fi; }

allowed "empty home / no unit"
mkdir -p "$HOME/.limonatad"
refused "existing node home"
LIMONATA_REDEPLOY_CONFIRMED=1 refused "legacy override must not bypass existing home"
rmdir "$HOME/.limonatad"

ln -s "$tmp/absent-target" "$HOME/.limonatad"
refused "dangling home symlink"
rm "$HOME/.limonatad"

: > "$LIMONATA_BIN"
refused "existing operator binary"
rm "$LIMONATA_BIN"
ln -s "$tmp/absent-binary" "$LIMONATA_BIN"
refused "dangling binary symlink"
rm "$LIMONATA_BIN"

MOCK_LOAD_STATE=loaded refused "loaded service"
MOCK_LOAD_STATE=masked refused "masked service"
MOCK_LOAD_STATE=ERROR refused "systemd error"
MOCK_LOAD_STATE=not-found allowed "fresh installation after negative cases"

# Full installer integration: an existing home must exit before package, sudo,
# systemd mutation, binary creation, or any irreversible operation.
mkdir -p "$HOME/.limonatad"
set +e
printf 'test\n26\ny\ny\nn\np\nn\nlimonatad\n' | \
    LIMONATA_REDEPLOY_CONFIRMED=1 bash "$installer" > "$tmp/full-output" 2>&1
code=$?
set -e
[ "$code" -ne 0 ] || fail "full installer accepted existing home"
grep -Fq 'REFUSED: existing node' "$tmp/full-output" || fail "installer did not reject before mutation"
[ ! -e "$MOCK_SUDO_LOG" ] || fail "installer called sudo despite existing home"
[ -d "$HOME/.limonatad" ] || fail "installer removed existing home"

grep -Fq 'if ! guard_fresh_limonata_install; then' "$installer" || fail "missing pre-write guard"
if grep -Fq 'sudo rm -rf "$HOME/.limonatad"' "$installer"; then fail "destructive home deletion remains"; fi
if grep -Fq 'LIMONATA_REDEPLOY_CONFIRMED' "$installer"; then fail "redeploy bypass remains"; fi
if grep -Fq 'LIMONATA_REDEPLOY_CONFIRMED' "$wrapper"; then fail "wrapper still passes bypass"; fi
if grep -Fq 'Type REDEPLOY' "$wrapper"; then fail "wrapper still offers destructive redeploy"; fi
echo "Fresh-install fail-closed regression tests passed."
