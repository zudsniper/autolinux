# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
MOD_DESC="Signal Desktop"
MOD_GROUP="apps"
MOD_PROFILES="full"
mod_detect() { is_package_installed signal-desktop; }
mod_install() {
    apt_add_repo signal-desktop-keyring https://updates.signal.org/desktop/apt/keys.asc \
        "deb [arch=amd64 signed-by=KEYRING] https://updates.signal.org/desktop/apt xenial main" || return 1
    apt_install signal-desktop
}
