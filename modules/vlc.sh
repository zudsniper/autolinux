# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
MOD_DESC="VLC media player"
MOD_GROUP="apps"
MOD_PROFILES="full"
PKGS=(vlc)
mod_detect()  { all_packages_installed "${PKGS[@]}"; }
mod_install() { apt_install "${PKGS[@]}"; }
