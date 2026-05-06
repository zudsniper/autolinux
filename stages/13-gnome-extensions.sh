# shellcheck shell=bash
# Stage 13: thin wrapper around gnome_extensions.sh.

S13_MARKER="$AUTOLINUX_STATE_DIR/.gnome_extensions.done"

s13_detect() {
    [ -e "$S13_MARKER" ]
}

s13_precheck() {
    if [ "$(detect_de)" != "gnome" ]; then
        log_error "gnome_extensions requires a GNOME session — currently '$(detect_de)'"
        return 1
    fi
    return 0
}

s13_execute() {
    local script="$AUTOLINUX_REPO_DIR/gnome_extensions.sh"
    [ -x "$script" ] || { log_error "missing $script"; return 1; }

    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then
        log_dryrun "$script"
        return 0
    fi

    "$script" || return $?
    touch "$S13_MARKER"
}

s13_verify() {
    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then return 0; fi
    [ -e "$S13_MARKER" ]
}
