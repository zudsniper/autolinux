#!/bin/bash
# autolinux module installer — set up this workstation's apps, desktop and
# tooling on an Ubuntu GNOME machine, interactively or entirely from flags.
#
#   sudo ./install.sh                         # interactive checklist (full profile preselected)
#   sudo ./install.sh --yes                   # full profile, no questions
#   sudo ./install.sh --profile minimal --yes
#   sudo ./install.sh --only ringboard,kitty  # just these (deps are added automatically)
#   sudo ./install.sh --with portainer --without steam,obs --yes
#   sudo ./install.sh --dry-run               # report what is missing, change nothing
#   ./install.sh --doctor                     # what's already installed? (all modules)
#   ./install.sh --list-modules
#
# Every run starts with the same check as --doctor: modules that are already
# set up are listed as such and skipped, the rest are installed. Re-running is
# always safe. For a fresh Xubuntu → GNOME migration use
# bootstrap.sh, which calls the same modules from its stages.

set -u
set -o pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AUTOLINUX_REPO_DIR="$REPO_DIR"

source "$REPO_DIR/lib/log.sh"
source "$REPO_DIR/lib/detect.sh"
source "$REPO_DIR/lib/safety.sh"
source "$REPO_DIR/lib/modules.sh"

usage() {
    cat <<EOF
Usage: sudo ./install.sh [flags]

Selection (applied in this order):
  --profile <full|minimal>   Starting set of modules (default: full)
  --only <list>              Start from exactly these modules/groups instead of a profile
  --with <list>              Add modules/groups
  --without <list>           Remove modules/groups
  <list> is comma-separated module or group names, e.g. "ringboard,dev".

Mode:
  -i, --interactive          Show the checklist (default when run in a terminal)
  -y, --yes, --non-interactive
                             No checklist, no prompts
  -n, --dry-run              Only report what each module would do
  --doctor                   Check which modules are already installed and exit
                             (all modules unless --profile/--only/--with/--without
                             narrow it; sudo gives the most accurate answer)
  --list-modules             Print modules, groups and profiles, then exit
  -h, --help                 This message

Environment overrides (put them after sudo, which drops the caller's env):
  sudo AUTOLINUX_UFW_ENABLE=1 RINGBOARD_VERSION=0.15.0 ./install.sh ...
  AUTOLINUX_UFW_ENABLE  1 = enable UFW with SSH allowed (default: install only)
  RINGBOARD_VERSION     crate version to install (default 0.15.0)
  RINGBOARD_SHORTCUT    GNOME binding for the Ringboard popup (default <Ctrl><Super><Alt>v)
  NVM_VERSION           nvm release tag
EOF
}

PROFILE=full PROFILE_SET=0 ONLY="" WITH="" WITHOUT="" INTERACTIVE="" ACTION=run
export AUTOLINUX_DRY_RUN="${AUTOLINUX_DRY_RUN:-0}" AUTOLINUX_YES="${AUTOLINUX_YES:-0}"

need_val() { if [ "$#" -lt 2 ] || [ -z "$2" ]; then log_die "$1 needs a value"; fi; }
while [ "$#" -gt 0 ]; do
    case "$1" in
        --profile|--only|--with|--without) need_val "$@" ;;
    esac
    case "$1" in
        --profile)              PROFILE="$2"; PROFILE_SET=1; shift 2 ;;
        --only)                 ONLY="$2"; shift 2 ;;
        --with)                 WITH="$2"; shift 2 ;;
        --without)              WITHOUT="$2"; shift 2 ;;
        -i|--interactive)       INTERACTIVE=1; shift ;;
        -y|--yes|--non-interactive) INTERACTIVE=0; AUTOLINUX_YES=1; shift ;;
        -n|--dry-run)           AUTOLINUX_DRY_RUN=1; shift ;;
        --list-modules)         ACTION=list; shift ;;
        --doctor)               ACTION=doctor; shift ;;
        -h|--help)              usage; exit 0 ;;
        *) log_error "unknown flag: $1"; usage >&2; exit 2 ;;
    esac
done

case "$PROFILE" in full|minimal) ;; *) log_die "unknown profile: $PROFILE (full|minimal)" ;; esac

modules_load_meta || exit 1

if [ "$ACTION" = "list" ]; then
    modules_list
    exit 0
fi

if [ "$ACTION" = "doctor" ]; then
    # No selection flags: check every module, opt-in ones included.
    if [ "$PROFILE_SET" = "0" ] && [ -z "$ONLY$WITH$WITHOUT" ]; then
        ONLY="$(IFS=,; echo "${MODULE_ORDER[*]}")"
    fi
    modules_select "$PROFILE" "$ONLY" "$WITH" "$WITHOUT" 0 >/dev/null || exit 2
    log_header "autolinux doctor — user: $(real_user), session: $(detect_session_type)"
    [ "$(id -u)" = 0 ] || log_warning "not root: a few checks (e.g. ufw status) may read as missing; sudo is more accurate"
    modules_doctor "${MODULES_SELECTED[@]}"
    [ "${#DOCTOR_MISSING[@]}" -eq 0 ] || log_info "install the missing ones: sudo ./install.sh --only $(IFS=,; echo "${DOCTOR_MISSING[*]}")"
    exit 0
fi

# Default: interactive only when we have a terminal and --yes wasn't given.
if [ -z "$INTERACTIVE" ]; then
    if [ -t 0 ] && [ "$AUTOLINUX_YES" != "1" ] && [ "$AUTOLINUX_DRY_RUN" != "1" ]; then
        INTERACTIVE=1
    else
        INTERACTIVE=0
    fi
fi

require_root
require_ubuntu || log_warning "not Ubuntu — package names may not match"
[ "$(detect_de)" = "gnome" ] || log_warning "desktop is '$(detect_de)', not GNOME — desktop modules may fail"

export AUTOLINUX_LOG_DIR="${AUTOLINUX_LOG_DIR:-/var/log/autolinux}"
[ "$AUTOLINUX_DRY_RUN" = "1" ] && AUTOLINUX_LOG_DIR="$(mktemp -d -t autolinux-dryrun.XXXXXX)"
mkdir -p "$AUTOLINUX_LOG_DIR"

modules_select "$PROFILE" "$ONLY" "$WITH" "$WITHOUT" "$INTERACTIVE" || exit 2
[ "${#MODULES_SELECTED[@]}" -gt 0 ] || { log_info "nothing selected"; exit 0; }

sel_desc="profile: $PROFILE"; [ -n "$ONLY" ] && sel_desc="only: $ONLY"
log_header "autolinux — user: $(real_user), session: $(detect_session_type), $sel_desc"
log_info "modules: ${MODULES_SELECTED[*]}"
[ "$AUTOLINUX_DRY_RUN" = "1" ] && log_info "dry-run: nothing will be changed"

modules_run
