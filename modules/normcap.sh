# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
MOD_DESC="NormCap OCR screen-capture (flatpak) on Ctrl+Super+Alt+O"
MOD_GROUP="desktop"
MOD_PROFILES=""
MOD_DEPENDS="flatpak"
mod_detect() { is_flatpak_installed com.github.dynobo.normcap && gnome_has_keybinding "flatpak run com.github.dynobo.normcap"; }
mod_install() {
    flatpak_install com.github.dynobo.normcap || return 1
    gnome_add_keybinding "NormCap OCR" "flatpak run com.github.dynobo.normcap" "<Ctrl><Super><Alt>o"
}
