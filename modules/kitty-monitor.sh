# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
MOD_DESC="Autostart a kitty window with btop | nvtop side by side"
MOD_GROUP="desktop"
MOD_PROFILES=""
MOD_DEPENDS="kitty base-packages"
mod_detect() { [ -e "$(real_home)/.config/autostart/kitty-system-monitor.desktop" ]; }
mod_install() {
    local src="$AUTOLINUX_REPO_DIR/kitty/monitor"
    as_user mkdir -p "$(real_home)/.config/kitty" "$(real_home)/.config/autostart" || return 1
    as_user cp "$src/startup-session.conf" "$(real_home)/.config/kitty/startup-session.conf" || return 1
    as_user_sh "sed 's|@HOME@|$(real_home)|g' '$src/kitty-system-monitor.desktop' > ~/.config/autostart/kitty-system-monitor.desktop"
}
