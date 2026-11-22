#!/bin/bash
# Tests for lib/modules.sh (registry, selection, runner) and module contracts.
# Pure bash; no root needed; nothing is installed.
#
# Usage: ./tests/modules.sh   (exit 0 = all passed)

set -u
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0 FAIL=0

_ok()   { PASS=$((PASS+1)); printf '  \033[0;32m✓\033[0m %s\n' "$1"; }
_bad()  { FAIL=$((FAIL+1)); printf '  \033[0;31m✗\033[0m %s\n' "$1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; }
_assert() { if [ "$2" = "$3" ]; then _ok "$1"; else _bad "$1" "expected '$3', got '$2'"; fi; }
_contains() { case " $2 " in *" $3 "*) _ok "$1" ;; *) _bad "$1" "'$3' not in: $2" ;; esac; }
_lacks()    { case " $2 " in *" $3 "*) _bad "$1" "'$3' unexpectedly in: $2" ;; *) _ok "$1" ;; esac; }

export NO_COLOR=1 AUTOLINUX_REPO_DIR="$REPO_DIR"
source "$REPO_DIR/lib/log.sh"
source "$REPO_DIR/lib/detect.sh"
source "$REPO_DIR/lib/safety.sh"
source "$REPO_DIR/lib/modules.sh"

echo "==> every module in MODULE_ORDER has a well-formed file"
for m in "${MODULE_ORDER[@]}"; do
    f="$REPO_DIR/modules/$m.sh"
    if [ ! -r "$f" ]; then _bad "$m: file exists"; continue; fi
    out="$(bash -n "$f" 2>&1)" || { _bad "$m: syntax" "$out"; continue; }
    if (
        source "$f"
        [ -n "${MOD_DESC:-}" ] && [ -n "${MOD_GROUP:-}" ] \
            && declare -F mod_detect >/dev/null && declare -F mod_install >/dev/null
    ); then _ok "$m: metadata + mod_detect + mod_install"; else _bad "$m: contract"; fi
done

echo
echo "==> no orphan module files"
for f in "$REPO_DIR"/modules/*.sh; do
    n="$(basename "$f" .sh)"
    if module_exists "$n"; then _ok "$n is registered"; else _bad "$n is not in MODULE_ORDER"; fi
done

echo
echo "==> dependencies exist and run earlier"
modules_load_meta
for m in "${MODULE_ORDER[@]}"; do
    for d in ${MOD_META_DEPENDS[$m]}; do
        module_exists "$d" || { _bad "$m depends on unknown '$d'"; continue; }
        mi=-1 di=-1
        for i in "${!MODULE_ORDER[@]}"; do
            [ "${MODULE_ORDER[$i]}" = "$m" ] && mi=$i
            [ "${MODULE_ORDER[$i]}" = "$d" ] && di=$i
        done
        if [ "$di" -lt "$mi" ]; then _ok "$d runs before $m"; else _bad "$d must come before $m in MODULE_ORDER"; fi
    done
done

echo
echo "==> selection"
modules_select full "" "" "" 0
sel="${MODULES_SELECTED[*]}"
_contains "full profile includes ringboard" "$sel" ringboard
_contains "full profile includes steam" "$sel" steam
_lacks    "full profile excludes opt-in portainer" "$sel" portainer

modules_select minimal "" "" "" 0
sel="${MODULES_SELECTED[*]}"
_contains "minimal includes kitty" "$sel" kitty
_lacks    "minimal excludes steam" "$sel" steam

modules_select full "" "" "steam,obs" 0
sel="${MODULES_SELECTED[*]}"
_lacks "--without steam,obs removes steam" "$sel" steam
_lacks "--without steam,obs removes obs" "$sel" obs

modules_select full "" "" "hardware" 0
sel="${MODULES_SELECTED[*]}"
_lacks "--without <group> removes ckb-next" "$sel" ckb-next

modules_select full "ringboard" "" "" 0 2>/dev/null
_assert "--only ringboard pulls in rust first" "${MODULES_SELECTED[*]}" "rust ringboard"

modules_select full "" "portainer" "docker" 0 2>/dev/null
sel="${MODULES_SELECTED[*]}"
_contains "dependency re-added even if --without'd" "$sel" docker

if modules_select full "" "nope-not-a-module" "" 0 2>/dev/null; then
    _bad "unknown module name is rejected"
else
    _ok "unknown module name is rejected"
fi

echo
echo "==> runner: dry-run never calls mod_install"
FAKE="$(mktemp -d)"
trap 'rm -rf "$FAKE"' EXIT
mkdir -p "$FAKE/modules"
cat > "$FAKE/modules/fake.sh" <<EOF
MOD_DESC="fake"; MOD_GROUP="core"; MOD_PROFILES="full"
mod_detect()  { return 1; }
mod_install() { touch "$FAKE/installed"; }
EOF
(
    AUTOLINUX_REPO_DIR="$FAKE" AUTOLINUX_LOG_DIR="$FAKE/log" AUTOLINUX_DRY_RUN=1
    MODULE_ORDER=(fake); MOD_META_DESC=([fake]=fake)
    MODULES_SELECTED=(fake)
    modules_run >/dev/null 2>&1
)
if [ -e "$FAKE/installed" ]; then _bad "dry-run did not install"; else _ok "dry-run did not install"; fi

(
    AUTOLINUX_REPO_DIR="$FAKE" AUTOLINUX_LOG_DIR="$FAKE/log" AUTOLINUX_DRY_RUN=0
    MODULE_ORDER=(fake); MOD_META_DESC=([fake]=fake)
    MODULES_SELECTED=(fake)
    modules_run >/dev/null 2>&1
)
if [ -e "$FAKE/installed" ]; then _ok "real run calls mod_install"; else _bad "real run calls mod_install"; fi
if grep -q "FAILED fake" "$FAKE/log/modules-status.txt" 2>/dev/null; then
    _ok "module whose detect still fails after install is reported FAILED"
else
    _bad "post-install detect failure reported"
fi

echo
echo "==> stage filters"
AUTOLINUX_MODULES="rust ringboard desktop-settings gnome-extensions steam"
_assert "apps filter drops desktop-settings/gnome-extensions" "$(_stage_modules apps)" "rust ringboard steam"
_assert "single-module filter" "$(_stage_modules gnome-extensions)" "gnome-extensions"
AUTOLINUX_MODULES="rust"
_assert "unselected single module is empty" "$(_stage_modules gnome-extensions)" ""

echo
echo "==> no forced X11"
if grep -rqE '^\s*WaylandEnable\s*=\s*false' "$REPO_DIR"/*.sh "$REPO_DIR"/stages "$REPO_DIR"/modules "$REPO_DIR"/lib; then
    _bad "nothing writes WaylandEnable=false"
else
    _ok "nothing writes WaylandEnable=false"
fi

echo
echo "==> CLI"
if "$REPO_DIR/install.sh" --list-modules >/dev/null 2>&1; then _ok "install.sh --list-modules"; else _bad "install.sh --list-modules"; fi
if "$REPO_DIR/install.sh" --help >/dev/null 2>&1; then _ok "install.sh --help"; else _bad "install.sh --help"; fi
if "$REPO_DIR/install.sh" --bogus >/dev/null 2>&1; then _bad "unknown flag rejected"; else _ok "unknown flag rejected"; fi

echo
echo "----------------------------------------"
echo "passed: $PASS"
echo "failed: $FAIL"
[ "$FAIL" -eq 0 ]
