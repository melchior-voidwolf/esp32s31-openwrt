#!/bin/bash
# Write the complete 16 MiB image.  This erases the entire flash, including data.
set -euo pipefail

ROOT="${ESP32S31_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
. "$ROOT/tools/s31-lease-common.sh"
if ! s31_exclusive_valid "${S31_RUNTIME_DIR:-/tmp}"; then
  export S31_SESSION="${S31_SESSION:-openwrt}"
  export S31_REASON="${S31_REASON:-flash complete OpenWrt image (erase all)}"
  exec "$ROOT/tools/s31-exclusive.sh" "$0" "$@"
fi
PORT="${S31_PORT:-/dev/ttyUSB0}"
ESPT="${ESPTOOL:-/home/kail/.espressif/python_env/idf6.1_py3.12_env/bin/esptool}"
IMAGE="${1:-$ROOT/build/korvo1-openwrt/openwrt-flash-16m.img}"

python3 -I "$ROOT/tools/validate-openwrt-full-image.py" \
  --image "$IMAGE" --build-root "$ROOT/build/korvo1-openwrt" \
  --linux-repo "$ROOT/linux/repo"
. "$ROOT/tools/flash-openwrt-console.sh"
trap owrt_console_cleanup EXIT

flash() {
  local attempt
  for attempt in 1 2 3; do
    if timeout 900 "$ESPT" --chip esp32s31 -p "$PORT" -b 230400 \
      --before default-reset --after hard-reset write-flash 0x0 "$IMAGE" \
      > /tmp/ef-openwrt-full.log 2>&1; then
      return 0
    fi
    echo "retry $attempt for complete OpenWrt image"
    sleep 4
  done
  return 1
}

owrt_sync_console
owrt_stop_console
flash || { echo "FULL IMAGE FLASH FAILED"; tail -8 /tmp/ef-openwrt-full.log; exit 1; }
echo "FULL_IMAGE_FLASH_OK (entire flash including data was replaced)"
owrt_start_console
owrt_console_ready
