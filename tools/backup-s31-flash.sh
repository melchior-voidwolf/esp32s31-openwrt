#!/bin/bash
# Read the complete flash twice and keep a verified recovery backup.
set -euo pipefail

ROOT="${ESP32S31_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
. "$ROOT/tools/s31-lease-common.sh"
if ! s31_exclusive_valid "${S31_RUNTIME_DIR:-/tmp}"; then
  export S31_SESSION="${S31_SESSION:-openwrt}"
  export S31_REASON="${S31_REASON:-backup complete S31 flash}"
  exec "$ROOT/tools/s31-exclusive.sh" "$0" "$@"
fi
PORT="${S31_PORT:-/dev/ttyUSB0}"
ESPT="${ESPTOOL:-/home/kail/.espressif/python_env/idf6.1_py3.12_env/bin/esptool}"
OUT="${1:-$ROOT/backups/$(date -u +%Y%m%dT%H%M%SZ)-openwrt}"
mkdir -p "$OUT"
. "$ROOT/tools/flash-openwrt-console.sh"
trap owrt_console_cleanup EXIT

read_once() {
  local output="$1" log="$2" attempt
  for attempt in 1 2 3; do
    if timeout 900 "$ESPT" --chip esp32s31 -p "$PORT" -b 230400 \
      --before default-reset --after hard-reset read-flash 0x0 0x1000000 "$output" \
      > "$log" 2>&1; then
      return 0
    fi
    echo "retry $attempt for complete flash read"
    sleep 4
  done
  return 1
}

owrt_stop_console
read_once "$OUT/readback-1.img" "$OUT/readback-1.log"
read_once "$OUT/readback-2.img" "$OUT/readback-2.log"
cmp -s "$OUT/readback-1.img" "$OUT/readback-2.img" || {
  echo "backup readback mismatch: $OUT" >&2
  exit 1
}
cp "$OUT/readback-1.img" "$OUT/full.img"
(
  cd "$OUT"
  sha256sum full.img readback-1.img readback-2.img > SHA256SUMS
)
printf 'backup_time=%s\nport=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PORT" > "$OUT/INFO"
echo "FLASH_BACKUP_OK $OUT"
owrt_start_console
owrt_console_ready
