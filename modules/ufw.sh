# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
# Installed but left inactive by default, matching the reference machine:
# enabling it blocks LocalSend/RustDesk/etc. until rules are added.
# Set AUTOLINUX_UFW_ENABLE=1 to enable it with SSH allowed.
MOD_DESC="UFW firewall (installed; enabled only with AUTOLINUX_UFW_ENABLE=1)"
MOD_GROUP="security"
MOD_PROFILES="minimal full"
mod_detect() {
    is_package_installed ufw || return 1
    [ "${AUTOLINUX_UFW_ENABLE:-0}" = "1" ] || return 0
    ufw status 2>/dev/null | grep -q '^Status: active'
}
mod_install() {
    apt_install ufw || return 1
    if [ "${AUTOLINUX_UFW_ENABLE:-0}" = "1" ]; then
        run_or_dry ufw allow OpenSSH || return 1
        run_or_dry ufw --force enable
    fi
}
