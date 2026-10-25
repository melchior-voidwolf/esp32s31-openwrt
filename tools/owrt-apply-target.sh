#!/bin/bash
# owrt-apply-target.sh — install the esp32s31 target + riscv32 (ilp32f + S31 ISA)
# plumbing + files/ overlay into the OpenWrt clone (openwrt/openwrt). Idempotent.
set -e
ESP32S31_ROOT=${ESP32S31_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
ROOT=$ESP32S31_ROOT/openwrt
OWRT=$ROOT/openwrt
SKEL=$ROOT/esp32s31

[ -d "$OWRT/target/linux" ] || { echo "no openwrt clone at $OWRT"; exit 1; }

# 1. riscv32 arch plumbing (toolchain/gcc/common.mk + include/target.mk + target/Config.in)
python3 "$ESP32S31_ROOT/tools/patch-owrt-riscv32.py" "$OWRT"

# 1b. autoconf site config for the new arch (prereq requires site/$(ARCH))
install -m 0644 "$SKEL/site/riscv32" "$OWRT/include/site/riscv32"

# 1c. musl 1.2.6 backport for riscv32 ilp32f (setjmp/longjmp fsw/flw + vDSO clock_gettime)
install -m 0644 "$SKEL/musl-910-riscv32-ilp32f-setjmp-vdso.patch" \
  "$OWRT/toolchain/musl/patches/910-riscv32-ilp32f-setjmp-vdso.patch"

# 2. target skeleton
cp -R "$SKEL/target/linux/esp32s31" "$OWRT/target/linux/"

# 3. top-level files/ overlay (applied after all packages in prepare_rootfs)
if [ -d "$SKEL/files" ]; then
  rm -rf "$OWRT/files"
  cp -a "$SKEL/files" "$OWRT/files"
fi

echo "target installed: $OWRT/target/linux/esp32s31 (+ files overlay)"
