# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
# Stable toolchain is enough for Ringboard >= 0.15 (no nightly needed anymore).
MOD_DESC="Rust toolchain via rustup (stable, per user)"
MOD_GROUP="core"
MOD_PROFILES="minimal full"
mod_detect() { as_user bash -c 'command -v cargo && rustup toolchain list | grep -q stable' >/dev/null 2>&1; }
mod_install() {
    apt_install build-essential pkgconf curl || return 1
    if as_user bash -c 'command -v rustup' >/dev/null 2>&1; then
        as_user rustup toolchain install stable --profile minimal
    else
        as_user_sh 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable'
    fi
}
