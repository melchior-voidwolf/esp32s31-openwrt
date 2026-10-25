#!/bin/bash
# Build four static S31 ABI/ISA benchmark variants and verify their instructions.
set -euo pipefail

ROOT=${ESP32S31_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
SRC="$ROOT/openwrt/bench/isa-abi-bench.c"
CALLEE="$ROOT/openwrt/bench/isa-abi-callee.c"
OUT="$ROOT/openwrt/bench/bin"
SOFT="$ROOT/linux/repo/build/br-output-korvo1/host/bin/riscv32-buildroot-linux-musl"
HARD_ROOT="$ROOT/openwrt/openwrt/staging_dir/toolchain-riscv32_generic_gcc-14.3.0_musl"
HARD="$HARD_ROOT/bin/riscv32-openwrt-linux-musl"
BASE_ISA=rv32imafc_zicsr_zifencei
FULL_ISA=rv32imafc_zicsr_zifencei_zba_zbb_zbs
COMMON=(-O2 -static -fno-fast-math -fno-builtin-sqrtf -ffp-contract=off)

mkdir -p "$OUT"
build() {
    local prefix="$1"
    local abi="$2"
    local march="$3"
    local output="$4"
    "${!prefix}-gcc" "${COMMON[@]}" -march="$march" -mabi="$abi" \
        -o "$OUT/$output" "$SRC" "$CALLEE" -lm
    "${!prefix}-objdump" -d --disassemble=bench_float "$OUT/$output" \
        > "$OUT/$output.float.objdump"
    "${!prefix}-objdump" -d --disassemble=bench_abi_call "$OUT/$output" \
        > "$OUT/$output.abi-call.objdump"
    "${!prefix}-objdump" -d --disassemble=abi_float_step "$OUT/$output" \
        > "$OUT/$output.callee.objdump"
    "${!prefix}-objdump" -d --disassemble=bench_sqrt "$OUT/$output" \
        > "$OUT/$output.sqrt.objdump"
    "${!prefix}-objdump" -d --disassemble=sqrtf "$OUT/$output" \
        > "$OUT/$output.sqrtf.objdump"
    "${!prefix}-objdump" -d --disassemble=bench_double "$OUT/$output" \
        > "$OUT/$output.double.objdump"
    "${!prefix}-objdump" -d --disassemble=bench_bits "$OUT/$output" \
        > "$OUT/$output.bits.objdump"
}

build SOFT ilp32 "$BASE_ISA" isa-abi-soft-base
build SOFT ilp32 "$FULL_ISA" isa-abi-soft-full
build HARD ilp32f "$BASE_ISA" isa-abi-hard-base
build HARD ilp32f "$FULL_ISA" isa-abi-hard-full

for name in soft-base soft-full; do
    "$SOFT-readelf" -h "$OUT/isa-abi-$name" | grep 'soft-float ABI'
    grep -E 'fadd[.]s|fmul[.]s' "$OUT/isa-abi-$name.float.objdump"
    grep -E '__adddf3|__muldf3' "$OUT/isa-abi-$name.double.objdump"
    grep -E '__clzsi2|__ctzsi2' "$OUT/isa-abi-$name.bits.objdump" || true
done
for name in hard-base hard-full; do
    "$HARD-readelf" -h "$OUT/isa-abi-$name" | grep 'single-float ABI'
    grep -E 'fadd[.]s|fmul[.]s' "$OUT/isa-abi-$name.float.objdump"
    grep -E '__adddf3|__muldf3' "$OUT/isa-abi-$name.double.objdump"
done
for name in soft-full hard-full; do
    grep -E 'clz|ctz|rev8|rori|bclr|bset' "$OUT/isa-abi-$name.bits.objdump"
done

for name in soft-base soft-full hard-base hard-full; do
    grep -E 'jal[^<]*<sqrtf>' "$OUT/isa-abi-$name.sqrt.objdump"
done

if command -v qemu-riscv32 >/dev/null 2>&1; then
    for name in soft-base soft-full hard-base hard-full; do
        echo "=== QEMU $name ==="
        qemu-riscv32 "$OUT/isa-abi-$name" all 1000
    done
fi

for name in soft-base soft-full; do
    "$SOFT-strip" "$OUT/isa-abi-$name"
done
for name in hard-base hard-full; do
    "$HARD-strip" "$OUT/isa-abi-$name"
done
ls -l "$OUT"/isa-abi-*
echo "ISA_ABI_BENCH_BUILD_OK"
