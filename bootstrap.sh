#!/bin/bash
# autolinux bootstrap — state-machine orchestrator for safe Xubuntu→GNOME migration
# and the rest of the workstation setup.
#
# Run: sudo ./bootstrap.sh [flags]
# See ./bootstrap.sh --help for flag reference.

set -u
set -o pipefail
# NOT set -e: we want explicit error handling per stage so failure marks state correctly.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AUTOLINUX_REPO_DIR="$REPO_DIR"

# shellcheck source=lib/log.sh
source "$REPO_DIR/lib/log.sh"
# shellcheck source=lib/state.sh
source "$REPO_DIR/lib/state.sh"
# shellcheck source=lib/detect.sh
source "$REPO_DIR/lib/detect.sh"
# shellcheck source=lib/safety.sh
source "$REPO_DIR/lib/safety.sh"
# shellcheck source=lib/snapshot.sh
source "$REPO_DIR/lib/snapshot.sh"
# shellcheck source=lib/resume.sh
source "$REPO_DIR/lib/resume.sh"

# Ordered stage list. Each entry is "NN:slug"; the matching file is stages/NN-slug.sh
# and it must define functions sNN_detect / sNN_precheck (optional) / sNN_execute /
# sNN_verify (optional). It may set SNN_REQUIRES_REBOOT=1.
STAGES=(
    "00:preflight"
    "01:timeshift-snapshot"
    "02:hold-critical-packages"
    "03:detect-starting-de"
    "04:install-gnome-stack"
    "05:switch-display-manager"
    "06:arm-resume-and-reboot"
    "07:verify-gnome-session"
    "08:remove-xfce"
    "09:cleanup-xfce-configs"
    "10:system-config"
    "11:app-install"
    "12:desktop-config"
    "13:gnome-extensions"
    "14:unhold-packages"
    "15:done"
)

usage() {
    cat <<EOF
Usage: sudo ./bootstrap.sh [flags]

Orchestrates the safe Xubuntu→GNOME migration and workstation setup as a
state machine with checkpoints in /var/lib/autolinux/state.json. Stages that
require a reboot exit cleanly after arming a resume hook.

Flags:
  --resume                       Continue from the last checkpoint (used by resume hook)
  --status                       Print the state machine + last logs and exit
  --dry-run                      Print the plan without executing destructive actions
  --from <stage>                 Start at <stage>; previous stages must already be done
  --only <stage>                 Run exactly one stage
  --force-replay <stage>         Re-run a stage even if marked done
  --rollback                     Offer timeshift restore + remove holds + remove hooks
  --yes                          Accept all confirmation prompts
  --allow-pending-upgrades       Bypass the stage-00 'pending apt upgrades' guard
  --list-stages                  Print the stage list and exit
  -h, --help                     This message

Stages can be referenced by number ('06') or slug ('arm-resume-and-reboot') or
the full ID ('06-arm-resume-and-reboot').
EOF
}

# ---------- arg parsing ----------
ACTION=run
ONLY_STAGE=""
FROM_STAGE=""
FORCE_REPLAY=""
export AUTOLINUX_DRY_RUN=0
export AUTOLINUX_YES=0
export AUTOLINUX_ALLOW_PENDING_UPGRADES=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --resume)                   ACTION=run; shift ;;
        --status)                   ACTION=status; shift ;;
        --dry-run)                  AUTOLINUX_DRY_RUN=1; shift ;;
        --from)                     FROM_STAGE="$2"; shift 2 ;;
        --only)                     ONLY_STAGE="$2"; shift 2 ;;
        --force-replay)             FORCE_REPLAY="$2"; shift 2 ;;
        --rollback)                 ACTION=rollback; shift ;;
        --yes|-y)                   AUTOLINUX_YES=1; shift ;;
        --allow-pending-upgrades)   AUTOLINUX_ALLOW_PENDING_UPGRADES=1; shift ;;
        --list-stages)              ACTION=list; shift ;;
        -h|--help)                  usage; exit 0 ;;
        *) log_error "unknown flag: $1"; usage >&2; exit 2 ;;
    esac
done

# In --dry-run, redirect state to a scratch dir so we don't leave artifacts
# in /var/lib/autolinux. Status/list/rollback always read the real dir.
if [ "$AUTOLINUX_DRY_RUN" = "1" ] && [ "$ACTION" = "run" ]; then
    AUTOLINUX_STATE_DIR="$(mktemp -d -t autolinux-dryrun.XXXXXX)"
    AUTOLINUX_STATE_FILE="$AUTOLINUX_STATE_DIR/state.json"
    AUTOLINUX_LOG_DIR="$AUTOLINUX_STATE_DIR/log"
    export AUTOLINUX_STATE_DIR AUTOLINUX_STATE_FILE AUTOLINUX_LOG_DIR
    log_info "dry-run state dir: $AUTOLINUX_STATE_DIR (will be left for inspection)"
fi

# ---------- stage helpers ----------

# Resolve "06" or "arm-resume-and-reboot" or "06-arm-resume-and-reboot" → "06:arm-resume-and-reboot"
_resolve_stage() {
    local query="$1" entry num slug
    for entry in "${STAGES[@]}"; do
        num="${entry%%:*}"
        slug="${entry#*:}"
        if [ "$query" = "$num" ] || [ "$query" = "$slug" ] || [ "$query" = "$num-$slug" ]; then
            echo "$entry"
            return 0
        fi
    done
    return 1
}

_stage_file() {
    local entry="$1" num slug
    num="${entry%%:*}"
    slug="${entry#*:}"
    echo "$REPO_DIR/stages/${num}-${slug}.sh"
}

_stage_id() {
    # entry "06:arm-resume-and-reboot" → "06-arm-resume-and-reboot"
    echo "${1%%:*}-${1#*:}"
}

_stage_fn() {
    # entry "06:arm-resume-and-reboot", suffix "execute" → s06_execute
    local entry="$1" suffix="$2"
    echo "s${entry%%:*}_${suffix}"
}

_stage_reboot_var() {
    local entry="$1"
    echo "S${entry%%:*}_REQUIRES_REBOOT"
}

# Source a stage file. Each file is sourced afresh per call so any variable
# mutations are scoped (the function defs persist, which is fine — they are uniquely named).
_source_stage() {
    local entry="$1" file
    file="$(_stage_file "$entry")"
    [ -r "$file" ] || log_die "missing stage file: $file"
    # shellcheck source=/dev/null
    source "$file"
}

_call_or_default() {
    # _call_or_default <fn> <default-rc> [args...]
    local fn="$1" default_rc="$2"; shift 2
    if declare -F "$fn" >/dev/null; then
        "$fn" "$@"
    else
        return "$default_rc"
    fi
}

# ---------- top-level actions ----------

action_list() {
    log_header "Stage list"
    local entry
    for entry in "${STAGES[@]}"; do
        printf '  %s\n' "$(_stage_id "$entry")"
    done
}

action_status() {
    log_header "autolinux status"
    log_info "state dir : $AUTOLINUX_STATE_DIR"
    log_info "state file: $AUTOLINUX_STATE_FILE"
    log_info "log dir   : $AUTOLINUX_LOG_DIR"
    if [ ! -s "$AUTOLINUX_STATE_FILE" ]; then
        log_info "(no state.json — first run)"
        return 0
    fi
    state_dump
    echo
    log_header "Per-stage status"
    local entry status
    for entry in "${STAGES[@]}"; do
        status="$(state_stage_status "$(_stage_id "$entry")")"
        printf '  %-35s %s\n' "$(_stage_id "$entry")" "${status:-pending}"
    done
}

action_rollback() {
    require_root
    log_header "Rollback"
    log_warning "Rollback offers: (1) timeshift restore, (2) unhold packages, (3) remove resume hooks."
    log_warning "It will NOT undo successful purges or app installs."
    log_confirm "Proceed with rollback?" || { log_info "aborted"; return 0; }

    if command -v timeshift >/dev/null 2>&1; then
        log_info "available autolinux snapshots:"
        snapshot_list_ours | sed 's/^/    /'
        log_warning "To restore, run from a live USB or another session:"
        log_warning "  sudo timeshift --restore --snapshot <NAME>"
    fi

    local user holds
    user="$(real_user)"
    holds="$(state_get holds_added | jq -r '.[]?' 2>/dev/null)"
    if [ -z "$holds" ]; then
        # fall back to snapshot-from-state
        holds="$(jq -r '.holds_added[]?' < "$AUTOLINUX_STATE_FILE" 2>/dev/null)"
    fi
    if [ -n "$holds" ]; then
        log_info "releasing package holds:"
        # shellcheck disable=SC2086
        unhold_packages $holds
    fi
    resume_remove_hooks "$user"
    state_set status "rolled-back"
    log_success "rollback actions applied (any timeshift restore must be done manually)"
}

_print_untested_banner() {
    [ "${AUTOLINUX_SUPPRESS_UNTESTED_BANNER:-0}" = "1" ] && return 0
    log_warning "════════════════════════════════════════════════════════════════════"
    log_warning "  UNTESTED ON REAL HARDWARE (as of 2026-05-06)."
    log_warning "  The full Xubuntu→GNOME migration path has only been dry-run-tested."
    log_warning "  Run with --dry-run first. Test in a VM before live use."
    log_warning "  Suppress this banner with AUTOLINUX_SUPPRESS_UNTESTED_BANNER=1."
    log_warning "════════════════════════════════════════════════════════════════════"
}

action_run() {
    _print_untested_banner
    require_root
    state_init
    state_set status "in_progress"

    # Resolve --only / --from / --force-replay against the stage list.
    local only_resolved="" from_resolved="" replay_resolved=""
    if [ -n "$ONLY_STAGE" ]; then
        only_resolved="$(_resolve_stage "$ONLY_STAGE")" \
            || log_die "unknown stage: $ONLY_STAGE (try --list-stages)"
    fi
    if [ -n "$FROM_STAGE" ]; then
        from_resolved="$(_resolve_stage "$FROM_STAGE")" \
            || log_die "unknown stage: $FROM_STAGE"
    fi
    if [ -n "$FORCE_REPLAY" ]; then
        replay_resolved="$(_resolve_stage "$FORCE_REPLAY")" \
            || log_die "unknown stage: $FORCE_REPLAY"
    fi

    local started=0 entry id status detect_fn precheck_fn execute_fn verify_fn reboot_var rc
    for entry in "${STAGES[@]}"; do
        id="$(_stage_id "$entry")"

        # --only filter
        if [ -n "$only_resolved" ] && [ "$entry" != "$only_resolved" ]; then
            continue
        fi
        # --from filter (skip until we hit it)
        if [ -n "$from_resolved" ] && [ "$started" -eq 0 ]; then
            if [ "$entry" = "$from_resolved" ]; then started=1; else continue; fi
        fi

        status="$(state_stage_status "$id")"
        _source_stage "$entry"

        detect_fn="$(_stage_fn "$entry" detect)"
        precheck_fn="$(_stage_fn "$entry" precheck)"
        execute_fn="$(_stage_fn "$entry" execute)"
        verify_fn="$(_stage_fn "$entry" verify)"
        reboot_var="$(_stage_reboot_var "$entry")"

        # If marked done, verify it still detects (defense in depth).
        if [ "$status" = "done" ] && [ "$entry" != "$replay_resolved" ]; then
            if _call_or_default "$detect_fn" 0; then
                log_skip "[$id] already done"
                continue
            else
                log_error "[$id] state says done, but detection failed (drift detected)."
                log_error "Re-run with: --force-replay $id"
                exit 3
            fi
        fi

        # If pending and detect already passes, mark done without executing (this lets
        # bootstrap pick up a machine where someone did the work manually — exactly
        # the situation on this user's box, where GNOME is already live).
        if [ "$entry" != "$replay_resolved" ] && _call_or_default "$detect_fn" 1; then
            log_skip "[$id] already satisfied (skipping)"
            state_stage_set "$id" done
            continue
        fi

        log_header "[$id] starting"
        AUTOLINUX_LOG_FILE="$AUTOLINUX_LOG_DIR/${id}-$(date +%Y%m%d-%H%M%S).log"
        export AUTOLINUX_LOG_FILE
        : > "$AUTOLINUX_LOG_FILE" 2>/dev/null || true

        if ! _call_or_default "$precheck_fn" 0; then
            log_error "[$id] precheck failed — aborting."
            state_stage_set "$id" failed
            state_set status "failed"
            exit 4
        fi

        state_stage_set "$id" running

        rc=0
        "$execute_fn" || rc=$?
        if [ "$rc" -ne 0 ]; then
            log_error "[$id] execute failed (rc=$rc)"
            state_stage_set "$id" failed
            state_set status "failed"
            exit 5
        fi

        if ! _call_or_default "$verify_fn" 0; then
            log_error "[$id] verify failed"
            state_stage_set "$id" failed
            state_set status "failed"
            exit 6
        fi

        state_stage_set "$id" done
        log_success "[$id] done"

        # Reboot handoff?
        local reboot_now=0
        if [ -n "${!reboot_var:-}" ] && [ "${!reboot_var}" = "1" ]; then
            reboot_now=1
        fi
        if [ "$reboot_now" = "1" ] && [ "${AUTOLINUX_DRY_RUN}" != "1" ]; then
            log_warning "[$id] requests a reboot."
            local user
            user="$(real_user)"
            resume_install_hooks "$REPO_DIR" "$user"
            log_info "resume hook installed for user '$user'"
            if log_confirm "Reboot now?"; then
                log_info "rebooting…"
                sync
                systemctl reboot
                exit 0
            else
                log_warning "Reboot deferred. Run 'sudo reboot' manually; bootstrap will resume on next login."
                exit 0
            fi
        fi

        if [ -n "$only_resolved" ]; then
            break
        fi
    done

    state_set status "done"
    log_header "All stages complete"
}

# ---------- dispatch ----------

case "$ACTION" in
    list)     action_list ;;
    status)   action_status ;;
    rollback) action_rollback ;;
    run)      action_run ;;
    *)        usage >&2; exit 2 ;;
esac
