# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
MOD_DESC="Flatpak + Flathub remote + Flatseal"
MOD_GROUP="core"
MOD_PROFILES="minimal full"
mod_detect() {
    is_package_installed flatpak && flatpak remotes 2>/dev/null | grep -q '^flathub' \
        && is_flatpak_installed com.github.tchx84.Flatseal
}
mod_install() {
    apt_install flatpak gnome-software-plugin-flatpak || return 1
    flatpak_install com.github.tchx84.Flatseal
}
