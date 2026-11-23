# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
MOD_DESC="uv (Astral Python package manager, per user)"
MOD_GROUP="dev"
MOD_PROFILES="full"
mod_detect() { as_user test -x "$(real_home)/.local/bin/uv"; }
mod_install() { as_user_sh 'curl -LsSf https://astral.sh/uv/install.sh | sh'; }
