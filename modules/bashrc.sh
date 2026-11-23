# shellcheck shell=bash
# shellcheck disable=SC2034  # MOD_* metadata is read by lib/modules.sh
# zod's ~/.bashrc (dotfiles/bashrc). An existing, different ~/.bashrc is
# backed up to ~/.bashrc.bak-<timestamp> before it is replaced.
#
# "Installed" means ~/.bashrc starts with the same header and version line.
# Installers (nvm, rustup, ...) append to ~/.bashrc, so a full-file compare
# would re-install and clobber those lines on every run.

MOD_DESC="zod's ~/.bashrc (existing one backed up)"
MOD_GROUP="core"
MOD_PROFILES="minimal full"

_bashrc_src() { echo "$AUTOLINUX_REPO_DIR/dotfiles/bashrc"; }
_bashrc_dst() { echo "$(real_home)/.bashrc"; }

mod_detect() {
    [ -r "$(_bashrc_dst)" ] || return 1
    [ "$(head -n 2 "$(_bashrc_src)")" = "$(head -n 2 "$(_bashrc_dst)")" ]
}

mod_install() {
    local src dst
    src="$(_bashrc_src)" dst="$(_bashrc_dst)"
    [ -r "$src" ] || { log_error "missing $src"; return 1; }
    # shellcheck disable=SC2016  # expanded by the user's shell, not here
    as_user env SRC="$src" DST="$dst" bash -c '
        set -e
        if [ -e "$DST" ]; then
            cp -p "$DST" "$DST.bak-$(date +%Y%m%d-%H%M%S)"
            echo "backed up the old ~/.bashrc"
        fi
        cp "$SRC" "$DST"'
}
