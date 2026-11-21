#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
installer="$root/resources/limonata_node_install_testnet.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/fake-bin" "$tmp/fixture" "$tmp/work" "$tmp/home"

# Invoke the actual installer function without fetching a real release or
# touching system directories, node homes, services, or validator state.
awk '/^install_cosmovisor\(\) \{$/{inside=1} inside {print} inside && /^}$/{exit}' "$installer" > "$tmp/function.sh"
grep -Fq 'install_cosmovisor() {' "$tmp/function.sh" || fail "missing function"
# shellcheck disable=SC1091
source "$tmp/function.sh"

cat > "$tmp/fixture/cosmovisor" <<'MOCK'
#!/bin/sh
[ "${1:-}" = "--help" ]
MOCK
chmod +x "$tmp/fixture/cosmovisor"
tar -czf "$tmp/release.tar.gz" -C "$tmp/fixture" cosmovisor

cat > "$tmp/fake-bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
while [ "$#" -gt 0 ]; do
    if [ "$1" = "-o" ]; then
        cp "$MOCK_RELEASE" "$2"
        exit 0
    fi
    shift
done
exit 1
MOCK
cat > "$tmp/fake-bin/sudo" <<'MOCK'
#!/usr/bin/env bash
printf 'UNEXPECTED SUDO\n' >> "$MOCK_SUDO_LOG"
exit 99
MOCK
chmod +x "$tmp/fake-bin/curl" "$tmp/fake-bin/sudo"

export MOCK_RELEASE="$tmp/release.tar.gz" MOCK_SUDO_LOG="$tmp/sudo.log"
export PATH="$tmp/fake-bin:$PATH"
WORKDIR="$tmp/work"
COSMOVISOR_ARTIFACT="release.tar.gz"
COSMOVISOR_VERSION="v1.7.3"
COSMOVISOR_ARTIFACT_SHA256=$(sha256sum "$MOCK_RELEASE" | awk '{print $1}')
COSMOVISOR_RELEASE_BASE="https://example.invalid/test"
COSMOVISOR_BIN="$tmp/home/.local/libexec/valley-of-limonata/cosmovisor"

install_cosmovisor >/dev/null || fail "private install failed"
cmp -s "$tmp/fixture/cosmovisor" "$COSMOVISOR_BIN" || fail "installed bytes changed"
[ -x "$COSMOVISOR_BIN" ] || fail "private binary is not executable"
[ ! -e "$MOCK_SUDO_LOG" ] || fail "private installation invoked sudo"

install_cosmovisor >/dev/null || fail "identical private binary should be reusable"

printf 'other chain binary\n' > "$COSMOVISOR_BIN"
if (install_cosmovisor >/dev/null 2>&1); then fail "mismatched binary was overwritten"; fi
grep -Fq 'other chain binary' "$COSMOVISOR_BIN" || fail "mismatched binary was mutated"

cp "$tmp/fixture/cosmovisor" "$COSMOVISOR_BIN"
chmod 0644 "$COSMOVISOR_BIN"
if (install_cosmovisor >/dev/null 2>&1); then fail "non-executable binary was accepted"; fi

rm -f "$COSMOVISOR_BIN"
ln -s "$tmp/fixture/cosmovisor" "$COSMOVISOR_BIN"
if (install_cosmovisor >/dev/null 2>&1); then fail "existing symlink was accepted"; fi
[ -L "$COSMOVISOR_BIN" ] || fail "existing symlink was modified"

rm -f "$COSMOVISOR_BIN"
ln -s "$tmp/not-present" "$COSMOVISOR_BIN"
if (install_cosmovisor >/dev/null 2>&1); then fail "dangling symlink was accepted"; fi
[ -L "$COSMOVISOR_BIN" ] || fail "dangling symlink was modified"

rm -f "$COSMOVISOR_BIN"
mkdir "$COSMOVISOR_BIN"
if (install_cosmovisor >/dev/null 2>&1); then fail "existing directory was accepted"; fi
[ -d "$COSMOVISOR_BIN" ] || fail "existing directory was modified"

[ ! -e "$MOCK_SUDO_LOG" ] || fail "test path invoked sudo"
echo "Limonata-private Cosmovisor negative-case checks passed."
