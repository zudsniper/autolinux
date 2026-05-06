# shellcheck shell=bash
# Stage 00: preflight
# Validate that the system is sane enough to start: Ubuntu, dpkg-clean,
# no other autolinux run, optional pending-upgrades guard, basic free space.

s00_detect() {
    # Always run preflight when not yet done — it's cheap and catches drift.
    return 1
}

s00_precheck() { return 0; }

s00_execute() {
    local fail=0

    if ! require_ubuntu; then
        log_error "Not an Ubuntu system. /etc/os-release ID != ubuntu."
        log_error "Refusing to migrate (this script targets Ubuntu/Xubuntu)."
        fail=1
    else
        log_success "Ubuntu detected: $(ubuntu_version_id)"
    fi

    if [ ! -d /sys/firmware/efi ]; then
        log_warning "Legacy BIOS boot detected — EFI checks will be skipped later."
    else
        log_success "UEFI boot detected"
    fi

    log_info "running dpkg/apt sanity gate…"
    if ! check_dpkg_sane; then
        log_error "Fix dpkg/apt state before re-running:"
        log_error "  sudo dpkg --configure -a"
        log_error "  sudo apt-get --fix-broken install"
        fail=1
    else
        log_success "dpkg --audit clean, apt-get check clean"
    fi

    local free_gb
    free_gb="$(disk_root_free_gb)"
    if [ -z "$free_gb" ] || [ "$free_gb" -lt 15 ]; then
        log_error "Less than 15GB free on / (have ${free_gb:-?}GB). Free space before continuing."
        fail=1
    elif [ "$free_gb" -lt 30 ]; then
        log_warning "Only ${free_gb}GB free on /. timeshift snapshot may be tight."
    else
        log_success "${free_gb}GB free on /"
    fi

    local mem_gb
    mem_gb="$(mem_total_gb)"
    if [ "$mem_gb" -lt 4 ]; then
        log_warning "Only ${mem_gb}GB RAM. GNOME 49 wants ≥4GB; expect sluggishness."
    fi

    log_info "checking for pending apt upgrades…"
    local pending
    pending="$(pending_upgrade_count)"
    if [ "$pending" -gt 0 ]; then
        if [ "${AUTOLINUX_ALLOW_PENDING_UPGRADES:-0}" = "1" ]; then
            log_warning "$pending pending upgrades — proceeding (--allow-pending-upgrades set)."
        else
            log_error "$pending pending apt upgrades. DO NOT mix updates with a DE migration."
            log_error "Run first:  sudo apt-get update && sudo apt-get upgrade && sudo reboot"
            log_error "Or override with --allow-pending-upgrades (not recommended)."
            fail=1
        fi
    else
        log_success "no pending apt upgrades"
    fi

    log_info "checking network connectivity…"
    if curl -fsS --max-time 6 -o /dev/null https://archive.ubuntu.com/ 2>/dev/null \
       || curl -fsS --max-time 6 -o /dev/null https://1.1.1.1/ 2>/dev/null; then
        log_success "network reachable"
    else
        log_error "no network — cannot apt-install. Connect to the internet and retry."
        fail=1
    fi

    # Heads-up only — actual remediation lives in stage 02a (gpu-driver-check).
    if command -v lspci >/dev/null 2>&1; then
        if lspci -nnk 2>/dev/null | awk '
            /VGA|3D controller|Display controller/ { is_gpu=1; product=$0; next }
            is_gpu && /Kernel driver in use:/      { driver=$0; print product"\n"driver; is_gpu=0 }
        ' | grep -q 'NVIDIA' && \
           lspci -nnk 2>/dev/null | grep -A2 'NVIDIA' | grep -q 'Kernel driver in use: nouveau'; then
            log_warning "NVIDIA GPU is currently bound to nouveau — stage 02a will offer to install the proprietary driver."
        fi
    fi

    if [ -e "$AUTOLINUX_STATE_DIR/.lock" ]; then
        local pid
        pid="$(cat "$AUTOLINUX_STATE_DIR/.lock" 2>/dev/null || echo "")"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && [ "$pid" != "$$" ]; then
            log_error "another autolinux process is running (pid $pid)"
            fail=1
        else
            log_warning "stale lock file at $AUTOLINUX_STATE_DIR/.lock — cleaning up"
            run_or_dry rm -f "$AUTOLINUX_STATE_DIR/.lock"
        fi
    fi
    if [ "${AUTOLINUX_DRY_RUN:-0}" != "1" ]; then
        echo "$$" > "$AUTOLINUX_STATE_DIR/.lock"
    fi

    return "$fail"
}

s00_verify() { return 0; }
