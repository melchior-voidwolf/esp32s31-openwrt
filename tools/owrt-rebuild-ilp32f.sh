#!/bin/bash
# owrt-rebuild-ilp32f.sh — Clean rebuild of OpenWrt toolchain and all target
# packages for ESP32-S31 with hardware single-precision float ABI (-mabi=ilp32f)
# and full S31 CPU ISA extensions (-march=rv32imafc_zicsr_zifencei_zba_zbb_zbs).
# Preserves host tools (staging_dir/host*, build_dir/host*) and the prebuilt
# 6.12 dummy kernel tree to avoid unnecessary rebuild overhead.
set -euo pipefail

ESP32S31_ROOT=${ESP32S31_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
OWRT="$ESP32S31_ROOT/openwrt/openwrt"

echo "=== [1/6] Validating and applying canonical board overlays ==="
bash "$ESP32S31_ROOT/tools/owrt-sync-overlays.sh"
bash "$ESP32S31_ROOT/tools/owrt-apply-target.sh"
python3 "$ESP32S31_ROOT/tools/patch-owrt-openssl.py" "$OWRT"
cp "$ESP32S31_ROOT/openwrt/esp32s31/korvo1.config.fragment" "$OWRT/.config"
make -C "$OWRT" defconfig

echo "=== [2/6] Cleaning old soft-float (ilp32) toolchain and target packages ==="
rm -rf "$OWRT/build_dir/toolchain-riscv32_generic_gcc-14.3.0_musl"
rm -rf "$OWRT/staging_dir/toolchain-riscv32_generic_gcc-14.3.0_musl"
rm -rf "$OWRT/staging_dir/target-riscv32_generic_musl"
rm -rf "$OWRT/bin/packages/riscv32_generic"
rm -rf "$OWRT/bin/targets/esp32s31"
rm -rf "$OWRT/staging_dir/packages/esp32s31"

# Clean all userland package dirs in build_dir/target-riscv32_generic_musl
# while preserving linux-esp32s31_korvo1/linux-6.12.112
if [ -d "$OWRT/build_dir/target-riscv32_generic_musl" ]; then
  for d in "$OWRT/build_dir/target-riscv32_generic_musl"/*; do
    [ -e "$d" ] || continue
    if [ "$(basename "$d")" = "linux-esp32s31_korvo1" ]; then
      rm -rf "$d/base-files" "$d/iptables-"* "$d/mtd" "$d/packages" "$d"/root.*
    else
      rm -rf "$d"
    fi
  done
fi

echo "=== [3/6] Building ilp32f + zba_zbb_zbs toolchain (-j$(nproc)) ==="
make -C "$OWRT" toolchain/install -j"$(nproc)"

echo "=== [4/6] Running ilp32f + S31 ISA toolchain verification ==="
bash "$ESP32S31_ROOT/tools/owrt-toolchain-check.sh"

echo "=== [5/6] Building all OpenWrt target packages with ilp32f + zba_zbb_zbs (-j$(nproc)) ==="
make -C "$OWRT" target/linux/install package/compile package/install -j"$(nproc)"

echo "=== [6/6] Running canonical rootfs post-processing and hard validation ==="
SKIP_KERNEL=1 bash "$ESP32S31_ROOT/tools/owrt-finish-all.sh"
