#!/bin/bash
# Run a reset/flash/OS-switch/long benchmark while holding the board lease.
# usage: S31_SESSION=name S31_REASON='flash A/B' s31-exclusive.sh command [args...]
set -u
ROOT=${ESP32S31_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
. "$ROOT/tools/s31-lease-common.sh"

if [ "$#" -lt 1 ]; then
    echo "usage: S31_SESSION=name S31_REASON=reason s31-exclusive.sh command [args...]" >&2
    exit 2
fi
# Nested users share a lease only while its ID and actual flock are live.
# A stale exported environment never grants a bypass by itself.
if s31_exclusive_valid "${S31_RUNTIME_DIR:-/tmp}"; then
    exec "$@"
fi
if [ "${S31_BOARD_EXCLUSIVE:-0}" = 1 ]; then
    unset S31_BOARD_EXCLUSIVE S31_EXCLUSIVE_ID
fi

RUNTIME=${S31_RUNTIME_DIR:-/tmp}
BOARD_LOCK=$RUNTIME/s31-board.lock
REQUESTS=$RUNTIME/s31-requests.log
OWNER_FILE=$RUNTIME/s31-exclusive.owner
OWNER=${S31_SESSION:-unlabeled}
REASON=${S31_REASON:-unspecified}
LOCK_TIMEOUT=${S31_LOCK_TIMEOUT:-60}
RID="$(date -u +%Y%m%dT%H%M%SZ).$$.$RANDOM"
LOG=$RUNTIME/s31out.log

if [ ! -d "$RUNTIME" ]; then
    echo "s31-exclusive: runtime directory missing: $RUNTIME" >&2
    exit 69
fi
if ! command -v flock >/dev/null 2>&1; then
    echo "s31-exclusive: flock is required" >&2
    exit 69
fi

exec 9>"$BOARD_LOCK"
if ! flock -x -w "$LOCK_TIMEOUT" 9; then
    echo "s31-exclusive: board is busy; see $OWNER_FILE" >&2
    exit 75
fi

request_event() {
    local event=$1 result=$2
    exec 7>>"$REQUESTS"
    flock -x 7
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$RID" "$OWNER" "$$" "$event" \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$result" "$REASON" >&7
    flock -u 7
    exec 7>&-
}

request_event exclusive-start -
printf '%s\n' "request=$RID" "owner=$OWNER" "pid=$$" "reason=$REASON" \
    "started=$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$OWNER_FILE"
export S31_BOARD_EXCLUSIVE=1
export S31_EXCLUSIVE_ID=$RID

# Ordinary descendants inherit the lease fd, so a background child cannot
# outlive the lease and race the next owner.  Long-lived daemon launchers must
# close fd 9 explicitly; this shell retains it for the whole command.
"$@"
RC=$?
request_event exclusive-end "$RC"
rm -f "$OWNER_FILE"
exit "$RC"
