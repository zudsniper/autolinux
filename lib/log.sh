# shellcheck shell=bash
# Shared logging functions. Source this from any script that wants colored output.
# Originally extracted from gnome_extensions.sh:6-34.
#
# Set AUTOLINUX_LOG_FILE to also tee everything to a file.
# Set NO_COLOR=1 to disable ANSI colors (also disabled automatically when stdout is not a TTY).

if [ -n "${_AUTOLINUX_LOG_SH_LOADED:-}" ]; then return 0; fi
_AUTOLINUX_LOG_SH_LOADED=1

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    _LOG_RED='\033[0;31m'
    _LOG_GREEN='\033[0;32m'
    _LOG_YELLOW='\033[1;33m'
    _LOG_BLUE='\033[0;34m'
    _LOG_BOLD='\033[1m'
    _LOG_NC='\033[0m'
else
    _LOG_RED=''; _LOG_GREEN=''; _LOG_YELLOW=''; _LOG_BLUE=''; _LOG_BOLD=''; _LOG_NC=''
fi

_log_write() {
    local line="$1"
    printf '%b\n' "$line"
    if [ -n "${AUTOLINUX_LOG_FILE:-}" ]; then
        # Strip ANSI for the file copy.
        printf '%s\n' "$(printf '%b' "$line" | sed 's/\x1b\[[0-9;]*m//g')" >> "$AUTOLINUX_LOG_FILE" 2>/dev/null || true
    fi
}

log_info()    { _log_write "${_LOG_BLUE}[INFO]${_LOG_NC} $*"; }
log_success() { _log_write "${_LOG_GREEN}[OK]${_LOG_NC} $*"; }
log_warning() { _log_write "${_LOG_YELLOW}[WARN]${_LOG_NC} $*"; }
log_error()   { _log_write "${_LOG_RED}[ERROR]${_LOG_NC} $*" >&2; }
log_skip()    { _log_write "${_LOG_YELLOW}[SKIP]${_LOG_NC} $*"; }
log_dryrun()  { _log_write "${_LOG_YELLOW}[DRY-RUN]${_LOG_NC} $*"; }

log_header() {
    _log_write ""
    _log_write "${_LOG_BOLD}${_LOG_BLUE}━━━ $* ━━━${_LOG_NC}"
}

log_die() {
    log_error "$*"
    exit 1
}

# Confirm prompt that respects --yes via AUTOLINUX_YES=1.
# Usage: log_confirm "Proceed?" || return 1
log_confirm() {
    local prompt="$1"
    if [ "${AUTOLINUX_YES:-0}" = "1" ]; then
        log_info "auto-yes: $prompt"
        return 0
    fi
    local ans
    read -r -p "$(printf '%b' "${_LOG_YELLOW}[?]${_LOG_NC} $prompt [y/N]: ")" ans
    [[ "$ans" =~ ^[Yy]$ ]]
}
