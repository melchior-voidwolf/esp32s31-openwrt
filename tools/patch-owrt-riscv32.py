#!/usr/bin/env python3
"""patch-owrt-riscv32.py — idempotent riscv32 (ilp32f + S31 ISA) plumbing for OpenWrt.

Touches four upstream files (mirrors the riscv64 blocks; ABI is ilp32f
single-precision hardware float + full ESP32-S31 ISA extensions
rv32imafc_zicsr_zifencei_zba_zbb_zbs):
  - toolchain/gcc/common.mk : --with-arch=rv32imafc_zicsr_zifencei_zba_zbb_zbs
                              --with-abi=ilp32f --with-multilib-list=ilp32f
  - include/kernel.mk       : LINUX_KARCH riscv32 -> riscv
  - include/target.mk       : CPU_CFLAGS_generic = -mabi=ilp32f -march=rv32imafc_zicsr_zifencei_zba_zbb_zbs
  - target/Config.in        : "config riscv32" kconfig symbol + ARCH default
Usage: python3 tools/patch-owrt-riscv32.py <openwrt-tree-dir>
"""
import sys

owrt = sys.argv[1]
changes = 0

S31_MARCH = "rv32imafc_zicsr_zifencei_zba_zbb_zbs"
S31_MABI = "ilp32f"

# --- toolchain/gcc/common.mk: pin gcc to S31 ilp32f multilib ----------------
p = f"{owrt}/toolchain/gcc/common.mk"
src = open(p).read()
anchor = """ifneq ($(GCC_ARCH),)
  GCC_CONFIGURE+= --with-arch=$(GCC_ARCH)
endif
"""
old_block = """ifeq ($(ARCH),riscv32)
  GCC_CONFIGURE+= \\
\t--with-arch=rv32imafc \\
\t--with-abi=ilp32 \\
\t--with-multilib-list=ilp32
endif
"""
new_block = f"""ifeq ($(ARCH),riscv32)
  GCC_CONFIGURE+= \\
\t--with-arch={S31_MARCH} \\
\t--with-abi={S31_MABI} \\
\t--with-multilib-list={S31_MABI}
endif
"""
if new_block in src:
    print(f"gcc/common.mk: {S31_MABI} ({S31_MARCH}) already pinned")
elif old_block in src:
    open(p, "w").write(src.replace(old_block, new_block, 1))
    print(f"gcc/common.mk: upgraded ilp32 -> {S31_MABI} ({S31_MARCH})")
    changes += 1
else:
    assert anchor in src, "gcc/common.mk: GCC_ARCH block not found"
    open(p, "w").write(src.replace(anchor, anchor + new_block, 1))
    print(f"gcc/common.mk: {S31_MABI} ({S31_MARCH}) multilib pinned")
    changes += 1

# --- include/kernel.mk: kernel arch is shared riscv (no arch/riscv32) ------
p = f"{owrt}/include/kernel.mk"
src = open(p).read()
old = "else ifneq (,$(findstring $(ARCH) , riscv64 ))"
new = "else ifneq (,$(findstring $(ARCH) , riscv32 riscv64 ))"
if new not in src:
    assert old in src, "kernel.mk: riscv64 karch line not found"
    open(p, "w").write(src.replace(old, new, 1))
    print("kernel.mk: LINUX_KARCH riscv32 -> riscv added")
    changes += 1
else:
    print("kernel.mk: riscv32 karch already present")

# --- include/target.mk: riscv32 CPU flags next to the riscv64 block -------
p = f"{owrt}/include/target.mk"
src = open(p).read()
anchor = """  ifeq ($(ARCH),riscv64)
    CPU_TYPE ?= generic
    CPU_CFLAGS_generic:=-mabi=lp64d -march=rv64gc
  endif
"""
old_tblock = """  ifeq ($(ARCH),riscv32)
    CPU_TYPE ?= generic
    CPU_CFLAGS_generic:=-mabi=ilp32 -march=rv32imafc
  endif
"""
new_tblock = f"""  ifeq ($(ARCH),riscv32)
    CPU_TYPE ?= generic
    CPU_CFLAGS_generic:=-mabi={S31_MABI} -march={S31_MARCH}
  endif
"""
if new_tblock in src:
    print(f"target.mk: riscv32 ({S31_MABI} + {S31_MARCH}) already present")
elif old_tblock in src:
    open(p, "w").write(src.replace(old_tblock, new_tblock, 1))
    print(f"target.mk: upgraded riscv32 -> -mabi={S31_MABI} -march={S31_MARCH}")
    changes += 1
else:
    assert anchor in src, "target.mk: riscv64 block not found"
    open(p, "w").write(src.replace(anchor, anchor + new_tblock, 1))
    print(f"target.mk: riscv32 ({S31_MABI} + {S31_MARCH}) block added")
    changes += 1

# --- target/Config.in: kconfig symbol + ARCH default -----------------------
p = f"{owrt}/target/Config.in"
src = open(p).read()
if "\nconfig riscv32\n" not in src:
    assert "\nconfig riscv64\n" in src, "Config.in: riscv64 symbol not found"
    src = src.replace(
        "\nconfig riscv64\n",
        "\nconfig riscv32\n\tbool\n\nconfig riscv64\n", 1)
    print("Config.in: config riscv32 added")
    changes += 1
else:
    print("Config.in: config riscv32 already present")

if '\tdefault "riscv32"   if riscv32' not in src:
    old = '\tdefault "riscv64"   if riscv64\n'
    assert old in src, "Config.in: riscv64 default not found"
    src = src.replace(old, '\tdefault "riscv32"   if riscv32\n' + old, 1)
    print("Config.in: ARCH default riscv32 added")
    changes += 1
else:
    print("Config.in: ARCH default already present")
open(p, "w").write(src)

print(f"riscv32 plumbing: {changes} change(s) applied")
