# SPDX-License-Identifier: GPL-2.0-only
include $(TOPDIR)/rules.mk

ARCH:=riscv32
BOARD:=esp32s31
SUBTARGET:=korvo1
BOARDNAME:=Korvo-1
DEVICE_TYPE:=basic

define Target/Description
	Korvo-1 development board (800x480 LCD, microSD, ESP-Hosted Wi-Fi).
endef
