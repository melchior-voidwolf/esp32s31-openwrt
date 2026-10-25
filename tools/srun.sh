#!/bin/bash
# Send one command through the shared UART daemon and print only its output window.
# usage: S31_SESSION=linux-flash srun.sh "command" [wait_seconds]
set -u
ROOT=${ESP32S31_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
. "$ROOT/tools/s31-lease-common.sh"

RUNTIME=${S31_RUNTIME_DIR:-/tmp}
FIFO=$RUNTIME/s31in
LOG=$RUNTIME/s31out.log
BOARD_LOCK=$RUNTIME/s31-board.lock
COMMAND_LOCK=$RUNTIME/s31-command.lock
REQUESTS=$RUNTIME/s31-requests.log
CMD=${1-}
WAIT=${2:-5}
OWNER=${S31_SESSION:-unlabeled}
LOCK_TIMEOUT=${S31_LOCK_TIMEOUT:-60}
RID="$(date -u +%Y%m%dT%H%M%SZ).$$.$RANDOM"
MARKER=${S31_DONE_MARKER:-}
case $MARKER in
    *[!A-Za-z0-9_.-]*) echo "srun: invalid S31_DONE_MARKER" >&2; exit 2 ;;
esac
if [ -n "$MARKER" ]; then
    case $WAIT in ''|*[!0-9]*) echo "srun: marker timeout must be a positive integer" >&2; exit 2 ;; esac
    [ "$WAIT" -gt 0 ] || { echo "srun: marker timeout must be positive" >&2; exit 2; }
fi

if [ -z "$CMD" ] || [ "$#" -gt 2 ]; then
    echo "usage: S31_SESSION=name srun.sh 'command' [wait_seconds]" >&2
    exit 2
fi
if ! command -v flock >/dev/null 2>&1; then
    echo "srun: flock is required" >&2
    exit 69
fi
if [ ! -d "$RUNTIME" ] || [ ! -p "$FIFO" ]; then
    echo "srun: shared UART daemon is not ready ($FIFO missing)" >&2
    exit 69
fi
touch "$LOG"

request_event() {
    local event=$1 offset=$2 result=$3
    exec 7>>"$REQUESTS"
    flock -x 7
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$RID" "$OWNER" "$$" "$event" \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$offset" "$result" >&7
    flock -u 7
    exec 7>&-
}

# Normal lock order is board -> command.  A nested request bypasses only the
# board lock after proving its lease is live; command serialization still
# applies so concurrent nested clients cannot mix their output windows.
if [ "${S31_BOARD_EXCLUSIVE:-0}" = 1 ]; then
    if ! s31_exclusive_valid "$RUNTIME"; then
        echo "srun: stale or invalid exclusive lease" >&2
        exit 75
    fi
else
    exec 9>"$BOARD_LOCK"
    if ! flock -s -w "$LOCK_TIMEOUT" 9; then
        echo "srun: board is exclusively busy; see $RUNTIME/s31-exclusive.owner" >&2
        exit 75
    fi
fi
exec 8>"$COMMAND_LOCK"
if ! flock -x -w "$LOCK_TIMEOUT" 8; then
    echo "srun: another console command is still running" >&2
    exit 75
fi

OFF=$(wc -c < "$LOG")
request_event start "$OFF" -
PAYLOAD=$CMD
if [ -n "$MARKER" ]; then
    PAYLOAD="$CMD; __s31_rc=\$?; printf '\\n$MARKER:%s\\n' \"\$__s31_rc\""
fi
python3 -I "$ROOT/tools/s31-fifo-send.py" "$FIFO" "$PAYLOAD" "${S31_SEND_TIMEOUT:-5}"
SEND_RC=$?
if [ "$SEND_RC" -ne 0 ]; then
    request_event error "$OFF" "$SEND_RC"
    echo "srun: failed to write $FIFO" >&2
    exit "$SEND_RC"
fi

if [ -n "$MARKER" ]; then
    START_SECONDS=$SECONDS
    LINE=
    while [ $((SECONDS - START_SECONDS)) -le "$WAIT" ]; do
        CANDIDATES=$(tail -c +$((OFF + 1)) "$LOG" | tr -d '\r' | grep -F "$MARKER:" || true)
        while IFS= read -r candidate; do
            case $candidate in "$MARKER":*) LINE=$candidate ;; esac
        done <<< "$CANDIDATES"
        [ -n "$LINE" ] && break
        sleep 1
    done
    END=$(wc -c < "$LOG")
    if [ -z "$LINE" ]; then
        request_event error "$END" timeout
        tail -c +$((OFF + 1)) "$LOG" | head -c $((END - OFF))
        echo "srun: board command did not complete within $WAIT seconds" >&2
        exit 124
    fi
    RC=${LINE#"$MARKER":}
    case $RC in ''|*[!0-9]*)
        request_event error "$END" bad-marker
        tail -c +$((OFF + 1)) "$LOG" | head -c $((END - OFF))
        echo "srun: invalid completion marker" >&2
        exit 1
        ;;
    esac
    request_event end "$END" "$RC"
    tail -c +$((OFF + 1)) "$LOG" | head -c $((END - OFF))
    exit "$RC"
fi

sleep "$WAIT"
END=$(wc -c < "$LOG")
request_event end "$END" done
tail -c +$((OFF + 1)) "$LOG" | head -c $((END - OFF))
