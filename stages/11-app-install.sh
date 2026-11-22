# shellcheck shell=bash
# Stage 11: install the selected app/dev/desktop modules (everything except
# desktop-settings and gnome-extensions, which have their own stages).
# Detection is live: the stage counts as done when every selected module
# detects as already set up.

s11_detect()   { modules_stage_detect apps; }
s11_precheck() { check_dpkg_sane; }
s11_execute()  { modules_stage_run apps; }
s11_verify() {
    [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ] && return 0
    modules_stage_detect apps
}
