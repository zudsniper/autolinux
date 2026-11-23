# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
MOD_DESC="Cursor editor (official apt repo)"
MOD_GROUP="dev"
MOD_PROFILES="full"
mod_detect() { is_package_installed cursor; }
mod_install() {
    apt_add_repo anysphere https://downloads.cursor.com/keys/anysphere.asc \
        "deb [arch=amd64,arm64 signed-by=KEYRING] https://downloads.cursor.com/aptrepo stable main" || return 1
    apt_install cursor
}
