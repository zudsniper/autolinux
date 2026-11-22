# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
MOD_DESC="Google Chrome (adds Google's apt repo via the .deb)"
MOD_GROUP="apps"
MOD_PROFILES="minimal full"
mod_detect()  { is_package_installed google-chrome-stable; }
mod_install() { deb_install_url https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb; }
