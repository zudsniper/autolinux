#!/bin/bash
# Self-contained tests for lib/state.sh and lib/safety.sh helpers.
# Pure bash + jq; no bats dependency.
#
# Usage: ./tests/state-machine.sh
#   exit 0 = all passed; nonzero = failures

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0
FAILED_TESTS=()

_assert() {
    local desc="$1" actual="$2" expected="$3"
    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS+1))
        printf '  \033[0;32m✓\033[0m %s\n' "$desc"
    else
        FAIL=$((FAIL+1))
        FAILED_TESTS+=("$desc")
        printf '  \033[0;31m✗\033[0m %s\n' "$desc"
        printf '      expected: %q\n' "$expected"
        printf '      actual  : %q\n' "$actual"
    fi
}

_assert_true() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        PASS=$((PASS+1))
        printf '  \033[0;32m✓\033[0m %s\n' "$desc"
    else
        FAIL=$((FAIL+1))
        FAILED_TESTS+=("$desc")
        printf '  \033[0;31m✗\033[0m %s\n  cmd failed: %s\n' "$desc" "$*"
    fi
}

_assert_false() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        FAIL=$((FAIL+1))
        FAILED_TESTS+=("$desc")
        printf '  \033[0;31m✗\033[0m %s\n  cmd unexpectedly succeeded: %s\n' "$desc" "$*"
    else
        PASS=$((PASS+1))
        printf '  \033[0;32m✓\033[0m %s\n' "$desc"
    fi
}

# Use a scratch dir so tests don't touch /var/lib/autolinux.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export AUTOLINUX_STATE_DIR="$TMP"

# Source the libs (in order, dependencies first).
# shellcheck source=../lib/log.sh
source "$REPO_DIR/lib/log.sh"
# shellcheck source=../lib/state.sh
source "$REPO_DIR/lib/state.sh"
# shellcheck source=../lib/detect.sh
source "$REPO_DIR/lib/detect.sh"

command -v jq >/dev/null 2>&1 || { echo "jq not installed — skipping tests"; exit 0; }

echo "==> state.sh: initialization & basic getters/setters"
_assert "no state file before init"          "$(test -f "$AUTOLINUX_STATE_FILE" && echo y || echo n)" "n"
state_init
_assert_true "state file exists after init"  test -f "$AUTOLINUX_STATE_FILE"
_assert_true "state file is valid JSON"      jq -e . < "$AUTOLINUX_STATE_FILE"
_assert "version field"                       "$(state_get version)" "1"
_assert "starting status"                     "$(state_get status)" "in_progress"

state_set custom_field "hello"
_assert "set/get round-trip"                  "$(state_get custom_field)" "hello"

echo
echo "==> state.sh: stage transitions"
_assert "missing stage status is empty"       "$(state_stage_status 'fake-stage')" ""
state_stage_set "00-preflight" "running"
_assert "stage running"                       "$(state_stage_status '00-preflight')" "running"
state_stage_set "00-preflight" "done"
_assert "stage done"                          "$(state_stage_status '00-preflight')" "done"
_assert "current_stage tracked"               "$(state_get current_stage)" "00-preflight"

state_stage_meta "01-timeshift-snapshot" "snapshot" "tag-xyz"
_assert "stage meta key written"              "$(jq -r '.stages."01-timeshift-snapshot".snapshot' < "$AUTOLINUX_STATE_FILE")" "tag-xyz"

echo
echo "==> state.sh: array append + replace + dedupe"
state_array_append holds_added "ubuntu-desktop"
state_array_append holds_added "gdm3"
state_array_append holds_added "ubuntu-desktop"   # duplicate, should dedupe
_assert "array length after dedupe"           "$(jq '.holds_added | length' < "$AUTOLINUX_STATE_FILE")" "2"

state_array_replace holds_added "linux-generic"
_assert "array replace yields 1 item"         "$(jq '.holds_added | length' < "$AUTOLINUX_STATE_FILE")" "1"
_assert "array replace content"               "$(jq -r '.holds_added[0]' < "$AUTOLINUX_STATE_FILE")" "linux-generic"

echo
echo "==> state.sh: malformed JSON recovery"
echo "this is not json" > "$AUTOLINUX_STATE_FILE"
state_init  # should rebuild
_assert "rebuilt after corruption"            "$(state_get version)" "1"

echo
echo "==> state.sh: atomic write rejects malformed payloads"
# Force a bad write: pipe garbage straight through _state_atomic_write.
( echo "garbage" | _state_atomic_write 2>&1 ) >/dev/null
# state.json should still be the last-good content (still version=1).
_assert "post-bad-write file still parses"    "$(jq -r '.version' < "$AUTOLINUX_STATE_FILE")" "1"

echo
echo "==> state.sh: state_dump on empty file"
rm -f "$AUTOLINUX_STATE_FILE"
out="$(state_dump)"
_assert "empty dump message"                  "$out" "(no state.json yet — first run)"

echo
echo "==> detect.sh: real_user / is_package_installed"
u="$(real_user)"
_assert_true "real_user nonempty"             test -n "$u"
_assert_true "real_user is real"              getent passwd "$u"
_assert_true "is_package_installed bash"      is_package_installed bash
_assert_false "is_package_installed nonexistent-pkg" is_package_installed this-package-does-not-exist-zzz

echo
echo "==> detect.sh: is_repository_added matches grep semantics"
# At least the ubuntu archive should match.
_assert_true "ubuntu archive repo present"    is_repository_added archive.ubuntu.com

echo
echo "==> bootstrap.sh: --list-stages output"
out="$("$REPO_DIR/bootstrap.sh" --list-stages 2>/dev/null)"
_assert_true "list-stages mentions 00-preflight" grep -q "00-preflight" <<<"$out"
_assert_true "list-stages mentions 15-done"      grep -q "15-done"      <<<"$out"
_assert_true "list-stages mentions 06-arm-resume-and-reboot" grep -q "06-arm-resume-and-reboot" <<<"$out"

echo
echo "==> bootstrap.sh: --help works without root"
"$REPO_DIR/bootstrap.sh" --help >/dev/null 2>&1
_assert "help exit code"                      "$?" "0"

echo
echo "----------------------------------------"
printf "passed: \033[0;32m%d\033[0m\n" "$PASS"
printf "failed: \033[0;31m%d\033[0m\n" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
    printf "failed tests:\n"
    for t in "${FAILED_TESTS[@]}"; do
        printf "  - %s\n" "$t"
    done
    exit 1
fi
exit 0
