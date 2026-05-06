# shellcheck shell=bash
# Stage 07: post-reboot — confirm GNOME is the running DE and GDM3 is default.

s07_detect() {
    [ "$(detect_de)" = "gnome" ] && [ "$(detect_dm)" = "gdm3" ]
}

s07_precheck() { return 0; }

s07_execute() {
    if s07_detect; then
        log_success "GNOME session active, GDM3 is default DM"
        return 0
    fi

    local de dm
    de="$(detect_de)"
    dm="$(detect_dm)"
    log_error "Expected GNOME/GDM3, got DE='$de' DM='$dm'."
    log_error "Try: log out and pick 'GNOME on Xorg' or 'Ubuntu' from the gear icon at GDM."
    log_error "If GDM is not even running, check: systemctl status gdm.service"
    return 1
}

s07_verify() { s07_detect; }
