# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
MOD_DESC="OpenVPN + NetworkManager plugin"
MOD_GROUP="security"
MOD_PROFILES="full"
PKGS=(openvpn network-manager-openvpn network-manager-openvpn-gnome)
mod_detect()  { all_packages_installed "${PKGS[@]}"; }
mod_install() { apt_install "${PKGS[@]}"; }
