# SPDX-License-Identifier: GPL-2.0-only
#
# Image rules for the esp32s31 target.  Only the rootfs matters: the SD
# image is assembled outside OpenWrt by tools/mk-openwrt-sd.sh from
# $(BIN_DIR)/openwrt-esp32s31-korvo1-rootfs.tar.gz plus the linux/repo
# kernel Image.
#
include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/image.mk

define Device/generic
  DEVICE_VENDOR := Espressif
  DEVICE_MODEL := ESP32-S31 Korvo-1
  DEVICE_PACKAGES :=
  KERNEL_NAME := Image
endef
TARGET_DEVICES += generic

$(eval $(call BuildImage))
