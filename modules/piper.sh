# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
MOD_DESC="Piper / ratbagd (gaming mouse config)"
MOD_GROUP="hardware"
MOD_PROFILES="full"
PKGS=(piper ratbagd)
mod_detect()  { all_packages_installed "${PKGS[@]}"; }
mod_install() { apt_install "${PKGS[@]}"; }
