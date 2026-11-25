# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
# Small tools the other modules rely on (fetching scripts, adding signed apt
# repos). The runner always puts this first, so any subset of modules works on
# a fresh machine. Kept deliberately tiny and installed without Recommends:
# heavier helpers (python3, dconf-cli, software-properties-common) are
# installed by the modules that use them. Keep this to packages that exist on
# both Ubuntu and Debian (software-properties-common is gone in Debian 13).

MOD_DESC="Essentials: curl, git, jq, gpg (used by the other modules)"
MOD_GROUP="core"
MOD_PROFILES="minimal full"

ESSENTIALS=(curl ca-certificates git jq gpg)

mod_detect()  { all_packages_installed "${ESSENTIALS[@]}"; }
mod_install() { apt_install_lean "${ESSENTIALS[@]}"; }
