# shellcheck shell=bash
# Module registry, selection (profile / --with / --without / --only /
# interactive checklist) and runner.
#
# A module is modules/<name>.sh defining:
#   MOD_DESC="One-line description"
#   MOD_GROUP="core|desktop|apps|dev|security|hardware|extras"
#   MOD_PROFILES="minimal full"   # profiles that include it by default ("" = opt-in only)
#   MOD_DEPENDS="rust"            # optional, other module names
#   mod_detect()  { ...; }        # 0 = already installed/configured (read-only!)
#   mod_install() { ...; }        # do the work (root context; use as_user for user bits)
#
# Each module is sourced in a subshell, so modules can't leak state into each
# other. In --dry-run, mod_install is never called: the runner only reports
# which modules would be installed.

if [ -n "${_AUTOLINUX_MODULES_SH_LOADED:-}" ]; then return 0; fi
_AUTOLINUX_MODULES_SH_LOADED=1

AUTOLINUX_REPO_DIR="${AUTOLINUX_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/user.sh
source "$AUTOLINUX_REPO_DIR/lib/user.sh"
# shellcheck source=lib/pkg.sh
source "$AUTOLINUX_REPO_DIR/lib/pkg.sh"

# Run order. Dependencies must come before their dependents.
MODULE_ORDER=(
    base-packages flatpak rust
    kitty ringboard gnome-extensions desktop-settings flameshot normcap kitty-monitor
    chrome 1password signal discord spotify localsend rustdesk steam obs kate vlc transmission claude-desktop
    vscode cursor gh docker portainer nvm pyenv uv claude-code cloudflared virtualization
    ufw yubikey openvpn timeshift kleopatra
    ckb-next piper
    notify-services
)

declare -gA MOD_META_DESC=() MOD_META_GROUP=() MOD_META_PROFILES=() MOD_META_DEPENDS=()

_module_file() { echo "$AUTOLINUX_REPO_DIR/modules/$1.sh"; }

modules_load_meta() {
    local m line
    for m in "${MODULE_ORDER[@]}"; do
        [ -r "$(_module_file "$m")" ] || { log_error "missing module file: modules/$m.sh"; return 1; }
        line="$(
            MOD_DESC="" MOD_GROUP="" MOD_PROFILES="" MOD_DEPENDS=""
            # shellcheck source=/dev/null
            source "$(_module_file "$m")"
            printf '%s\t%s\t%s\t%s' "$MOD_GROUP" "${MOD_PROFILES:--}" "${MOD_DEPENDS:--}" "$MOD_DESC"
        )"
        local g p d desc
        IFS=$'\t' read -r g p d desc <<< "$line"
        [ "$p" = "-" ] && p=""
        [ "$d" = "-" ] && d=""
        MOD_META_GROUP[$m]="$g"; MOD_META_PROFILES[$m]="$p"
        MOD_META_DEPENDS[$m]="$d"; MOD_META_DESC[$m]="$desc"
    done
}

module_exists() {
    local m
    for m in "${MODULE_ORDER[@]}"; do [ "$m" = "$1" ] && return 0; done
    return 1
}

# Expand a comma list of module and/or group names (e.g. "ringboard,dev").
_expand_names() {
    local item m matched items=()
    IFS=',' read -ra items <<< "$1"
    for item in "${items[@]}"; do
        item="${item// /}"
        [ -z "$item" ] && continue
        if module_exists "$item"; then
            echo "$item"
            continue
        fi
        matched=0
        for m in "${MODULE_ORDER[@]}"; do
            if [ "${MOD_META_GROUP[$m]}" = "$item" ]; then echo "$m"; matched=1; fi
        done
        [ "$matched" = "1" ] || { log_error "unknown module or group: $item (see --list-modules)"; return 1; }
    done
}

declare -gA _SEL=()

# modules_select <profile> <only> <with> <without> <interactive 0|1>
# Result: MODULES_SELECTED array, in run order.
modules_select() {
    local profile="$1" only="$2" with="$3" without="$4" interactive="$5" m names
    _SEL=()
    if [ -n "$only" ]; then
        names="$(_expand_names "$only")" || return 1
        for m in $names; do _SEL[$m]=1; done
    else
        for m in "${MODULE_ORDER[@]}"; do
            case " ${MOD_META_PROFILES[$m]} " in *" $profile "*) _SEL[$m]=1 ;; esac
        done
    fi
    if [ -n "$with" ]; then
        names="$(_expand_names "$with")" || return 1
        for m in $names; do _SEL[$m]=1; done
    fi
    if [ -n "$without" ]; then
        names="$(_expand_names "$without")" || return 1
        for m in $names; do unset "_SEL[$m]"; done
    fi

    [ "$interactive" = "1" ] && _modules_interactive

    # Pull in dependencies.
    local changed=1 d
    while [ "$changed" = "1" ]; do
        changed=0
        for m in "${!_SEL[@]}"; do
            for d in ${MOD_META_DEPENDS[$m]}; do
                if [ -z "${_SEL[$d]:-}" ]; then
                    log_info "adding '$d' (required by '$m')"
                    _SEL[$d]=1; changed=1
                fi
            done
        done
    done

    MODULES_SELECTED=()
    for m in "${MODULE_ORDER[@]}"; do
        [ -n "${_SEL[$m]:-}" ] && MODULES_SELECTED+=("$m")
    done
    return 0
}

_modules_interactive() {
    local m args=() state choice
    if command -v whiptail >/dev/null 2>&1 && [ -t 0 ]; then
        for m in "${MODULE_ORDER[@]}"; do
            state=OFF; [ -n "${_SEL[$m]:-}" ] && state=ON
            args+=("$m" "[${MOD_META_GROUP[$m]}] ${MOD_META_DESC[$m]}" "$state")
        done
        choice="$(whiptail --title "autolinux" --separate-output \
            --checklist "Space toggles, Enter confirms. Preselected = current profile." \
            30 110 22 "${args[@]}" 3>&1 1>&2 2>&3)" || log_die "cancelled"
        _SEL=()
        for m in $choice; do _SEL[$m]=1; done
        return 0
    fi
    log_info "whiptail not available; answering per module (Enter keeps the default)."
    local ans def
    for m in "${MODULE_ORDER[@]}"; do
        def=n; [ -n "${_SEL[$m]:-}" ] && def=y
        read -r -p "  [${MOD_META_GROUP[$m]}] $m - ${MOD_META_DESC[$m]} [$def]: " ans
        ans="${ans:-$def}"
        if [[ "$ans" =~ ^[Yy] ]]; then _SEL[$m]=1; else unset "_SEL[$m]"; fi
    done
}

modules_list() {
    local m
    printf '%-17s %-9s %-13s %s\n' MODULE GROUP PROFILES DESCRIPTION
    for m in "${MODULE_ORDER[@]}"; do
        printf '%-17s %-9s %-13s %s\n' "$m" "${MOD_META_GROUP[$m]}" "${MOD_META_PROFILES[$m]:-opt-in}" "${MOD_META_DESC[$m]}"
    done
}

# Run one module function in an isolated subshell.
_module_call() {
    local m="$1" fn="$2"
    (
        # shellcheck source=/dev/null
        source "$(_module_file "$m")"
        declare -F "$fn" >/dev/null || { log_error "$m: missing $fn"; exit 1; }
        "$fn"
    )
}

module_detect() { _module_call "$1" mod_detect >/dev/null 2>&1; }

# modules_run — install MODULES_SELECTED. Returns 1 if any module failed.
modules_run() {
    MODULES_FAILED=(); MODULES_DONE=(); MODULES_SKIPPED=()
    local status_file="${AUTOLINUX_LOG_DIR:-/tmp}/modules-status.txt" m rc
    mkdir -p "$(dirname "$status_file")" 2>/dev/null || true
    echo "# autolinux modules — $(date -Is)" > "$status_file" 2>/dev/null || true

    # Tools the modules themselves rely on (fetching keys/scripts, editing
    # dconf lists), so any subset works on a fresh machine.
    if [ "${AUTOLINUX_DRY_RUN:-0}" != "1" ]; then
        rm -f "$(_apt_stamp)"
        apt_install curl ca-certificates gnupg git jq python3 software-properties-common dconf-cli \
            || log_warning "could not install prerequisites; some modules may fail"
    fi

    for m in "${MODULES_SELECTED[@]}"; do
        if module_detect "$m"; then
            log_skip "$m: already set up"
            MODULES_SKIPPED+=("$m"); echo "SKIPPED $m" >> "$status_file"
            continue
        fi
        if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then
            log_dryrun "$m: would install — ${MOD_META_DESC[$m]}"
            MODULES_DONE+=("$m"); echo "WOULD-INSTALL $m" >> "$status_file"
            continue
        fi
        log_header "$m — ${MOD_META_DESC[$m]}"
        rc=0
        _module_call "$m" mod_install || rc=$?
        if [ "$rc" -eq 0 ] && module_detect "$m"; then
            log_success "$m installed"
            MODULES_DONE+=("$m"); echo "DONE $m" >> "$status_file"
        else
            log_error "$m failed (rc=$rc)"
            MODULES_FAILED+=("$m"); echo "FAILED $m rc=$rc" >> "$status_file"
        fi
    done

    log_header "Summary"
    if [ "${AUTOLINUX_DRY_RUN:-0}" = "1" ]; then
        log_info "would install: ${MODULES_DONE[*]:-none}"
    else
        log_info "installed: ${MODULES_DONE[*]:-none}"
    fi
    log_info "already set up: ${MODULES_SKIPPED[*]:-none}"
    if [ "${#MODULES_FAILED[@]}" -gt 0 ]; then
        log_error "failed: ${MODULES_FAILED[*]} (re-run to retry; status in $status_file)"
        return 1
    fi
    return 0
}

# ---------- bootstrap.sh integration ----------
# bootstrap.sh resolves the selection once (flags or checklist), stores it in
# state.json and exports it as AUTOLINUX_MODULES (space-separated). Stages call
# these helpers with a filter:
#   apps     = everything except desktop-settings / gnome-extensions (stage 11)
#   <module> = just that module, if selected (stages 12 and 13)

_stage_modules() {
    local filter="$1" m out=()
    for m in ${AUTOLINUX_MODULES:-}; do
        case "$filter" in
            apps) [ "$m" = "desktop-settings" ] || [ "$m" = "gnome-extensions" ] || out+=("$m") ;;
            *)    [ "$m" = "$filter" ] && out+=("$m") ;;
        esac
    done
    echo "${out[*]}"
}

# True when every module for this stage already detects as set up.
modules_stage_detect() {
    local m
    for m in $(_stage_modules "$1"); do module_detect "$m" || return 1; done
    return 0
}

modules_stage_run() {
    [ "${#MOD_META_DESC[@]}" -gt 0 ] || modules_load_meta || return 1
    read -ra MODULES_SELECTED <<< "$(_stage_modules "$1")"
    [ "${#MODULES_SELECTED[@]}" -gt 0 ] || { log_skip "no modules selected for this stage"; return 0; }
    modules_run
}
