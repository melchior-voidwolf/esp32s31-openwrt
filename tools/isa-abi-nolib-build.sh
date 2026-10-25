#!/bin/bash
# Build same-GCC, no-runtime S31 ABI/ISA comparison binaries.
set -euo pipefail

ROOT=${ESP32S31_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
TC="$ROOT/openwrt/openwrt/staging_dir/toolchain-riscv32_generic_gcc-14.3.0_musl/bin/riscv32-openwrt-linux-musl"
OUT="$ROOT/openwrt/bench/nolib"
SRC="$ROOT/openwrt/bench/isa-abi-nolib.c"
CALLEE="$ROOT/openwrt/bench/isa-abi-callee.c"
START="$ROOT/openwrt/bench/isa-abi-start.S"
BASE=rv32imafc_zicsr_zifencei
FULL=rv32imafc_zicsr_zifencei_zba_zbb_zbs
FLAGS=(
    -std=gnu11 -O2 -fno-fast-math -ffp-contract=off
    -ffreestanding -fno-builtin -fno-stack-protector
    -fno-tree-loop-distribute-patterns -fno-pic -no-pie
    -msmall-data-limit=0 -mcmodel=medlow -mno-relax
    -falign-functions=64 -falign-loops=32
    -static -nostdlib -Wl,--no-relax -Wl,--build-id=none
)
mkdir -p "$OUT"

build() {
    local name="$1" abi="$2" march="$3"
    "$TC-gcc" "${FLAGS[@]}" -march="$march" -mabi="$abi" \
        -o "$OUT/$name" "$START" "$SRC" "$CALLEE"
    for symbol in bench_float_local bench_float_call abi_float_step bench_bits bench_zba bench_int_control; do
        "$TC-objdump" -d --disassemble="$symbol" "$OUT/$name" \
            > "$OUT/$name.$symbol.objdump"
    done
}

build nolib-soft-base ilp32 "$BASE"
build nolib-soft-full ilp32 "$FULL"
build nolib-hard-base ilp32f "$BASE"
build nolib-hard-full ilp32f "$FULL"

for name in nolib-soft-base nolib-soft-full; do
    "$TC-readelf" -h "$OUT/$name" | grep 'soft-float ABI'
done
for name in nolib-hard-base nolib-hard-full; do
    "$TC-readelf" -h "$OUT/$name" | grep 'single-float ABI'
done
for name in nolib-soft-base nolib-soft-full nolib-hard-base nolib-hard-full; do
    [ -z "$("$TC-nm" -u "$OUT/$name")" ]
    ! "$TC-readelf" -l "$OUT/$name" | grep -q INTERP
    ! "$TC-readelf" -d "$OUT/$name" | grep -q NEEDED
    grep -E 'fadd[.]s|fmul[.]s' "$OUT/$name.bench_float_local.objdump"
done
for name in nolib-soft-base nolib-hard-base; do
    ! grep -E 'clz|ctz|rev8|rori|bset|bclr' "$OUT/$name.bench_bits.objdump"
    ! grep -E 'sh1add|sh2add|sh3add' "$OUT/$name.bench_zba.objdump"
done
for name in nolib-soft-full nolib-hard-full; do
    grep -E 'clz|ctz|rev8|rori|bset|bclr' "$OUT/$name.bench_bits.objdump"
    grep -E 'sh1add|sh2add|sh3add' "$OUT/$name.bench_zba.objdump"
done

if command -v qemu-riscv32 >/dev/null 2>&1; then
    for name in nolib-soft-base nolib-soft-full nolib-hard-base nolib-hard-full; do
        echo "=== QEMU $name ==="
        qemu-riscv32 "$OUT/$name"
    done
fi
ls -l "$OUT"/nolib-*
echo "NOLIB_BENCH_BUILD_OK"
