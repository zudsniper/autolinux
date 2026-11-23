# shellcheck shell=bash
# Stage 13: GNOME Shell extensions from extensions.gnome.org
# (modules/gnome-extensions.sh).

s13_detect() { modules_stage_detect gnome-extensions; }
s13_precheck() {
    if [ "$(detect_de)" != "gnome" ]; then
        log_error "gnome-extensions requires a GNOME session — currently '$(detect_de)'"
        return 1
    fi
    return 0
}
s13_execute() { modules_stage_run gnome-extensions; }
s13_verify() {
    [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ] && return 0
    modules_stage_detect gnome-extensions
}
