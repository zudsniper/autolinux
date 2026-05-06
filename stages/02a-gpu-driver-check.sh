# shellcheck shell=bash
# Stage 02a: GPU driver check.
#
# Detects GPU vendor + currently-bound kernel module and recommends/installs
# the right vendor driver. Motivation: an RTX 3060 Ti running on the Nouveau
# kernel driver can't sustain ~820 M-pixels/sec composition for a 165 Hz panel,
# so we want bootstrap to catch "Ampere/Lovelace + nouveau" up front rather
# than ship a sluggish desktop.
#
# Decisions:
#   - NVIDIA on `nouveau` for Maxwell+ -> recommend `ubuntu-drivers devices`
#     winner and apt-install with confirmation. Sets reboot flag because the
#     kernel module swap requires reboot.
#   - NVIDIA on `nvidia` (already correct), AMD on amdgpu, Intel on i915/xe
#     -> ensure userspace bits (mesa/vulkan/va) are present, no reboot.
#   - NVIDIA on a pre-Maxwell card -> warn only (nouveau is fine there).
#   - No GPU detected -> warn and pass.
#
# Style: dry-run safe — every mutating action is behind run_or_dry.

# Reboot flag is set conditionally inside execute when we install an nvidia driver.
S02a_REQUIRES_REBOOT=0

# --- helpers ---

# Prints lines: "<pci-addr>|<vendor>|<kernel-driver>|<product-name>"
# vendor is one of: nvidia / amd / intel / other
_s02a_enumerate_gpus() {
    # Parse `lspci -D -nnk` with a small state machine — collect each device's
    # class + product line, then read its "Kernel driver in use:" line.
    local line current_pci="" current_class="" current_product="" current_driver=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^([0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-9a-f])\ ([^:]+):\ (.*)$ ]]; then
            # Flush previous record if it was a GPU.
            if [ -n "$current_pci" ]; then
                _s02a_emit_gpu "$current_pci" "$current_class" "$current_product" "$current_driver"
            fi
            current_pci="${BASH_REMATCH[1]}"
            current_class="${BASH_REMATCH[2]}"
            current_product="${BASH_REMATCH[3]}"
            current_driver=""
        elif [[ "$line" =~ ^[[:space:]]+Kernel\ driver\ in\ use:\ (.*)$ ]]; then
            current_driver="${BASH_REMATCH[1]}"
        fi
    done < <(lspci -D -nnk 2>/dev/null)
    if [ -n "$current_pci" ]; then
        _s02a_emit_gpu "$current_pci" "$current_class" "$current_product" "$current_driver"
    fi
}

_s02a_emit_gpu() {
    local pci="$1" class="$2" product="$3" driver="$4"
    case "$class" in
        *VGA*|*"3D controller"*|*"Display controller"*) ;;
        *) return 0 ;;
    esac
    local vendor="other"
    case "$product" in
        *NVIDIA*|*nvidia*)                 vendor="nvidia" ;;
        *"Advanced Micro Devices"*|*AMD*|*ATI*) vendor="amd" ;;
        *Intel*)                           vendor="intel" ;;
    esac
    # Use a delimiter that won't appear in product names.
    printf '%s|%s|%s|%s\n' "$pci" "$vendor" "${driver:-none}" "$product"
}

# Heuristic: pre-Maxwell NVIDIA cards (GeForce GT/GTX 4xx/5xx/6xx/7xx, Quadro K)
# are old enough that nouveau is acceptable. We match conservatively — anything
# else (including unlabeled future architectures) gets treated as "needs the
# proprietary driver".
_s02a_nvidia_is_pre_maxwell() {
    local product="$1"
    # Known pre-Maxwell GeForce model numbers in the 400/500/600/700 series
    # (excluding GTX 750/750 Ti which are actually Maxwell — caught below).
    if [[ "$product" =~ GeForce[[:space:]]+(GT|GTX)[[:space:]]+(4[0-9]{2}|5[0-9]{2}|6[0-9]{2}|7[0-3][0-9]) ]]; then
        return 0
    fi
    if [[ "$product" =~ Quadro[[:space:]]+K[0-9] ]]; then
        return 0
    fi
    return 1
}

# Parse `ubuntu-drivers devices` output and emit the recommended package name.
# Empty output if no recommendation was found.
_s02a_recommended_nvidia_pkg() {
    if ! command -v ubuntu-drivers >/dev/null 2>&1; then
        return 1
    fi
    ubuntu-drivers devices 2>/dev/null \
        | awk '/^driver[[:space:]]*:[[:space:]]*nvidia-driver-.*recommended/ {print $3; exit}'
}

_s02a_secure_boot_state() {
    if command -v mokutil >/dev/null 2>&1; then
        mokutil --sb-state 2>/dev/null | head -n1
    else
        echo "unknown (mokutil not installed)"
    fi
}

# --- stage interface ---

s02a_detect() {
    # Returns 0 if all detected GPUs are healthy, 1 if remediation is needed.
    local any=0 needs_work=0 vendor driver product
    while IFS='|' read -r _pci vendor driver product; do
        any=1
        case "$vendor" in
            nvidia)
                if [ "$driver" = "nvidia" ]; then
                    : # already on proprietary
                elif [ "$driver" = "nouveau" ] && _s02a_nvidia_is_pre_maxwell "$product"; then
                    : # nouveau is fine for ancient cards
                else
                    needs_work=1
                fi
                ;;
            amd)
                if [ "$driver" != "amdgpu" ] && [ "$driver" != "radeon" ]; then
                    needs_work=1
                fi
                if ! is_package_installed mesa-vulkan-drivers || ! is_package_installed libvulkan1; then
                    needs_work=1
                fi
                ;;
            intel)
                if [ "$driver" != "i915" ] && [ "$driver" != "xe" ]; then
                    needs_work=1
                fi
                ;;
            *)
                : # unknown vendor — pass
                ;;
        esac
    done < <(_s02a_enumerate_gpus)
    if [ "$any" = "0" ]; then
        return 0
    fi
    [ "$needs_work" = "0" ]
}

s02a_precheck() {
    check_dpkg_sane || return 1
    if ! command -v ubuntu-drivers >/dev/null 2>&1; then
        log_info "ubuntu-drivers-common is missing — installing it for driver recommendations"
        run_or_dry apt-get update -qq
        run_or_dry env DEBIAN_FRONTEND=noninteractive \
            apt-get install -y ubuntu-drivers-common
    fi
    return 0
}

_s02a_handle_nvidia() {
    local product="$1" driver="$2"
    if [ "$driver" = "nvidia" ]; then
        log_success "NVIDIA GPU already on proprietary driver: $product"
        return 0
    fi
    if [ "$driver" = "nouveau" ] && _s02a_nvidia_is_pre_maxwell "$product"; then
        log_warning "NVIDIA $product on nouveau — pre-Maxwell card, leaving as-is."
        return 0
    fi

    log_warning "NVIDIA $product is bound to '${driver:-none}'. This is the situation that"
    log_warning "tanks compositor performance on Ampere/Lovelace at high refresh rates."

    local pkg
    pkg="$(_s02a_recommended_nvidia_pkg || true)"
    if [ -z "$pkg" ]; then
        log_error "ubuntu-drivers had no nvidia-driver-* recommendation; skipping install."
        log_error "Inspect manually with: ubuntu-drivers devices"
        return 0
    fi

    log_info "ubuntu-drivers recommends: $pkg"

    local sb
    sb="$(_s02a_secure_boot_state)"
    log_info "secure boot state: $sb"
    case "$sb" in
        *enabled*)
            log_warning "Secure Boot is ENABLED. Installing an NVIDIA module will require"
            log_warning "enrolling a MOK on next reboot. The installer will prompt for an"
            log_warning "8-16 char password; remember it — you'll type it twice into the"
            log_warning "MokManager UI shown by shim before the kernel boots."
            log_warning "Reference: https://wiki.ubuntu.com/UEFI/SecureBoot/DKMS"
            ;;
    esac

    if ! log_confirm "Install $pkg now?"; then
        log_warning "skipped NVIDIA driver install on user request"
        return 0
    fi

    log_info "showing apt simulation before install:"
    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then
        log_dryrun "apt-get install --simulate -y $pkg"
    else
        apt-get install --simulate -y "$pkg" 2>&1 | sed 's/^/    /' || true
    fi

    run_or_dry apt-get update -qq
    run_or_dry env DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg"

    state_set gpu_driver_installed "$pkg"
    state_array_append gpu_drivers_installed "$pkg"
    S02a_REQUIRES_REBOOT=1
    log_success "queued reboot — $pkg loaded after restart"
}

_s02a_handle_amd() {
    local product="$1" driver="$2"
    log_info "AMD GPU: $product (driver: ${driver:-none})"
    local missing=()
    is_package_installed mesa-vulkan-drivers || missing+=("mesa-vulkan-drivers")
    is_package_installed libvulkan1          || missing+=("libvulkan1")
    is_package_installed vulkan-tools        || missing+=("vulkan-tools")
    if [ "${#missing[@]}" -eq 0 ]; then
        log_success "AMD userspace stack present"
        return 0
    fi
    log_info "installing AMD userspace bits: ${missing[*]}"
    run_or_dry apt-get update -qq
    run_or_dry env DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
}

_s02a_handle_intel() {
    local product="$1" driver="$2"
    log_info "Intel GPU: $product (driver: ${driver:-none})"
    local missing=()
    # Prefer non-free VA-API driver when available (covers more codecs); fall
    # back to the free variant if the non-free package isn't in the index.
    if ! is_package_installed intel-media-va-driver-non-free \
       && ! is_package_installed intel-media-va-driver; then
        if apt-cache show intel-media-va-driver-non-free >/dev/null 2>&1; then
            missing+=("intel-media-va-driver-non-free")
        else
            missing+=("intel-media-va-driver")
        fi
    fi
    is_package_installed i965-va-driver || missing+=("i965-va-driver")
    is_package_installed libvulkan1     || missing+=("libvulkan1")
    if [ "${#missing[@]}" -eq 0 ]; then
        log_success "Intel userspace stack present"
        return 0
    fi
    log_info "installing Intel userspace bits: ${missing[*]}"
    run_or_dry apt-get update -qq
    run_or_dry env DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
}

s02a_execute() {
    local found=0 pci vendor driver product
    while IFS='|' read -r pci vendor driver product; do
        found=1
        log_info "GPU @ $pci  vendor=$vendor  bound=$driver"
        case "$vendor" in
            nvidia) _s02a_handle_nvidia "$product" "$driver" ;;
            amd)    _s02a_handle_amd    "$product" "$driver" ;;
            intel)  _s02a_handle_intel  "$product" "$driver" ;;
            *)      log_warning "unknown GPU vendor for $product — skipping" ;;
        esac
    done < <(_s02a_enumerate_gpus)

    if [ "$found" = "0" ]; then
        log_warning "no GPU detected via lspci — skipping driver checks"
    fi
    return 0
}

s02a_verify() {
    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then return 0; fi
    # If we just queued an nvidia install, the kernel module won't be live until
    # after reboot — so we don't re-run detect here in that case.
    if [ "$S02a_REQUIRES_REBOOT" = "1" ]; then
        log_info "verify: nvidia driver install queued; full verification deferred until post-reboot"
        return 0
    fi
    s02a_detect || {
        log_warning "post-execute detection still reports remediation needed (non-fatal)"
        return 0
    }
}
