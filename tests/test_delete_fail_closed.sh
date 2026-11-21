#!/bin/bash
set -euo pipefail

wrapper="resources/valleyofLimonata.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Extract only this function; never source the interactive wrapper itself.
awk '/^function delete_limonata_node\(\) \{/{found=1} found{print} found && /^\}/{exit}' "$wrapper" > "$tmp/delete_function.sh"
grep -Fq 'function delete_limonata_node()' "$tmp/delete_function.sh"
if grep -Fq 'sudo rm -f /usr/local/bin/limonatad' "$tmp/delete_function.sh"; then
    echo "Unmanaged global binary must not be deleted" >&2
    exit 1
fi
source "$tmp/delete_function.sh"

mkdir -p "$tmp/fake-bin"
cat > "$tmp/fake-bin/sudo" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$TEST_SUDO_LOG"
if [ "$1" = "systemctl" ]; then
    case "$2" in
        stop) exit "$TEST_STOP_RC" ;;
        disable) exit "$TEST_DISABLE_RC" ;;
        daemon-reload) exit "$TEST_RELOAD_RC" ;;
        show)
            [ "$TEST_SHOW_RC" -eq 0 ] || exit "$TEST_SHOW_RC"
            printf '%s\n' "$TEST_ACTIVE_STATE"
            exit 0
            ;;
    esac
fi
if [ "$1" = "rm" ] && [ "$2" = "-f" ]; then
    exit "$TEST_UNIT_RC"
fi
exit 0
EOF
chmod +x "$tmp/fake-bin/sudo"

menu() { :; }
require_standard_limonata_home() { [ "$LIMONATA_HOME" = "$HOME/.limonatad" ]; }
RED= YELLOW= GREEN= RESET=

run_case() {
    local name=$1 stop_rc=$2 disable_rc=$3 show_rc=$4 state=$5 unit_rc=$6 reload_rc=$7 allowed=$8
    local root="$tmp/$name"
    mkdir -p "$root/home/.limonatad/config" "$root/home/go/bin"
    printf 'preserve\n' > "$root/home/.limonatad/marker"
    printf 'synthetic binary\n' > "$root/home/go/bin/limonatad"
    printf 'export LIMONATA_TEST=1\n' > "$root/home/.bash_profile"
    : > "$root/sudo.log"

    printf 'DELETE\n' | (
        export HOME="$root/home" LIMONATA_HOME="$root/home/.limonatad"
        export LIMONATA_SERVICE_NAME="test-limonatad"
        export TEST_SUDO_LOG="$root/sudo.log" TEST_STOP_RC="$stop_rc"
        export TEST_DISABLE_RC="$disable_rc" TEST_SHOW_RC="$show_rc"
        export TEST_UNIT_RC="$unit_rc" TEST_RELOAD_RC="$reload_rc"
        export TEST_ACTIVE_STATE="$state" PATH="$tmp/fake-bin:$PATH"
        delete_limonata_node
    ) > "$root/output" 2>&1
    if grep -Fq '/usr/local/bin/limonatad' "$root/sudo.log"; then
        echo "$name: attempted to remove unmanaged global binary" >&2
        exit 1
    fi

    if [ "$allowed" = "yes" ]; then
        grep -Fq 'rm -rf ' "$root/sudo.log" || { echo "$name: expected deletion path not reached" >&2; exit 1; }
        [ ! -e "$root/home/go/bin/limonatad" ] || { echo "$name: local link not removed" >&2; exit 1; }
    else
        if grep -Fq 'rm -rf ' "$root/sudo.log"; then
            echo "$name: attempted destructive cleanup after unsafe service result" >&2
            exit 1
        fi
        [ -f "$root/home/.limonatad/marker" ] || { echo "$name: node files changed" >&2; exit 1; }
        [ -f "$root/home/go/bin/limonatad" ] || { echo "$name: binary path changed" >&2; exit 1; }
        grep -Eq 'Refusing (deletion|node-data deletion):' "$root/output" || { echo "$name: refusal not reported" >&2; exit 1; }
    fi
}

run_case stop_error 1 0 0 inactive 0 0 no
run_case disable_error 0 1 0 inactive 0 0 no
run_case show_error 0 0 1 inactive 0 0 no
run_case active 0 0 0 active 0 0 no
run_case unknown 0 0 0 unknown 0 0 no
run_case unit_error 0 0 0 inactive 1 0 no
run_case reload_error 0 0 0 inactive 0 1 no
run_case inactive 0 0 0 inactive 0 0 yes

echo "Delete fail-closed regression checks passed."
