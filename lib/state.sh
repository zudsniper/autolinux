# shellcheck shell=bash
# State machine helpers. State lives at $AUTOLINUX_STATE_DIR (default /var/lib/autolinux).
#
# All writes are atomic (tmp-file + rename). All reads tolerate a missing/empty state.json
# by treating it as "first run".
#
# Public functions:
#   state_init         — ensure state dir + state.json exist
#   state_get FIELD    — print top-level field; empty if missing
#   state_set FIELD V  — set top-level field
#   state_stage_status STAGE     — print "pending"|"running"|"done"|"failed"|"" for a stage
#   state_stage_set STAGE STATUS — set stage status (auto-stamps ts)
#   state_stage_meta STAGE KEY VALUE — set arbitrary stage metadata key
#   state_array_append FIELD VALUE — append to a top-level array (e.g. holds_added)
#   state_dump         — pretty-print full state
#   state_reset        — wipe state (with confirm)

if [ -n "${_AUTOLINUX_STATE_SH_LOADED:-}" ]; then return 0; fi
_AUTOLINUX_STATE_SH_LOADED=1

# shellcheck source=lib/log.sh
[ -n "${_AUTOLINUX_LOG_SH_LOADED:-}" ] || { log_error() { echo "[ERROR] $*" >&2; }; log_die() { echo "[ERROR] $*" >&2; exit 1; }; }

AUTOLINUX_STATE_DIR="${AUTOLINUX_STATE_DIR:-/var/lib/autolinux}"
AUTOLINUX_STATE_FILE="$AUTOLINUX_STATE_DIR/state.json"
AUTOLINUX_LOG_DIR="$AUTOLINUX_STATE_DIR/log"

_state_require_jq() {
    command -v jq >/dev/null 2>&1 || log_die "jq is required. Run: sudo apt-get install -y jq"
}

_state_atomic_write() {
    # stdin → $AUTOLINUX_STATE_FILE atomically.
    local tmp
    tmp="$(mktemp "${AUTOLINUX_STATE_FILE}.XXXXXX")"
    cat > "$tmp"
    # Validate the candidate parses before publishing.
    jq -e . < "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; log_die "refusing to write malformed state.json"; }
    mv "$tmp" "$AUTOLINUX_STATE_FILE"
    chmod 0644 "$AUTOLINUX_STATE_FILE"
}

state_init() {
    _state_require_jq
    mkdir -p "$AUTOLINUX_STATE_DIR" "$AUTOLINUX_LOG_DIR"
    if [ ! -s "$AUTOLINUX_STATE_FILE" ] || ! jq -e . < "$AUTOLINUX_STATE_FILE" >/dev/null 2>&1; then
        local now host user
        now="$(date -Iseconds)"
        host="$(hostname 2>/dev/null || echo unknown)"
        user="${SUDO_USER:-${USER:-unknown}}"
        local kernel os_id os_ver
        kernel="$(uname -r 2>/dev/null || echo unknown)"
        os_id="$(. /etc/os-release 2>/dev/null && echo "$ID" || echo unknown)"
        os_ver="$(. /etc/os-release 2>/dev/null && echo "$VERSION_ID" || echo unknown)"
        jq -n \
            --arg started_at "$now" \
            --arg host "$host" \
            --arg user "$user" \
            --arg kernel "$kernel" \
            --arg os_id "$os_id" \
            --arg os_ver "$os_ver" \
            '{
                version: 1,
                status: "in_progress",
                started_at: $started_at,
                host: $host,
                user: $user,
                kernel_at_start: $kernel,
                os_id: $os_id,
                os_version: $os_ver,
                starting_de: null,
                starting_dm: null,
                current_stage: null,
                stages: {},
                holds_added: [],
                purged: [],
                config_backups: []
            }' | _state_atomic_write
    fi
}

state_get() {
    _state_require_jq
    [ -s "$AUTOLINUX_STATE_FILE" ] || { echo ""; return 0; }
    jq -r --arg k "$1" '.[$k] // empty' < "$AUTOLINUX_STATE_FILE"
}

state_set() {
    state_init
    local key="$1" val="$2"
    jq --arg k "$key" --arg v "$val" '.[$k] = $v' < "$AUTOLINUX_STATE_FILE" | _state_atomic_write
}

state_stage_status() {
    _state_require_jq
    [ -s "$AUTOLINUX_STATE_FILE" ] || { echo ""; return 0; }
    jq -r --arg s "$1" '.stages[$s].status // empty' < "$AUTOLINUX_STATE_FILE"
}

state_stage_set() {
    state_init
    local stage="$1" status="$2"
    local ts
    ts="$(date -Iseconds)"
    jq --arg s "$stage" --arg st "$status" --arg ts "$ts" \
        '.stages[$s] = ((.stages[$s] // {}) + {status: $st, ts: $ts}) | .current_stage = $s' \
        < "$AUTOLINUX_STATE_FILE" | _state_atomic_write
}

state_stage_meta() {
    state_init
    local stage="$1" key="$2" value="$3"
    jq --arg s "$stage" --arg k "$key" --arg v "$value" \
        '.stages[$s] = ((.stages[$s] // {}) + {($k): $v})' \
        < "$AUTOLINUX_STATE_FILE" | _state_atomic_write
}

state_array_append() {
    state_init
    local field="$1" value="$2"
    jq --arg f "$field" --arg v "$value" \
        '.[$f] = ((.[$f] // []) + [$v] | unique)' \
        < "$AUTOLINUX_STATE_FILE" | _state_atomic_write
}

state_array_replace() {
    state_init
    local field="$1"; shift
    local items_json
    if [ "$#" -eq 0 ]; then
        items_json='[]'
    else
        items_json="$(printf '%s\n' "$@" | jq -R . | jq -s .)"
    fi
    jq --arg f "$field" --argjson v "$items_json" '.[$f] = $v' < "$AUTOLINUX_STATE_FILE" | _state_atomic_write
}

state_dump() {
    if [ -s "$AUTOLINUX_STATE_FILE" ] && jq -e . < "$AUTOLINUX_STATE_FILE" >/dev/null 2>&1; then
        jq . < "$AUTOLINUX_STATE_FILE"
    else
        echo "(no state.json yet — first run)"
    fi
}

state_reset() {
    if [ -e "$AUTOLINUX_STATE_FILE" ]; then
        local backup="$AUTOLINUX_STATE_FILE.bak.$(date +%Y%m%d-%H%M%S)"
        mv "$AUTOLINUX_STATE_FILE" "$backup"
        echo "Previous state backed up to $backup"
    fi
}
