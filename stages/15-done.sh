# shellcheck shell=bash
# Stage 15: cleanup and final summary.
# - Removes resume hooks (autostart .desktop + systemd unit)
# - Releases the lock file
# - Optionally offers to delete the timeshift snapshot
# - Prints a summary of what changed

s15_detect() {
    [ "$(state_get status)" = "done" ]
}

s15_precheck() { return 0; }

s15_execute() {
    local user
    user="$(real_user)"
    resume_remove_hooks "$user"

    rm -f "$AUTOLINUX_STATE_DIR/.lock" 2>/dev/null || true

    log_header "Migration summary"
    {
        echo "starting DE:           $(state_get starting_de)"
        echo "starting DM:           $(state_get starting_dm)"
        echo "starting session type: $(state_get starting_session_type)"
        echo "current DE:            $(detect_de)"
        echo "current DM:            $(detect_dm)"
        echo "current session type:  $(detect_session_type)"
    } | sed 's/^/    /'

    log_info "snapshots created by this run:"
    snapshot_list_ours | sed 's/^/    /' || true

    log_info "packages purged this run:"
    jq -r '.purged[]?' < "$AUTOLINUX_STATE_FILE" 2>/dev/null | sed 's/^/    /' || true

    log_info "config files backed up:"
    jq -r '.config_backups[]?' < "$AUTOLINUX_STATE_FILE" 2>/dev/null | sed 's/^/    /' || true

    if command -v timeshift >/dev/null 2>&1 && [ -n "$(snapshot_list_ours 2>/dev/null)" ]; then
        if log_confirm "Delete the autolinux pre-migration snapshot(s)?"; then
            snapshot_remove_ours
        else
            log_info "snapshots kept; remove later with: sudo timeshift --delete --snapshot <name>"
        fi
    fi

    state_set status "done"
    log_success "autolinux complete"
}

s15_verify() {
    [ "$(state_get status)" = "done" ]
}
