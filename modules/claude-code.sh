# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
MOD_DESC="Claude Code CLI (native installer, per user)"
MOD_GROUP="dev"
MOD_PROFILES="full"
mod_detect() { as_user test -x "$(real_home)/.local/bin/claude"; }
mod_install() { as_user_sh 'curl -fsSL https://claude.ai/install.sh | bash'; }
