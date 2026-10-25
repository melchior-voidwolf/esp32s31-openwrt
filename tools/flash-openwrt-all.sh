#!/bin/bash
# flash-openwrt-all.sh — validate and flash kernel + manifest + rootfs together.
set -euo pipefail

ROOT="${ESP32S31_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
. "$ROOT/tools/s31-lease-common.sh"
if ! s31_exclusive_valid "${S31_RUNTIME_DIR:-/tmp}"; then
  export S31_SESSION="${S31_SESSION:-openwrt}"
  export S31_REASON="${S31_REASON:-flash OpenWrt kernel manifest and rootfs}"
  exec "$ROOT/tools/s31-exclusive.sh" "$0" "$@"
fi
PORT="${S31_PORT:-/dev/ttyUSB0}"
ESPT="${ESPTOOL:-/home/kail/.espressif/python_env/idf6.1_py3.12_env/bin/esptool}"
. "$ROOT/tools/flash-openwrt-console.sh"
trap owrt_console_cleanup EXIT
IMG="$ROOT/build/korvo1-openwrt/Image-7.3-flash-initramfs"
SIZE="$ROOT/build/korvo1-openwrt/linux.size"
RFS="$ROOT/build/korvo1-openwrt/rootfs.squashfs"

python3 -I "$ROOT/tools/validate-openwrt-images.py" \
  --kernel "$IMG" --manifest "$SIZE" --rootfs "$RFS"
owrt_stop_console

flash() {
  local attempt
  for attempt in 1 2 3 4 5; do
    if timeout 600 "$ESPT" --chip esp32s31 -p "$PORT" -b 230400 \
      --before default-reset --after hard-reset write-flash \
      0x2a0000 "$IMG" 0xa1fff4 "$SIZE" 0xa20000 "$RFS" \
      > /tmp/ef-all.log 2>&1; then
      return 0
    fi
    echo "retry $attempt for kernel + manifest + rootfs"
    sleep 4
  done
  return 1
}

if ! flash; then
  echo "OPENWRT FLASH FAILED"
  tail -8 /tmp/ef-all.log
  exit 1
fi
echo "FLASH ALL OK: kernel + manifest + rootfs"

owrt_start_console
owrt_console_ready
