# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
# Community repackage (aaddrick/claude-desktop-debian). Installs side by side
# with Anthropic's official claude-desktop package if you add that later.
MOD_DESC="Claude Desktop (claude-desktop-unofficial apt repo)"
MOD_GROUP="apps"
MOD_PROFILES="full"
mod_detect() { is_package_installed claude-desktop-unofficial || is_package_installed claude-desktop; }
mod_install() {
    apt_add_repo claude-desktop-unofficial https://pkg.claude-desktop-debian.dev/KEY.gpg \
        "deb [signed-by=KEYRING arch=amd64,arm64] https://pkg.claude-desktop-debian.dev stable main" || return 1
    apt_install claude-desktop-unofficial
}
