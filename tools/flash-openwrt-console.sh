#!/bin/bash
# Console lifecycle helpers for flash-openwrt-*.sh.  The caller installs
# `trap owrt_console_cleanup EXIT` after setting ROOT and PORT.

OWRT_CONSOLE_ENGAGED=${OWRT_CONSOLE_ENGAGED:-0}
OWRT_CONSOLE_STOPPED=${OWRT_CONSOLE_STOPPED:-0}
OWRT_READY_ATTEMPTED=${OWRT_READY_ATTEMPTED:-0}

owrt_sync_console() {
  # Flush UBIFS before esptool resets the board, but do not prevent recovery
  # flashing when the running OS or console is already unavailable.
  if [ -p "${S31_RUNTIME_DIR:-/tmp}/s31in" ]; then
    S31_SESSION="${S31_SESSION:-openwrt}" bash "$ROOT/tools/srun.sh" 'sync' 5 || \
      echo "warning: pre-flash sync failed; continuing recovery flash" >&2
  fi
}

owrt_stop_console() {
  OWRT_CONSOLE_ENGAGED=1
  if command -v fuser >/dev/null 2>&1; then
    local pid
    for pid in $(fuser "$PORT" 2>/dev/null || true); do
      if [ -r "/proc/$pid/cmdline" ] && tr '\000' ' ' < "/proc/$pid/cmdline" | grep -Eq '(s31-uartd|console-daemon)[.]py'; then
        kill "$pid" 2>/dev/null || true
      fi
    done
  else
    pkill -f "^python3 $ROOT/tools/(console-daemon|s31-uartd)[.]py$" 2>/dev/null || true
  fi
  OWRT_CONSOLE_STOPPED=1
  sleep 2
}

owrt_start_console() {
  env -u S31_BOARD_EXCLUSIVE -u S31_EXCLUSIVE_ID \
    S31_PORT="$PORT" setsid -f nohup python3 "$ROOT/tools/s31-uartd.py" \
    9>&- > /tmp/s31-daemon.log 2>&1 < /dev/null
  OWRT_CONSOLE_STOPPED=0
  echo "console-daemon restarted without inherited lease"
}

owrt_console_ready() {
  local attempts="${1:-24}"
  local delay="${2:-5}"
  OWRT_READY_ATTEMPTED=1
  S31_BOOT_ATTEMPTS="$attempts" S31_BOOT_DELAY="$delay" \
    bash "$ROOT/tools/wait-openwrt-boot.sh"
}

owrt_console_cleanup() {
  local rc=$?
  if [ "$OWRT_CONSOLE_ENGAGED" = 1 ]; then
    if [ "$OWRT_CONSOLE_STOPPED" = 1 ]; then
      owrt_start_console || echo "warning: failed to restart console-daemon" >&2
    fi
    if [ "$rc" -ne 0 ] && [ "$OWRT_READY_ATTEMPTED" = 0 ]; then
      owrt_console_ready 3 3 || echo "warning: recovery boot-ready check failed" >&2
    fi
  fi
  exit "$rc"
}
