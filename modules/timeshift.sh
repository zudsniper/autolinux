# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
MOD_DESC="Timeshift system snapshots"
MOD_GROUP="security"
MOD_PROFILES="minimal full"
PKGS=(timeshift)
mod_detect()  { all_packages_installed "${PKGS[@]}"; }
mod_install() { apt_install "${PKGS[@]}"; }
