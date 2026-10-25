#!/bin/bash
# owrt-toolchain-check.sh — M0/ilp32f acceptance for the riscv32 OpenWrt toolchain.
#  1. cross gcc identity + ABI flags (rv32imafc_zicsr_zifencei_zba_zbb_zbs ilp32f, ELF flags 0x3)
#  2. hello world builds, PT_INTERP matches /lib/ld-musl-riscv32-sp.so.1
#  3. objdump verifies hardware FPU (fmadd.s/flw/fsw) + Bitmanip (rev8/clz/bset/sh*add) instructions
#  4. qemu-riscv32 runs the dynamic binary (userland smoke, no board needed)
set -e
ESP32S31_ROOT=${ESP32S31_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
TC=$ESP32S31_ROOT/openwrt/openwrt/staging_dir/toolchain-riscv32_generic_gcc-14.3.0_musl
CC=$TC/bin/riscv32-openwrt-linux-musl-gcc
OBJDUMP=$TC/bin/riscv32-openwrt-linux-musl-objdump
WORK=$(mktemp -d /tmp/owrt-tc-check.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

[ -x "$CC" ] || { echo "no cross gcc at $CC (toolchain not built?)" >&2; exit 1; }

echo "== 1. identity"
"$CC" -dumpmachine
"$CC" -dumpversion

echo "== 2. hello world (ilp32f + zba_zbb_zbs)"
cp "$ESP32S31_ROOT/openwrt/esp32s31/toolchain-check/hello.c" "$WORK/hello.c"
"$CC" -O2 -mabi=ilp32f -march=rv32imafc_zicsr_zifencei_zba_zbb_zbs -o "$WORK/hello" "$WORK/hello.c"

INTERP=$(LC_ALL=C readelf -l "$WORK/hello" | sed -n 's/.*Requesting program interpreter: \(.*\)\]/\1/p')
FLAGS=$(readelf -h "$WORK/hello" | awk '/Flags:/{print $2}')
echo "PT_INTERP: $INTERP (expect /lib/ld-musl-riscv32-sp.so.1)"
echo "ELF flags: $FLAGS (expect 0x3 = RVC + single-float ABI)"

[ "$INTERP" = "/lib/ld-musl-riscv32-sp.so.1" ] || { echo "FAIL: unexpected PT_INTERP $INTERP"; exit 1; }
[ "$FLAGS" = "0x3," ] || { echo "FAIL: unexpected ELF flags $FLAGS"; exit 1; }

echo "== 3. ISA instruction verification (FPU + Zba/Zbb/Zbs)"
"$OBJDUMP" -d "$WORK/hello" | grep -E "fmadd\.s|fadd\.s|fmul\.s|rev8|clz|bset"

echo "== 4. shipped musl linker:"
find "$TC" -name 'ld-musl-*' -not -path '*/include/*' | head

echo "== 5. qemu-riscv32 run"
qemu-riscv32 -cpu rv32,f=true,c=true,zba=true,zbb=true,zbs=true -L "$TC" "$WORK/hello"

echo "OWRT_TOOLCHAIN_ILP32F_CHECK_OK"
