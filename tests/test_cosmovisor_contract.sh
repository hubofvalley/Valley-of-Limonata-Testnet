#!/bin/bash

set -euo pipefail

installer="resources/limonata_node_install_testnet.sh"
updater="resources/limonata_update.sh"
versions="VERSIONS.json"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

[ -f "$installer" ] || fail "installer missing"
[ -f "$updater" ] || fail "updater missing"
[ -f "$versions" ] || fail "VERSIONS.json missing"

grep -Fq 'readonly LIMONATA_RELEASE="limonata-v0.3.6"' "$installer" || fail "installer is not pinned to v0.3.6"
grep -Fq 'readonly LIMONATA_RELEASE_COMMIT="effa377d673fc6f0fb307a78ca54e037e53060f7"' "$installer" || fail "release commit is not pinned"
grep -Fq 'readonly LIMONATA_ARTIFACT_SHA256="39ff376963498de120604c273d50751afc005ebeec9cbcca88c0f732eff56125"' "$installer" || fail "artifact SHA256 is not pinned"
grep -Fq 'readonly LIMONATA_SIGNING_KEY_FINGERPRINT="A45380198F390AF69126AE12E4ECEC477C1735FB"' "$installer" || fail "signing key fingerprint is not pinned"
grep -Fq 'readonly COSMOVISOR_VERSION="v1.7.1"' "$installer" || fail "Cosmovisor version is not pinned"
grep -Fq 'readonly GO_VERSION="1.26.5"' "$installer" || fail "installer Go toolchain is not pinned"

if grep -Fq '/releases/latest/' "$installer"; then
    fail "fresh installer must not select a mutable latest release"
fi

grep -Fq '"$COSMOVISOR_BIN" init /usr/local/bin/limonatad' "$installer" || fail "Cosmovisor genesis init missing"
grep -Fq 'Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"' "$installer" || fail "Cosmovisor auto-download must be disabled"
grep -Fq 'Environment="DAEMON_DOWNLOAD_MUST_HAVE_CHECKSUM=true"' "$installer" || fail "Cosmovisor checksum policy missing"
grep -Fq 'ExecStart=$COSMOVISOR_BIN run start' "$installer" || fail "systemd does not start through Cosmovisor"

for upgrade_name in \
    valgrant-v1 \
    encmempool-threshold-vpcap-v1 \
    gassponsor-security-caps-v1 \
    encmempool-transparent-dkg-v1 \
    encmempool-dkg-dealing-retention-v1 \
    encmempool-strict-concentration-v1; do
    grep -Fq "\"${upgrade_name}\"" "$installer" || fail "missing historical upgrade slot: ${upgrade_name}"
done

jq -e '.components.validator.consensus.version_current == "limonata-v0.3.6"' "$versions" >/dev/null || fail "VERSIONS target mismatch"
jq -e '.components.validator.consensus.release_commit == "effa377d673fc6f0fb307a78ca54e037e53060f7"' "$versions" >/dev/null || fail "VERSIONS commit mismatch"
jq -e '.components.validator.consensus.artifact_sha256 == "39ff376963498de120604c273d50751afc005ebeec9cbcca88c0f732eff56125"' "$versions" >/dev/null || fail "VERSIONS artifact digest mismatch"
jq -e '.components.validator.consensus.signature.fingerprint == "A45380198F390AF69126AE12E4ECEC477C1735FB"' "$versions" >/dev/null || fail "VERSIONS signing fingerprint mismatch"
jq -e '.components.validator.cosmovisor.used == true' "$versions" >/dev/null || fail "VERSIONS Cosmovisor flag mismatch"
jq -e '.components.validator.cosmovisor.allow_download_binaries == false' "$versions" >/dev/null || fail "VERSIONS must disable Cosmovisor downloads"
jq -e '.components.validator.upgrade.consensus_breaking == true' "$versions" >/dev/null || fail "coordinated upgrade semantics missing"
jq -e '.components.validator.upgrade.state_breaking == "not_asserted_by_upstream_release"' "$versions" >/dev/null || fail "state-breaking claim must remain non-asserted"

grep -Fq 'This node is managed by Cosmovisor.' "$updater" || fail "updater lacks Cosmovisor guard"
grep -Fq 'Refusing a direct binary replacement on a Cosmovisor-managed node.' "$updater" || fail "updater can directly replace Cosmovisor current binary"

echo "Cosmovisor v0.3.6 contract checks passed."
