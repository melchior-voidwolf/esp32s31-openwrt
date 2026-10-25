#!/bin/bash
# flash-openwrt-kernel.sh — flash the OpenWrt kernel and its manifest together.
set -euo pipefail

ROOT="${ESP32S31_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
. "$ROOT/tools/s31-lease-common.sh"
if ! s31_exclusive_valid "${S31_RUNTIME_DIR:-/tmp}"; then
  export S31_SESSION="${S31_SESSION:-openwrt}"
  export S31_REASON="${S31_REASON:-flash OpenWrt kernel and manifest}"
  exec "$ROOT/tools/s31-exclusive.sh" "$0" "$@"
fi
PORT="${S31_PORT:-/dev/ttyUSB0}"
ESPT="${ESPTOOL:-/home/kail/.espressif/python_env/idf6.1_py3.12_env/bin/esptool}"
. "$ROOT/tools/flash-openwrt-console.sh"
trap owrt_console_cleanup EXIT
IMG="${1:-$ROOT/build/korvo1-openwrt/Image-7.3-flash-initramfs}"
SIZE="${2:-$ROOT/build/korvo1-openwrt/linux.size}"

python3 -I "$ROOT/tools/validate-openwrt-images.py" \
  --kernel "$IMG" --manifest "$SIZE"
owrt_stop_console

flash() {
  local attempt
  for attempt in 1 2 3 4 5; do
    if timeout 420 "$ESPT" --chip esp32s31 -p "$PORT" -b 230400 \
      --before default-reset --after hard-reset write-flash \
      0x2a0000 "$IMG" 0xa1fff4 "$SIZE" > /tmp/ef-kernel.log 2>&1; then
      return 0
    fi
    echo "retry $attempt for kernel + manifest"
    sleep 4
  done
  return 1
}

if ! flash; then
  echo "KERNEL + MANIFEST FLASH FAILED"
  tail -8 /tmp/ef-kernel.log
  exit 1
fi
echo "FLASH OK: kernel @0x2a0000 + manifest @0xa1fff4"

owrt_start_console
owrt_console_ready
