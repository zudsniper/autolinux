# shellcheck shell=bash
# Stage 12: GNOME desktop settings (modules/desktop-settings.sh).

s12_detect() { modules_stage_detect desktop-settings; }
s12_precheck() {
    [ "$(detect_de)" = "gnome" ] || log_warning "desktop-settings targets GNOME but DE='$(detect_de)' — running anyway"
    return 0
}
s12_execute() { modules_stage_run desktop-settings; }
s12_verify() {
    [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ] && return 0
    modules_stage_detect desktop-settings
}
