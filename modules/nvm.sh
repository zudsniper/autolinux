# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
MOD_DESC="nvm + latest Node LTS (per user)"
MOD_GROUP="dev"
MOD_PROFILES="minimal full"
NVM_VERSION="${NVM_VERSION:-v0.40.3}"
mod_detect() {
    as_user test -s "$(real_home)/.nvm/nvm.sh" || return 1
    compgen -G "$(real_home)/.nvm/versions/node/v*" >/dev/null
}
mod_install() {
    as_user test -s "$(real_home)/.nvm/nvm.sh" || as_user_sh "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh | bash" || return 1
    as_user_sh 'export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh"; nvm install --lts'
}
