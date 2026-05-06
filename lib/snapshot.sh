# shellcheck shell=bash
# timeshift snapshot wrapper. Used by stage 01.
#
# Why timeshift specifically: standard ext4 answer (we have ext4 root, no btrfs/snapper).
# Uses rsync mode with default config; tags snapshots with our prefix so we can find them.

if [ -n "${_AUTOLINUX_SNAPSHOT_SH_LOADED:-}" ]; then return 0; fi
_AUTOLINUX_SNAPSHOT_SH_LOADED=1

AUTOLINUX_SNAPSHOT_PREFIX="autolinux-pre-migration"

snapshot_install_timeshift() {
    if is_package_installed timeshift; then
        log_skip "timeshift already installed"
        return 0
    fi
    log_info "installing timeshift"
    run_or_dry apt-get update -qq
    run_or_dry env DEBIAN_FRONTEND=noninteractive apt-get install -y timeshift
}

snapshot_configure_rsync_mode() {
    # Configure timeshift for rsync mode (the only mode that works on ext4).
    # We don't override include/exclude — defaults are appropriate.
    local cfg=/etc/timeshift/timeshift.json
    if [ -r "$cfg" ] && grep -q '"backup_device_uuid"' "$cfg" 2>/dev/null; then
        log_skip "timeshift already configured"
        return 0
    fi
    log_info "first-time timeshift configuration (rsync mode)"
    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then
        log_dryrun "timeshift --create --comment 'autolinux-init' --rsync (touches config)"
        return 0
    fi
    # Running with a stub create initializes config to default device (root FS).
    timeshift --rsync --check >/dev/null 2>&1 || true
}

snapshot_take() {
    local tag
    tag="${AUTOLINUX_SNAPSHOT_PREFIX}-$(date +%Y-%m-%d_%H-%M-%S)"
    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then
        log_dryrun "timeshift --create --comments '$tag' --tags D --scripted"
        echo "$tag"
        return 0
    fi
    log_info "creating timeshift snapshot: $tag"
    if timeshift --create --comments "$tag" --tags D --scripted; then
        echo "$tag"
        return 0
    else
        log_error "timeshift --create failed"
        return 1
    fi
}

snapshot_list_ours() {
    if ! command -v timeshift >/dev/null 2>&1; then return 0; fi
    timeshift --list 2>/dev/null | awk -v p="$AUTOLINUX_SNAPSHOT_PREFIX" '
        # The list rows look like: "1    >  2026-05-05_23-55-01  D  autolinux-pre-migration-..."
        $0 ~ p {print}
    '
}

snapshot_remove_ours() {
    if ! command -v timeshift >/dev/null 2>&1; then return 0; fi
    snapshot_list_ours | awk '{print $3}' | while read -r snap; do
        [ -n "$snap" ] || continue
        run_or_dry timeshift --delete --snapshot "$snap" --scripted
    done
}
