# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
MOD_DESC="LocalSend (flatpak)"
MOD_GROUP="apps"
MOD_PROFILES="full"
MOD_DEPENDS="flatpak"
APPS=(org.localsend.localsend_app)
mod_detect()  { all_flatpaks_installed "${APPS[@]}"; }
mod_install() { flatpak_install "${APPS[@]}"; }
