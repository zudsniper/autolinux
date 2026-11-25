# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
MOD_DESC="ckb-next (Corsair keyboard/mouse driver, PPA)"
MOD_GROUP="hardware"
MOD_PROFILES="full"
mod_detect() { is_package_installed ckb-next; }
mod_install() {
    # Launchpad PPAs (and add-apt-repository) are Ubuntu-only.
    require_ubuntu || { log_error "ckb-next uses an Ubuntu PPA; install it manually on this distro"; return 1; }
    apt_install software-properties-common || return 1
    if ! is_repository_added "tatokis/ckb-next"; then
        run_or_dry add-apt-repository -y ppa:tatokis/ckb-next || return 1
        rm -f "$(_apt_stamp)"
    fi
    apt_install ckb-next
}
