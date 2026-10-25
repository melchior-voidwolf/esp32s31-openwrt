#!/bin/bash
# Restore a complete backup produced by backup-s31-flash.sh.
set -euo pipefail

ROOT="${ESP32S31_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
. "$ROOT/tools/s31-lease-common.sh"
if ! s31_exclusive_valid "${S31_RUNTIME_DIR:-/tmp}"; then
  export S31_SESSION="${S31_SESSION:-openwrt}"
  export S31_REASON="${S31_REASON:-restore complete flash backup (erase all)}"
  exec "$ROOT/tools/s31-exclusive.sh" "$0" "$@"
fi
PORT="${S31_PORT:-/dev/ttyUSB0}"
ESPT="${ESPTOOL:-/home/kail/.espressif/python_env/idf6.1_py3.12_env/bin/esptool}"
INPUT="${1:-}"
[ -n "$INPUT" ] || { echo "usage: $0 BACKUP_DIR|full.img" >&2; exit 2; }
[ -d "$INPUT" ] && INPUT="$INPUT/full.img"
[ -f "$INPUT" ] || { echo "missing backup image: $INPUT" >&2; exit 1; }
DIR=$(dirname "$INPUT")
[ "$(stat -c%s "$INPUT")" = 16777216 ] || { echo "backup is not 16 MiB: $INPUT" >&2; exit 1; }
[ -f "$DIR/SHA256SUMS" ] || { echo "missing backup checksums: $DIR/SHA256SUMS" >&2; exit 1; }
grep -q ' full.img$' "$DIR/SHA256SUMS" || { echo "SHA256SUMS has no full.img entry" >&2; exit 1; }
(cd "$DIR" && sha256sum -c SHA256SUMS)
. "$ROOT/tools/flash-openwrt-console.sh"
trap owrt_console_cleanup EXIT

flash() {
  local attempt
  for attempt in 1 2 3; do
    if timeout 900 "$ESPT" --chip esp32s31 -p "$PORT" -b 230400 \
      --before default-reset --after hard-reset write-flash 0x0 "$INPUT" \
      > /tmp/ef-openwrt-restore.log 2>&1; then
      return 0
    fi
    echo "retry $attempt for backup restore"
    sleep 4
  done
  return 1
}

owrt_stop_console
flash || { echo "BACKUP RESTORE FAILED"; tail -8 /tmp/ef-openwrt-restore.log; exit 1; }
echo "BACKUP_RESTORE_OK $INPUT"
owrt_start_console
owrt_console_ready
