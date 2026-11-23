# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
MOD_DESC="Visual Studio Code"
MOD_GROUP="dev"
MOD_PROFILES="minimal full"
mod_detect() { is_package_installed code; }
mod_install() {
    apt_add_repo microsoft https://packages.microsoft.com/keys/microsoft.asc \
        "deb [arch=amd64 signed-by=KEYRING] https://packages.microsoft.com/repos/code stable main" || return 1
    apt_install code
}
