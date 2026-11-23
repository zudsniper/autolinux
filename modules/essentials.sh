# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
# Small tools the other modules rely on (fetching keys and scripts, editing
# dconf lists). The runner always puts this first, so any subset of modules
# works on a fresh machine.

MOD_DESC="Essentials: curl, git, jq, gnupg (used by the other modules)"
MOD_GROUP="core"
MOD_PROFILES="minimal full"

ESSENTIALS=(curl ca-certificates gnupg git jq python3 software-properties-common dconf-cli)

mod_detect()  { all_packages_installed "${ESSENTIALS[@]}"; }
mod_install() { apt_install "${ESSENTIALS[@]}"; }
