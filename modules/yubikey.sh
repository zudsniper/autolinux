# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
# age-plugin-yubikey ships no Linux binaries, so it is built with cargo and
# linked into /usr/local/bin.
MOD_DESC="YubiKey tools: ykman, pcscd, age, age-plugin-yubikey"
MOD_GROUP="security"
MOD_PROFILES="full"
MOD_DEPENDS="rust"
PKGS=(yubikey-manager pcscd age)
BUILD_DEPS=(libpcsclite-dev pkgconf)
mod_detect() { all_packages_installed "${PKGS[@]}" && command -v age-plugin-yubikey >/dev/null 2>&1; }
mod_install() {
    apt_install "${PKGS[@]}" "${BUILD_DEPS[@]}" || return 1
    run_or_dry systemctl enable --now pcscd.socket || true
    as_user cargo install --locked age-plugin-yubikey || return 1
    run_or_dry ln -sf "$(real_home)/.cargo/bin/age-plugin-yubikey" /usr/local/bin/age-plugin-yubikey
}
