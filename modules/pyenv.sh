# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
MOD_DESC="pyenv + Python build deps (per user)"
MOD_GROUP="dev"
MOD_PROFILES="full"
DEPS=(git make build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev
      curl llvm libncurses-dev xz-utils tk-dev libffi-dev liblzma-dev)
mod_detect() { as_user test -x "$(real_home)/.pyenv/bin/pyenv"; }
mod_install() {
    apt_install "${DEPS[@]}" || return 1
    as_user_sh 'curl -fsSL https://pyenv.run | bash' || return 1
    as_user_sh 'grep -q PYENV_ROOT ~/.bashrc || cat >> ~/.bashrc <<"RC"

# pyenv (added by autolinux)
export PYENV_ROOT="$HOME/.pyenv"
command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
RC'
}
