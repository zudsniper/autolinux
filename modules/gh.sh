# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
MOD_DESC="GitHub CLI"
MOD_GROUP="dev"
MOD_PROFILES="minimal full"
mod_detect() { is_package_installed gh; }
mod_install() {
    apt_add_repo githubcli-archive-keyring https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        "deb [arch=$(dpkg --print-architecture) signed-by=KEYRING] https://cli.github.com/packages stable main" || return 1
    apt_install gh
}
