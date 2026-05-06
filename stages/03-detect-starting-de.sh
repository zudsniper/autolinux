# shellcheck shell=bash
# Stage 03: record the starting DE/DM in state.json.
# This is captured BEFORE any installs/purges so we can diff later and so
# resume runs (post-reboot) can compare.

s03_detect() {
    local de
    de="$(state_get starting_de)"
    [ -n "$de" ] && [ "$de" != "null" ]
}

s03_precheck() { return 0; }

s03_execute() {
    local de dm sess
    de="$(detect_de)"
    dm="$(detect_dm)"
    sess="$(detect_session_type)"

    log_info "detected DE:           $de"
    log_info "detected DM:           $dm"
    log_info "detected session type: $sess"

    state_set starting_de "$de"
    state_set starting_dm "$dm"
    state_set starting_session_type "$sess"

    if [ "$de" = "xfce" ]; then
        log_warning "Starting in XFCE — full migration will run (install GNOME, switch DM, reboot)."
    elif [ "$de" = "gnome" ]; then
        log_info "Starting in GNOME — migration stages will short-circuit; only cleanup runs."
    else
        log_warning "Unrecognized DE '$de' — proceeding with best-effort detection at later stages."
    fi
}

s03_verify() { s03_detect; }
