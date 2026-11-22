# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
# Takes over Print from GNOME's built-in screenshot UI.
MOD_DESC="Flameshot on Print (GNOME screenshot keys cleared) + autostart"
MOD_GROUP="desktop"
MOD_PROFILES="full"
mod_detect() {
    is_package_installed flameshot && gnome_has_keybinding "flameshot gui" \
        && [ -e "$(real_home)/.config/autostart/org.flameshot.Flameshot.desktop" ]
}
mod_install() {
    apt_install flameshot || return 1
    as_user dconf write /org/gnome/shell/keybindings/show-screenshot-ui "@as []"
    as_user dconf write /org/gnome/shell/keybindings/screenshot "@as []"
    gnome_add_keybinding "Flameshot Region Select" "flameshot gui" "Print" || return 1
    as_user_sh 'mkdir -p ~/.config/autostart && cp /usr/share/applications/org.flameshot.Flameshot.desktop ~/.config/autostart/'
}
