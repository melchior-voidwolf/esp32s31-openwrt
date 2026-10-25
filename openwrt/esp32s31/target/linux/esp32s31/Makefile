# SPDX-License-Identifier: GPL-2.0-only
#
# ESP32-S31 (Korvo-1) target for OpenWrt.
#
# This target exists to build the OpenWrt *rootfs* for rv32imafc/ilp32
# soft-float musl.  The running kernel is built in the esp32-S31 linux/repo
# tree (Linux 7.3 + S31 platform patches) and installed onto the SD card
# separately (tools/mk-openwrt-sd.sh); the kernel that OpenWrt builds here
# is a throwaway generic rv32 kernel that only has to compile.
#
include $(TOPDIR)/rules.mk

ARCH:=riscv32
BOARD:=esp32s31
BOARDNAME:=Espressif ESP32-S31
FEATURES:=ext4
KERNELNAME:=Image
SUBTARGETS:=korvo1

KERNEL_PATCHVER:=6.12

include $(INCLUDE_DIR)/target.mk

DEFAULT_PACKAGES += -firewall4 -nftables -kmod-nft-core

define Target/Description
	Build the OpenWrt rootfs for the ESP32-S31 Korvo-1 board.
endef

$(eval $(call BuildTarget))
