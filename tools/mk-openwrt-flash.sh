#!/bin/bash
# Assemble a complete 16MB, 0xff-filled OpenWrt Korvo-1 flash image.
set -euo pipefail

ESP32S31_ROOT=${ESP32S31_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
B=$ESP32S31_ROOT/build/korvo1-openwrt
LR=$ESP32S31_ROOT/linux/repo
OUT=$B/openwrt-flash-16m.img

KERNEL=$B/Image-7.3-flash-initramfs
ROOTFS=$B/rootfs.squashfs
BOOT2=$LR/build/korvo1/bootloader/bootloader/bootloader.bin
PTABLE=$LR/build/korvo1/bootloader/partition_table/partition-table.bin
LOADER=${OPENWRT_LOADER:-$LR/build/korvo1/bootloader/s31-linux-loader.bin}
LOADER_CONFIG=${OPENWRT_SDKCONFIG:-$LR/build/korvo1/sdkconfig}
SBI=$LR/build/korvo1/opensbi.bin
MANIFEST=$B/linux.size

for f in "$KERNEL" "$ROOTFS" "$BOOT2" "$PTABLE" "$LOADER" "$SBI" "$LOADER_CONFIG"; do
    [ -f "$f" ] || { echo "missing: $f" >&2; exit 1; }
done
if ! grep -Eq '^CONFIG_S31_LINUX_LCD_KEEP_ALIVE=n$|^# CONFIG_S31_LINUX_LCD_KEEP_ALIVE is not set$' "$LOADER_CONFIG"; then
    echo "OpenWrt requires CONFIG_S31_LINUX_LCD_KEEP_ALIVE=n in $LOADER_CONFIG" >&2
    echo "Use a headless loader profile, or set OPENWRT_LOADER and OPENWRT_SDKCONFIG." >&2
    exit 1
fi

# The manifest always describes the exact initramfs kernel being assembled.
python3 -I "$ESP32S31_ROOT/tools/gen-linux-size.py" "$KERNEL" "$MANIFEST"
python3 -I "$ESP32S31_ROOT/tools/validate-openwrt-images.py" \
    --kernel "$KERNEL" --manifest "$MANIFEST" --rootfs "$ROOTFS"
python3 -I "$ESP32S31_ROOT/tools/assemble-openwrt-flash.py" "$OUT" \
    0x2000 "$BOOT2" \
    0x8000 "$PTABLE" \
    0x20000 "$LOADER" \
    0x220000 "$SBI" \
    0x2a0000 "$KERNEL" \
    0xa1fff4 "$MANIFEST" \
    0xa20000 "$ROOTFS"
sha256sum "$OUT"
echo "openwrt-flash: $OUT"
echo "MK_OPENWRT_FLASH_OK"
