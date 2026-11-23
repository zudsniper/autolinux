# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
MOD_DESC="Kleopatra (GPG key manager)"
MOD_GROUP="security"
MOD_PROFILES="full"
PKGS=(kleopatra)
mod_detect()  { all_packages_installed "${PKGS[@]}"; }
mod_install() { apt_install "${PKGS[@]}"; }
