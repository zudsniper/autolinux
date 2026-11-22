# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
# The package list lives in apt-packages.txt at the repo root (one name per
# line) and is read at run time. Override with AUTOLINUX_APT_PACKAGES=<file>.
MOD_DESC="Base apt packages listed in apt-packages.txt"
MOD_GROUP="core"
MOD_PROFILES="minimal full"

_apt_list() { echo "${AUTOLINUX_APT_PACKAGES:-$AUTOLINUX_REPO_DIR/apt-packages.txt}"; }

_load_pkgs() {
    mapfile -t PKGS < <(read_package_list "$(_apt_list)")
    [ "${#PKGS[@]}" -gt 0 ] || { log_error "no packages in $(_apt_list)"; return 1; }
}

mod_detect() { _load_pkgs 2>/dev/null && all_packages_installed "${PKGS[@]}"; }

mod_install() {
    _load_pkgs || return 1
    apt_update_once
    # One bad or renamed line shouldn't sink the whole batch: skip names apt
    # doesn't know and report them.
    local p ok=() unknown=()
    for p in "${PKGS[@]}"; do
        if apt-cache show "$p" >/dev/null 2>&1; then ok+=("$p"); else unknown+=("$p"); fi
    done
    [ "${#unknown[@]}" -eq 0 ] || log_warning "not in apt, skipped: ${unknown[*]} (check $(_apt_list))"
    [ "${#ok[@]}" -eq 0 ] || apt_install "${ok[@]}"
}
