# shellcheck shell=bash
# Stage 12: thin wrapper around desktop_config.sh.
# The script applies gsettings (idempotent) and creates an autostart entry.

S12_MARKER="$AUTOLINUX_STATE_DIR/.desktop_config.done"

s12_detect() {
    [ -e "$S12_MARKER" ]
}

s12_precheck() {
    [ "$(detect_de)" = "gnome" ] || { log_warning "desktop_config targets GNOME but DE='$(detect_de)' — running anyway"; }
    return 0
}

s12_execute() {
    local script="$AUTOLINUX_REPO_DIR/desktop_config.sh"
    [ -x "$script" ] || { log_error "missing $script"; return 1; }

    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then
        log_dryrun "$script"
        return 0
    fi

    "$script" || return $?
    touch "$S12_MARKER"
}

s12_verify() {
    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then return 0; fi
    [ -e "$S12_MARKER" ]
}
