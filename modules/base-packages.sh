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

# Names apt doesn't know on this distro are skipped by mod_install, so ignore
# them here too; otherwise the module never reads as installed.
_known_pkgs() {
    local p
    for p in "${PKGS[@]}"; do apt-cache show "$p" >/dev/null 2>&1 && echo "$p"; done
}
mod_detect() {
    _load_pkgs 2>/dev/null || return 1
    local known
    mapfile -t known < <(_known_pkgs)
    [ "${#known[@]}" -gt 0 ] || return 1   # no apt lists yet: don't claim installed
    all_packages_installed "${known[@]}"
}

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
