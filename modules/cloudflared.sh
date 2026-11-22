# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
MOD_DESC="cloudflared (Cloudflare Tunnel client)"
MOD_GROUP="dev"
MOD_PROFILES="full"
mod_detect() { command -v cloudflared >/dev/null 2>&1; }
mod_install() {
    apt_add_repo cloudflare-main https://pkg.cloudflare.com/cloudflare-main.gpg \
        "deb [signed-by=KEYRING] https://pkg.cloudflare.com/cloudflared any main" || return 1
    apt_install cloudflared
}
