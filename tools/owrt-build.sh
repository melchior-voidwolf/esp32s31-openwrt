#!/bin/bash
# owrt-build.sh — one-shot OpenWrt rootfs build for the korvo1 target:
#   1. install esp32s31 target + riscv32 plumbing (tools/owrt-apply-target.sh)
#   2. expand the authoritative config fragment (openwrt/esp32s31/korvo1.config.fragment)
#   3. make world (tools, toolchain, packages, rootfs tar/ext4)
# Output: openwrt/openwrt/bin/targets/esp32s31/korvo1/*.tar.gz
# Usage: tools/owrt-build.sh [extra make args...]
set -e
ESP32S31_ROOT=${ESP32S31_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
OWRT=$ESP32S31_ROOT/openwrt/openwrt

"$ESP32S31_ROOT/tools/owrt-apply-target.sh"

cp "$ESP32S31_ROOT/openwrt/esp32s31/korvo1.config.fragment" "$OWRT/.config"
make -C "$OWRT" defconfig

exec make -C "$OWRT" -j"$(nproc)" "$@"
