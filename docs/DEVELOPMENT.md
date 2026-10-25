# Development notes / 开发说明

## Architecture / 架构

This package is an OpenWrt userland port, not an upstream OpenWrt target.
The running system consists of:

```
ESP ROM → ESP-IDF bootloader → loader (hart0) → OpenSBI (hart1)
        → Linux 7.3 → flash-init → squashfs on mtdblock0 → procd
```

- `openwrt/esp32s31/` contains the target and canonical board overlay.
- `linux-openwrt.config` is a separate OpenWrt kernel configuration. Do not mix
  it with desktop or Buildroot flash configurations.
- The root filesystem is ilp32f musl. The CPU has single-precision FPU support,
  but no double-precision D extension.
- The persistent overlay uses UBIFS on the existing UBI data volume, with
  OpenWrt-specific `/overlay/openwrt/{upper,work}` directories. The all-empty-MTD
  initialization path still needs hardware acceptance; non-UBI data is not
  explicitly erased.
- `SQUASHFS_FILE_DIRECT` decompresses directly into page-cache pages instead of
  using an intermediate buffer and a second copy. See the bilingual performance
  section and A/B table in `README.md` for measurements and limitations.
- `uhttpd-mod-ucode` preinitializes the VM at startup. Each request still forks,
  but does not exec a new ucode interpreter.

## Source inputs / 源码输入

- OpenWrt upstream: commit `64900e756efa667774214f9c6b17c113222e01f7`.
- Board overlay: `openwrt/esp32s31/files/`.
- Kernel configuration: `linux-openwrt.config` in the Linux mainline tree.
- Mainline reference: <https://github.com/melchior-voidwolf/esp32-s31-linux-eXtends>.

`tools/owrt-finish-all.sh` normalizes `CONFIG_INITRAMFS_SOURCE` using
`ESP32S31_ROOT`; a fixed home-directory path is not required.

## Build / 构建

```sh
bash tools/owrt-apply-target.sh
cp openwrt/esp32s31/korvo1.config.fragment openwrt/openwrt/.config
make -C openwrt/openwrt defconfig
make -C openwrt/openwrt target/linux/install package/compile package/install -j"$(nproc)"
SKIP_KERNEL=1 bash tools/owrt-finish-all.sh
```

The last step verifies the ilp32f ELF headers, required rootfs fixes, the
manifest and the complete image. A full kernel build additionally requires a
separate Linux mainline checkout and its ESP-IDF/OpenSBI dependencies.

## Flash and recovery / 刷写与恢复

- `./flash.sh backup` reads the complete flash twice and verifies both copies.
- `./flash.sh update` writes kernel+manifest+rootfs without explicitly erasing data.
- `./flash.sh full` writes the complete 16 MiB image and erases everything.
- `./flash.sh restore DIR` restores a verified complete backup, also erasing everything.

`validate-openwrt-images.py` checks kernel size/CRC/manifest and rootfs format.
`validate-openwrt-full-image.py` compares every segment with its exact source
file and checks erased space. `wait-openwrt-boot.sh` checks both networking and
a real serial-shell response. These checks are not a substitute for a backup.

## Runtime details / 运行时细节

- `vm.min_free_kbytes=768` is included in the read-only rootfs and is therefore
  applied on every boot. It is not a user-overlay persistence claim.
- The random seed is generated locally during preinit. No shared
  `/etc/urandom.seed` is shipped in the public image; each device generates its
  own seed instead of reusing a developer's file.
- The AP is intentionally open in this development image. The documented root
  password is also a development default. Do not expose this image to an
  untrusted network without changing the security configuration.
- Audio, Matter/OTBR, X and SD storage are outside this OpenWrt release's
  verified feature set.

## 开发说明（中文）

- 本包是 OpenWrt 用户态移植，不是上游官方 target。
- 当前启动链为 `flash-init → mtdblock0 squashfs → procd`，rootfs 是 ilp32f musl。
- `openwrt/esp32s31/files/` 是板级 overlay 权威源；`linux-openwrt.config` 独立，
  不与桌面或 Buildroot flash 配置混用。
- 当前使用现有 UBI data 卷上的持久 UBIFS overlay，OpenWrt 独立使用
  `/overlay/openwrt/{upper,work}`；全空 MTD 初始化仍需板上验收，非 UBI 数据不会被主动擦除。
- `SQUASHFS_FILE_DIRECT` 直接解压到页缓存，省去中间缓冲区和第二次复制；
  中英文性能机制、对照数据与限制见 `README.md`。
- ucode 插件在启动时预初始化 VM；每请求仍 fork，但不 exec 新解释器。
- `vm.min_free_kbytes=768` 已写入只读 rootfs，因此每次启动都会应用。
- 公开镜像不带开发者的共享随机种子，preinit 会在本机生成新的随机种子。
- 开放 AP 和默认 root 密码仅用于受控开发环境，不要直接暴露到不可信网络。
- 音频、Matter/OTBR、X 和 SD 存储不属于本版本已验证能力。
