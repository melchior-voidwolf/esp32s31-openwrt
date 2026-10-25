#!/usr/bin/env python3
"""patch-owrt-openssl.py — route riscv32 to openssl's linux-generic32-openwrt.

OpenWrt's 110-openwrt_targets.patch enumerates per-ARCH openssl targets but
has no riscv32 entry, so `linux-riscv32-openwrt` fails in Configure.  The
generic32 target (no asm, soft-float friendly) already exists in the same
table.  Idempotent.  Usage: python3 tools/patch-owrt-openssl.py <owrt-tree>
"""
import sys

owrt = sys.argv[1]
p = f"{owrt}/package/libs/openssl/Makefile"
src = open(p).read()

old = 'OPENSSL_TARGET:=linux-$(call qstrip,$(CONFIG_ARCH))-openwrt'
new = """ifeq ($(ARCH),riscv32)
OPENSSL_TARGET:=linux-generic32-openwrt
TARGET_LDFLAGS += -latomic
else
OPENSSL_TARGET:=linux-$(call qstrip,$(CONFIG_ARCH))-openwrt
endif"""

if "TARGET_LDFLAGS += -latomic" not in src:
    assert old in src, "openssl Makefile: OPENSSL_TARGET line not found"
    open(p, "w").write(src.replace(old, new, 1))
    print("openssl: riscv32 -> linux-generic32-openwrt + -latomic")
else:
    print("openssl: riscv32 already handled")
