#!/bin/bash

set -euo pipefail

wrapper="resources/valleyofLimonata.sh"
installer="resources/limonata_node_install_testnet.sh"
updater="resources/limonata_update.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

[ -f "$wrapper" ] || fail "wrapper missing"
[ -f "$installer" ] || fail "installer missing"
[ -f "$updater" ] || fail "updater missing"

installer_sha=$(sha256sum "$installer" | awk '{print $1}')
updater_sha=$(sha256sum "$updater" | awk '{print $1}')
grep -Fq "readonly VALLEY_INSTALLER_SHA256=\"${installer_sha}\"" "$wrapper" || fail "wrapper installer SHA pin mismatch"
grep -Fq "readonly VALLEY_UPDATER_SHA256=\"${updater_sha}\"" "$wrapper" || fail "wrapper updater SHA pin mismatch"
grep -Fq 'sha256sum "$child_path"' "$wrapper" || fail "wrapper does not hash child scripts before execution"
grep -Fq 'Valley child script integrity check failed. Refusing execution.' "$wrapper" || fail "wrapper lacks fail-closed child integrity guard"
grep -Fq 'readonly VALLEY_SCRIPT_COMMIT="d4b100bb926b6fd0392c29b0bc0ae61dcb21468f"' "$wrapper" || fail "wrapper child commit is not immutable"
grep -Fq 'curl -fsSL "${VALLEY_SCRIPT_BASE}/${script_name}"' "$wrapper" || fail "remote child download is not fail-closed"

if grep -RIEq 'raw\.githubusercontent\.com/.*/main|/releases/latest/' README.md docs resources; then
    fail "mutable main/latest executable or documentation URL remains"
fi
grep -Fq 'bash <(curl -fsSL' README.md || fail "README run command must remain bash process substitution"
grep -Fq 'bash <(curl -fsSL' docs/usage.md || fail "usage run command must remain bash process substitution"
if grep -R -Fq '/COMMIT/' README.md docs/usage.md; then
    fail "documentation contains an unresolved wrapper commit placeholder"
fi

grep -Fq 'readonly LIMONATA_RELEASE="limonata-v0.3.6"' "$updater" || fail "legacy updater release is not pinned"
grep -Fq 'readonly LIMONATA_ARTIFACT_SHA256="39ff376963498de120604c273d50751afc005ebeec9cbcca88c0f732eff56125"' "$updater" || fail "legacy updater artifact SHA is not pinned"
grep -Fq 'readonly LIMONATA_SIGNING_KEY_FINGERPRINT="A45380198F390AF69126AE12E4ECEC477C1735FB"' "$updater" || fail "legacy updater signing fingerprint is not pinned"
grep -Fq 'SHA256SUMS.txt.asc' "$updater" || fail "legacy updater does not download signed checksum"
grep -Fq 'gpg --batch --homedir "$GNUPG_HOME" --verify' "$updater" || fail "legacy updater does not verify checksum signature"
grep -Fq 'Pinned artifact SHA256 mismatch. Refusing update.' "$updater" || fail "legacy updater lacks pinned artifact fail-closed check"
grep -Fq 'This installer supports Linux x86_64 (AMD64) only.' "$installer" || fail "installer lacks architecture preflight"
grep -Fq 'GOBIN="$build_bin_dir"' "$installer" || fail "source build does not isolate its output"
grep -Fq 'built_binary="$build_bin_dir/evmd"' "$installer" || fail "source build does not stage upstream evmd output"
grep -Fq "printf 'export LIMONATA_MONIKER=%q\\n'" "$installer" || fail "moniker is not shell-safe when persisted"

tmp=$(mktemp -d)
cleanup() {
    rm -rf "$tmp"
}
trap cleanup EXIT

# Environment/profile service names must be rejected before the interactive menu
# can reach node/service operations.
mkdir -p "$tmp/home"
: > "$tmp/home/.bash_profile"
set +e
printf '\n' | HOME="$tmp/home" LIMONATA_SERVICE_NAME='bad/name' bash "$wrapper" >"$tmp/wrapper-env.out" 2>&1
status=$?
set -e
[ "$status" -ne 0 ] || fail "wrapper accepted invalid service name from environment"
grep -Fq 'Invalid service name loaded from environment/profile' "$tmp/wrapper-env.out" || fail "wrapper did not report environment/profile service-name rejection"

printf '%s\n' 'export LIMONATA_SERVICE_NAME="bad/name"' > "$tmp/home/.bash_profile"
set +e
printf '\n' | env -u LIMONATA_SERVICE_NAME HOME="$tmp/home" bash "$wrapper" >"$tmp/wrapper-profile.out" 2>&1
status=$?
set -e
[ "$status" -ne 0 ] || fail "wrapper accepted invalid service name from profile"
grep -Fq 'Invalid service name loaded from environment/profile' "$tmp/wrapper-profile.out" || fail "wrapper did not report profile service-name rejection"

# A failed reviewed-release download must exit before any sudo/systemctl action.
mkdir -p "$tmp/update-home/go/bin" "$tmp/fake-bin"
: > "$tmp/update-home/.bash_profile"
cat > "$tmp/update-home/go/bin/limonatad" <<'EOF'
#!/bin/bash
echo "v0.3.5"
EOF
chmod +x "$tmp/update-home/go/bin/limonatad"
cat > "$tmp/fake-bin/curl" <<'EOF'
#!/bin/bash
exit 22
EOF
cat > "$tmp/fake-bin/sudo" <<EOF
#!/bin/bash
echo invoked >> "$tmp/sudo-called"
exit 99
EOF
chmod +x "$tmp/fake-bin/curl" "$tmp/fake-bin/sudo"

set +e
printf 'yes\n' | HOME="$tmp/update-home" PATH="$tmp/fake-bin:$PATH" bash "$updater" >"$tmp/update-download.out" 2>&1
status=$?
set -e
[ "$status" -ne 0 ] || fail "legacy updater succeeded despite failed release download"
[ ! -e "$tmp/sudo-called" ] || fail "legacy updater touched sudo/systemctl after failed release download"

echo "Operator hardening contract checks passed."
