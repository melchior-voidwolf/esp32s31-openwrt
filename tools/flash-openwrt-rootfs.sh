#!/bin/bash
# flash-openwrt-rootfs.sh — flash OpenWrt rootfs.squashfs @0xa20000.
set -euo pipefail

ROOT="${ESP32S31_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
. "$ROOT/tools/s31-lease-common.sh"
if ! s31_exclusive_valid "${S31_RUNTIME_DIR:-/tmp}"; then
  export S31_SESSION="${S31_SESSION:-openwrt}"
  export S31_REASON="${S31_REASON:-flash OpenWrt rootfs}"
  exec "$ROOT/tools/s31-exclusive.sh" "$0" "$@"
fi
PORT="${S31_PORT:-/dev/ttyUSB0}"
ESPT="${ESPTOOL:-/home/kail/.espressif/python_env/idf6.1_py3.12_env/bin/esptool}"
. "$ROOT/tools/flash-openwrt-console.sh"
trap owrt_console_cleanup EXIT
RFS="${1:-$ROOT/build/korvo1-openwrt/rootfs.squashfs}"

python3 -I "$ROOT/tools/validate-openwrt-images.py" --rootfs "$RFS"
owrt_stop_console

flash() {
  local attempt
  for attempt in 1 2 3 4 5; do
    if timeout 300 "$ESPT" --chip esp32s31 -p "$PORT" -b 230400 \
      --before default-reset --after hard-reset write-flash \
      0xa20000 "$RFS" > /tmp/ef-rootfs.log 2>&1; then
      return 0
    fi
    echo "retry $attempt for rootfs"
    sleep 4
  done
  return 1
}

if ! flash; then
  echo "ROOTFS FLASH FAILED"
  tail -8 /tmp/ef-rootfs.log
  exit 1
fi
echo "FLASH OK: rootfs @0xa20000"

owrt_start_console
owrt_console_ready
