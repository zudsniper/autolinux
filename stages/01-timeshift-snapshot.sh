# shellcheck shell=bash
# Stage 01: pre-migration timeshift snapshot.
# rsync mode (only viable option on ext4). Snapshot tag prefixed so we can
# find/remove ours later.

s01_detect() {
    command -v timeshift >/dev/null 2>&1 || return 1
    [ -n "$(snapshot_list_ours 2>/dev/null)" ]
}

s01_precheck() {
    local free_gb
    free_gb="$(disk_root_free_gb)"
    if [ -z "$free_gb" ] || [ "$free_gb" -lt 10 ]; then
        log_error "Snapshot needs ≥10GB free on /; have ${free_gb:-?}GB."
        return 1
    fi
    return 0
}

s01_execute() {
    snapshot_install_timeshift   || return 1
    snapshot_configure_rsync_mode || return 1
    local tag
    tag="$(snapshot_take)" || return 1
    if [ -n "$tag" ]; then
        state_stage_meta "01-timeshift-snapshot" snapshot "$tag"
        log_success "snapshot created: $tag"
    fi
    return 0
}

s01_verify() {
    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then return 0; fi
    [ -n "$(snapshot_list_ours)" ]
}
