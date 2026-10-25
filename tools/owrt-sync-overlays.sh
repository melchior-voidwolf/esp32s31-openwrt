#!/bin/bash
# Validate the canonical board files/ overlay and derive target base-files.
# /tmp is never a source of board customizations.
set -euo pipefail

ESP32S31_ROOT=${ESP32S31_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
SKEL="$ESP32S31_ROOT/openwrt/esp32s31"
FILES="$SKEL/files"
BASE="$SKEL/target/linux/esp32s31/base-files"

required=(
  etc/init.d/lanstatic
  etc/init.d/hostapd
  etc/init.d/sysntpd
  etc/hostapd.conf
  etc/shadow
  etc/config/network
  etc/config/system
  etc/config/luci
  etc/config/uhttpd
  etc/sysctl.d/99-s31.conf
  lib/preinit/80_mount_root
  lib/preinit/80_s31_urandom_seed
  lib/netifd/main.uc
  lib/firmware/rtl_nic/rtl8153a-3.fw
  sbin/kmodloader
  usr/bin/board-fetch
  usr/lib/lua/luci/i18n/base.zh-cn.lmo
  usr/lib/uhttpd_ucode.so
)
for rel in "${required[@]}"; do
  [ -f "$FILES/$rel" ] || { echo "missing canonical overlay file: $FILES/$rel"; exit 1; }
done

# Never ship a shared random seed.  The board generates a fresh local seed
# during preinit; each device and each tmpfs-overlay boot are independent.

# Only package-owned/custom base files belong in target base-files.  Everything
# else stays in the top-level overlay, which is applied after apk install.
rm -rf "$BASE"
mkdir -p "$BASE/etc/init.d" "$BASE/etc/config"
cp -a "$FILES/etc/init.d/lanstatic" "$BASE/etc/init.d/"
cp -a "$FILES/etc/init.d/hostapd" "$BASE/etc/init.d/"
cp -a "$FILES/etc/hostapd.conf" "$BASE/etc/"
cp -a "$FILES/etc/shadow" "$BASE/etc/"
cp -a "$FILES/etc/config/network" "$BASE/etc/config/"
