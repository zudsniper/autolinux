# shellcheck shell=bash
# Stage 06: arm the resume hook and request reboot.
#
# detect: skip if the running session is already GNOME (we already rebooted, or
# we started in GNOME). Only triggers a reboot when GNOME is installed but not
# the active session — which only happens when we're migrating from XFCE.
#
# When this stage *does* execute, bootstrap.sh sees S06_REQUIRES_REBOOT=1 and
# performs the reboot dance after marking the stage done.

S06_REQUIRES_REBOOT=0  # set to 1 only inside execute when we actually need it

s06_detect() {
    # Already on GNOME → nothing to do.
    [ "$(detect_de)" = "gnome" ] || return 1
    return 0
}

s06_precheck() {
    # We won't reboot if /boot looks degraded.
    check_bootloader || return 1
    return 0
}

s06_execute() {
    # If we're here, detect failed → we're not on GNOME yet.
    # The actual reboot happens in bootstrap.sh after this returns successfully.
    log_warning "GNOME is installed but the active session is '$(detect_de)'."
    log_warning "A reboot is required to land in GNOME and continue."
    S06_REQUIRES_REBOOT=1
}

s06_verify() {
    # Verifying success here is tautological — if execute returned, we're armed.
    return 0
}
