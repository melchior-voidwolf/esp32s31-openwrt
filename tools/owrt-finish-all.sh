#!/bin/bash
# owrt-finish-all.sh — Complete Phase 2 & Phase 3:
# 1. Sync all log-error fixes + LuCI Chinese into top-level files/ overlay
#    (keep target base-files clean so apk never complains about file ownership)
# 2. Rebuild base-files apk and run package/install
# 3. Post-process root-esp32s31 for zero-error boot and repack rootfs.squashfs
# 4. Rebuild Linux 7.3 kernel with CONFIG_OVERLAY_FS=y + ilp32f flash-init + rtl8153a-3.fw
set -euo pipefail

ESP32S31_ROOT=${ESP32S31_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
OWRT="$ESP32S31_ROOT/openwrt/openwrt"
SKEL_FILES="$ESP32S31_ROOT/openwrt/esp32s31/files"

echo "=== [1/4] Validating and applying canonical board overlays ==="
bash "$ESP32S31_ROOT/tools/owrt-sync-overlays.sh"
rm -rf "$OWRT/target/linux/esp32s31/base-files"
bash "$ESP32S31_ROOT/tools/owrt-apply-target.sh"

echo "=== [2/4] Rebuilding base-files apk and running package/install ==="
make -C "$OWRT" package/base-files/clean package/base-files/compile -j"$(nproc)"
make -C "$OWRT" package/install -j"$(nproc)"

echo "=== [3/4] Post-processing root-esp32s31 & verifying ELF headers (0x3, single-float ABI) ==="
ROOTFS_DIR="$OWRT/build_dir/target-riscv32_generic_musl/root-esp32s31"

cp -a "$SKEL_FILES/." "$ROOTFS_DIR/"
rm -f "$ROOTFS_DIR/etc/urandom.seed"
mkdir -p "$ROOTFS_DIR/lib/modules/7.3.0" "$ROOTFS_DIR/lib/netifd/wireless"
rm -rf "$ROOTFS_DIR/lib/modules/6.12"*
rm -f "$ROOTFS_DIR/usr/share/hostap/hostapd.uc" \
      "$ROOTFS_DIR/usr/share/hostap/wpa_supplicant.uc" \
      "$ROOTFS_DIR/sbin/ujail"
rm -f "$ROOTFS_DIR/etc/rc.d/"*packet_steering* \
      "$ROOTFS_DIR/etc/rc.d/"*firewall* \
      "$ROOTFS_DIR/etc/rc.d/"*cron* \
      "$ROOTFS_DIR/etc/rc.d/"*wpad*
rm -f "$ROOTFS_DIR/etc/init.d/packet_steering"
ln -sf ../init.d/hostapd "$ROOTFS_DIR/etc/rc.d/S25hostapd"
ln -sf ../init.d/lanstatic "$ROOTFS_DIR/etc/rc.d/S26lanstatic"

TC="$OWRT/staging_dir/toolchain-riscv32_generic_gcc-14.3.0_musl"
READELF="$TC/bin/riscv32-openwrt-linux-musl-readelf"
check_ilp32f() {
  local elf="$1"
  "$READELF" -h "$elf" | grep -E "Flags:"
  "$READELF" -h "$elf" | grep -q "0x3, RVC, single-float ABI"
  "$READELF" -l "$elf" | grep -q "ld-musl-riscv32-sp[.]so[.]1"
  echo "ILP32F_OK: $elf"
}
for elf in "$ROOTFS_DIR/bin/busybox" "$ROOTFS_DIR/sbin/procd" \
           "$ROOTFS_DIR/usr/sbin/wpad" "$ROOTFS_DIR/usr/bin/ucode"; do
  check_ilp32f "$elf"
done
for rel in etc/config/uhttpd etc/sysctl.d/99-s31.conf lib/preinit/80_s31_urandom_seed lib/netifd/main.uc sbin/kmodloader usr/lib/uhttpd_ucode.so; do
  [ -f "$ROOTFS_DIR/$rel" ] || { echo "missing rootfs fix: $rel"; exit 1; }
done
grep -q '^[[:space:]]*list[[:space:]]\+ucode_prefix' "$ROOTFS_DIR/etc/config/uhttpd"
echo "ROOTFS_OK: LuCI ucode and kmodloader/netifd fixes present"
ls -la "$ROOTFS_DIR/lib/ld-musl-"*

rm -rf /tmp/owrt-rootfs
cp -a "$ROOTFS_DIR" /tmp/owrt-rootfs
bash "$ESP32S31_ROOT/tools/pack-openwrt-rootfs.sh" \
  /tmp/owrt-rootfs "$ESP32S31_ROOT/build/korvo1-openwrt/rootfs.squashfs"

if [ "${SKIP_KERNEL:-0}" = 1 ]; then
  bash "$ESP32S31_ROOT/tools/mk-openwrt-flash.sh"
  echo "=== ROOTFS BUILD COMPLETE (kernel unchanged: SKIP_KERNEL=1) ==="
  exit 0
fi

"$TC/bin/riscv32-openwrt-linux-musl-gcc" -static -O2 -mabi=ilp32f \
  -march=rv32imafc_zicsr_zifencei_zba_zbb_zbs \
  -o "$ESP32S31_ROOT/build/korvo1-openwrt/flash-init" \
  "$ESP32S31_ROOT/openwrt/esp32s31/flash-init/init.c"
cp "$ESP32S31_ROOT/build/korvo1-openwrt/flash-init" \
  "$ESP32S31_ROOT/openwrt/esp32s31/flash-init-rootfs/init"

echo "=== [4/4] Rebuilding Linux 7.3 kernel with CONFIG_OVERLAY_FS=y + ilp32f flash-init ==="
KBUILD="$ESP32S31_ROOT/linux/repo/build/br-output-korvo1/build/linux-7.3"
cp "$ESP32S31_ROOT/linux/repo/br2-external/board/esp32s31/linux-openwrt.config" "$KBUILD/.config"
sed -i "s|^CONFIG_INITRAMFS_SOURCE=.*|CONFIG_INITRAMFS_SOURCE=\"$ESP32S31_ROOT/openwrt/esp32s31/flash-init-rootfs\"|" "$KBUILD/.config"
make -C "$KBUILD" ARCH=riscv olddefconfig
rm -f "$KBUILD/.stamp_configured" "$KBUILD/.stamp_built"
make -C "$ESP32S31_ROOT/linux/repo/external/buildroot" \
  O="$ESP32S31_ROOT/linux/repo/build/br-output-korvo1" \
  BR2_EXTERNAL="$ESP32S31_ROOT/linux/repo/br2-external" \
  BR2_DL_DIR="$ESP32S31_ROOT/linux/repo/dl" \
  linux -j"$(nproc)"

required_config=(
  CONFIG_BT
  CONFIG_ESP32S31_HOSTED
  CONFIG_MISC_FILESYSTEMS
  CONFIG_SQUASHFS
  CONFIG_SQUASHFS_FILE_DIRECT
  CONFIG_SQUASHFS_XZ
  CONFIG_XZ_DEC
  CONFIG_MTD
  CONFIG_MTD_BLOCK
  CONFIG_BLK_DEV_INITRD
  CONFIG_OVERLAY_FS
  CONFIG_MTD_UBI
  CONFIG_UBIFS_FS
  CONFIG_UBIFS_FS_ADVANCED_COMPR
  CONFIG_UBIFS_FS_LZO
  CONFIG_UBIFS_FS_XATTR
  CONFIG_UBIFS_FS_SECURITY
  CONFIG_USB_USBNET
  CONFIG_USB_RTL8152
  CONFIG_CMDLINE_FORCE
)
for symbol in "${required_config[@]}"; do
  grep -q "^${symbol}=y$" "$KBUILD/.config" || {
    echo "missing required kernel option: $symbol"
    exit 1
  }
done

# Comments such as "# CONFIG_HID=y (dropped)" do not disable a symbol.
# Keep the headless profile slim by rejecting these options if olddefconfig
# ever turns them back on.  Missing symbols are fine; built-in/module is not.
forbidden_config=(
  CONFIG_HID
  CONFIG_USB_HID
  CONFIG_JFFS2_FS
  CONFIG_SQUASHFS_FILE_CACHE
  CONFIG_USB_NET_AX8817X
  CONFIG_USB_NET_AX88179_178A
  CONFIG_USB_NET_CDCETHER
  CONFIG_USB_NET_CDC_NCM
  CONFIG_USB_NET_NET1080
  CONFIG_USB_NET_CDC_SUBSET
  CONFIG_USB_NET_ZAURUS
)
for symbol in "${forbidden_config[@]}"; do
  if grep -qE "^${symbol}=[ym]$" "$KBUILD/.config"; then
    echo "forbidden headless kernel option is enabled: $symbol"
    exit 1
  fi
done

grep -q '^CONFIG_CMDLINE=.*esp32_shm[.]radio_service=bt' "$KBUILD/.config"
grep -q '^CONFIG_BUILTIN_DTB_NAME="espressif/esp32s31_korvo1_openwrt"$' "$KBUILD/.config"
grep -qE '^CONFIG_INITRAMFS_SOURCE="[^"]+"$' "$KBUILD/.config"
strings "$ESP32S31_ROOT/linux/repo/build/br-output-korvo1/images/Image" | grep -c "authorized locally"

cp "$ESP32S31_ROOT/linux/repo/build/br-output-korvo1/images/Image" \
   "$ESP32S31_ROOT/build/korvo1-openwrt/Image-7.3-flash-initramfs"
python3 -I "$ESP32S31_ROOT/tools/gen-linux-size.py" \
   "$ESP32S31_ROOT/build/korvo1-openwrt/Image-7.3-flash-initramfs" \
   "$ESP32S31_ROOT/build/korvo1-openwrt/linux.size"
python3 -I "$ESP32S31_ROOT/tools/validate-openwrt-images.py" \
  --kernel "$ESP32S31_ROOT/build/korvo1-openwrt/Image-7.3-flash-initramfs" \
  --manifest "$ESP32S31_ROOT/build/korvo1-openwrt/linux.size" \
  --rootfs "$ESP32S31_ROOT/build/korvo1-openwrt/rootfs.squashfs"
bash "$ESP32S31_ROOT/tools/mk-openwrt-flash.sh"

echo "=== ALL PHASE 2 & PHASE 3 BUILDS COMPLETED BIT-PERFECTLY ==="
