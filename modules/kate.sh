# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
MOD_DESC="Kate text editor (flatpak)"
MOD_GROUP="apps"
MOD_PROFILES="full"
MOD_DEPENDS="flatpak"
APPS=(org.kde.kate)
mod_detect()  { all_flatpaks_installed "${APPS[@]}"; }
mod_install() { flatpak_install "${APPS[@]}"; }
