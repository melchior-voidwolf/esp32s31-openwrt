#!/bin/bash
# owrt-resume-ilp32f.sh — Apply musl 910 ilp32f patch, clean musl, and resume
# the toolchain + target packages ilp32f + zba_zbb_zbs build.
set -euo pipefail

ESP32S31_ROOT=${ESP32S31_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
OWRT="$ESP32S31_ROOT/openwrt/openwrt"

bash "$ESP32S31_ROOT/tools/owrt-sync-overlays.sh"
bash "$ESP32S31_ROOT/tools/owrt-apply-target.sh"

echo "=== Cleaning musl to apply 910-riscv32-ilp32f-setjmp-vdso.patch ==="
make -C "$OWRT" toolchain/musl/clean

echo "=== [3/6] Resuming ilp32f + zba_zbb_zbs toolchain build (-j$(nproc)) ==="
make -C "$OWRT" toolchain/install -j"$(nproc)"

echo "=== [4/6] Running ilp32f + S31 ISA toolchain verification ==="
bash "$ESP32S31_ROOT/tools/owrt-toolchain-check.sh"

echo "=== [5/6] Building all OpenWrt target packages with ilp32f + zba_zbb_zbs (-j$(nproc)) ==="
make -C "$OWRT" target/linux/install package/compile package/install -j"$(nproc)"

echo "=== [6/6] Running canonical rootfs post-processing and hard validation ==="
SKIP_KERNEL=1 bash "$ESP32S31_ROOT/tools/owrt-finish-all.sh"
