# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
MOD_DESC="1Password desktop + CLI"
MOD_GROUP="apps"
MOD_PROFILES="minimal full"
mod_detect() { all_packages_installed 1password 1password-cli; }
mod_install() {
    apt_add_repo 1password-archive-keyring https://downloads.1password.com/linux/keys/1password.asc \
        "deb [arch=amd64 signed-by=KEYRING] https://downloads.1password.com/linux/debian/amd64 stable main" || return 1
    apt_install 1password 1password-cli
}
