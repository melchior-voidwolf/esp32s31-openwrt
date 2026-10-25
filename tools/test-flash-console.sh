#!/bin/bash
# Host-only lifecycle tests for flash-openwrt-console.sh.
set -euo pipefail
ROOT=${ESP32S31_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
. "$ROOT/tools/flash-openwrt-console.sh"
TMP=$(mktemp -d /tmp/s31-console-lifecycle.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
LOG=$TMP/actions

owrt_start_console() {
  echo start >> "$LOG"
  OWRT_CONSOLE_STOPPED=0
}
owrt_console_ready() {
  echo ready >> "$LOG"
  OWRT_READY_ATTEMPTED=1
}

run_case() {
  local engaged=$1 stopped=$2 attempted=$3 expected_rc=$4
  : > "$LOG"
  set +e
  (
    OWRT_CONSOLE_ENGAGED=$engaged
    OWRT_CONSOLE_STOPPED=$stopped
    OWRT_READY_ATTEMPTED=$attempted
    ( exit "$expected_rc" )
    owrt_console_cleanup
  )
  RC=$?
  set -e
  [ "$RC" -eq "$expected_rc" ] || {
    echo "wrong rc: wanted $expected_rc got $RC" >&2
    exit 1
  }
}

run_case 1 1 0 7
[ "$(cat "$LOG")" = $'start\nready' ] || { echo "missing failure recovery: $(cat "$LOG")" >&2; exit 1; }
run_case 0 0 0 5
[ ! -s "$LOG" ] || { echo "validation failure touched console: $(cat "$LOG")" >&2; exit 1; }
run_case 1 0 1 0
[ ! -s "$LOG" ] || { echo "success path duplicated recovery: $(cat "$LOG")" >&2; exit 1; }
run_case 1 0 1 2
[ ! -s "$LOG" ] || { echo "ready failure duplicated recovery: $(cat "$LOG")" >&2; exit 1; }
echo FLASH_CONSOLE_CLEANUP_PASS
