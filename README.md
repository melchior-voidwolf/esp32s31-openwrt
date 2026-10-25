# ESP32-S31 OpenWrt

OpenWrt firmware and development files for the **Korvo-1** board.
适用于 **Korvo-1 开发板**的 OpenWrt 固件和开发文件。

This is a development release, not an official OpenWrt target or a production
router image. 这不是 OpenWrt 官方支持的开发板，也不是面向生产环境的路由器镜像。

## 中文说明

### 这是什么

- OpenWrt **25.12.6**，Linux **7.3**，RISC-V **ilp32f** musl 用户态。
- SPI flash 启动：`flash-init → mtdblock0 squashfs → procd`。
- 无 X、无桌面；串口控制台和中文 LuCI 管理。
- `br-lan` 桥接 RTL8153 有线网卡和 S31 无线 AP，管理地址 **10.0.0.84/24**。
- 默认开放 SSID **`esp32s31-openwrt`**；上级网络负责 DHCP，本机不默认做 NAT。
- `uhttpd-mod-ucode`、中文 LuCI、NTP/CST、`vm.min_free_kbytes=768`。
- 固件包含备份、分段更新、完整刷写和恢复工具。

### 已验证

- 完整刷写与回读校验通过；冷启动可进入 OpenWrt。
- overlay 可写、AP-ENABLED、NTP 正常、网关 ping 无丢包。
- 中文“概览”和“接口”页面真实登录均为 HTTP 200。
- 768 持续 10 分钟、1790 个请求：p50 **0.312s**、p95 **0.317s**、p99 **0.428s**；
  >1s 占 **0.39%**，>2s 占 **0.22%**，无 OOM/5xx/超时。
- 持久化后概览 p50 **0.300s**、接口 p50 **0.284s**。

### 重要限制

- **仅支持 Korvo-1**，不要刷到其他 ESP32/ESP32-S3/S31 开发板。
- **开放 AP**：当前没有可用的 WPA2 softAP 配置，不能当作安全路由器使用。
- **安全默认值**：默认 root 密码和 HTTP 明文管理只适合隔离/可信实验网络；不要暴露到不可信网络。运行时改密在 tmpfs overlay 上重启会丢失，生产使用应重新构建自己的安全配置。
- 无线首次关联偶发失败，这是当前 ESP-Hosted 固件路径的已知问题。
- 当前 overlay 是 **tmpfs**，重启会丢失运行时修改，**不是持久 UBIFS**。
- Linux `MemTotal` 约 **10.8 MiB**；16 MiB 是 flash 容量，不是可用 RAM。`MemAvailable` 仍低于 3 MiB 的目标；LuCI 长尾只是显著减少，并未完全消失。
- 不包含 X、音频、摄像头、Matter/OTBR，也不包含 SSH 服务端；Bluetooth 功能未在本 OpenWrt 镜像中验收。
- 网络由 `lanstatic` 直接配置，未验证标准 NAT、DHCP 服务器、防火墙或 LuCI 网络保存/应用。
- SD p1 中旧的 `IMAGE.BIN` 可能优先于 flash 内核启动，使用前请移除或改名。
- 公开镜像不带开发者的共享随机种子，preinit 会在每台设备上生成本地随机种子。
- 本项目不保证上游 OpenWrt 的包仓库、sysupgrade 或所有 LuCI 页面均可用。

### 文件说明

| 文件 | 用途 |
|---|---|
| `build/korvo1-openwrt/Image-7.3-flash-initramfs` | Linux 7.3 与 flash-init |
| `build/korvo1-openwrt/linux.size` | 内核 magic/size/CRC32 manifest |
| `build/korvo1-openwrt/rootfs.squashfs` | ilp32f OpenWrt rootfs，含 768 配置 |
| `build/korvo1-openwrt/openwrt-flash-16m.img` | 完整 16 MiB 镜像，**会擦除全部 flash** |
| `flash.sh` | 备份、更新、完整刷写、恢复入口 |
| `tools/` | 构建、刷写、验证、串口和基准工具 |
| `openwrt/esp32s31/` | OpenWrt target/overlay/配置文件 |
| `docs/` | 交接、性能和串口共享说明 |

### 环境准备

- Korvo-1 和 CP2102N 串口，Ubuntu 上通常是 `/dev/ttyUSB0`。
- `esptool 5.6.0`、`pyserial`、`flock`、`ping`。
- 可用 `S31_PORT` 和 `ESPTOOL` 环境变量覆盖默认路径。
- 不要并发打开串口；刷写前停止其它串口任务或使用项目提供的独占工具。

### 先备份

```sh
./flash.sh backup
```

默认在 `backups/<时间>-openwrt/` 下保存两次读取结果、`full.img`、日志和
`SHA256SUMS`。请把备份移到安全位置，不要只留在开发板或临时目录里。

### 常规更新（不主动擦除 data）

```sh
./flash.sh update
```

该命令先备份，再在同一次 esptool 调用中写入 kernel、manifest 和 rootfs。
**已有经过校验的备份时**才使用：

```sh
./flash.sh update --no-backup
```

### 整片刷写（清空全部 flash）

```sh
./flash.sh full
```

**警告：这会替换完整 16 MiB flash，包括 data 区域和已有系统。**
不要在不理解备份和恢复流程的情况下执行。首次部署必须先生成并校验备份。

### 从备份恢复

```sh
./flash.sh restore backups/<备份目录>
```

恢复目录必须包含 `full.img` 和对应的 `SHA256SUMS`。恢复同样是整片擦写。

### 启动后

- 首次启动和有线桥接就绪可能需要约一分钟；请等待 `OPENWRT_BOOT_READY`。
- LuCI：`http://10.0.0.84/`
- 用户名：`root`
- 默认密码：`iesp32web`（仅用于开发，登录后请修改）
- 无线：`esp32s31-openwrt`（开放网络）
- 检查水位：

```sh
cat /proc/sys/vm/min_free_kbytes   # 应为 768
cat /etc/sysctl.d/99-s31.conf
```

串口客户端示例：

```sh
S31_SESSION=openwrt tools/srun.sh 'uname -a' 5
S31_SESSION=openwrt tools/srun-wait.sh 'cat /proc/meminfo' 20
```

### 从源码构建

仓库不包含完整 OpenWrt 上游源码，也不包含整套 Linux 主线源码。
固件和引导组件已经附带，普通用户不需要重新构建。

开发时需要：

1. OpenWrt 源码，当前验证提交为 `64900e756efa667774214f9c6b17c113222e01f7`。
2. 本项目的 `openwrt/esp32s31/` overlay 和 `tools/`。
3. Linux 主线及其构建环境（用于 7.3 内核、loader 和 OpenSBI）。

```sh
git clone https://github.com/openwrt/openwrt.git openwrt/openwrt
git -C openwrt/openwrt checkout 64900e756efa667774214f9c6b17c113222e01f7
bash tools/owrt-apply-target.sh
cp openwrt/esp32s31/korvo1.config.fragment openwrt/openwrt/.config
make -C openwrt/openwrt defconfig
make -C openwrt/openwrt target/linux/install package/compile package/install -j"$(nproc)"
SKIP_KERNEL=1 bash tools/owrt-finish-all.sh
```

Linux 主线参考：[esp32-s31-linux-eXtends](https://github.com/melchior-voidwolf/esp32-s31-linux-eXtends)。
OpenWrt 专用配置位于 `linux/repo/br2-external/board/esp32s31/linux-openwrt.config`，
不要与桌面或 Buildroot flash 的配置混用。

### 许可证

发布内容以 **GPL-2.0-only** 提供。OpenWrt、Linux、ESP-IDF、OpenSBI 及其它
上游组件同时具有各自原始许可证和声明，见 `LICENSE` 与 `NOTICE`。

---

## English

### Overview

- **OpenWrt 25.12.6**, Linux **7.3**, RISC-V **ilp32f** musl userland.
- SPI-flash boot: `flash-init → mtdblock0 squashfs → procd`.
- Headless image with a serial console and Chinese LuCI.
- `br-lan` bridges the RTL8153 Ethernet adapter and the S31 wireless AP.
  Management address: **10.0.0.84/24**.
- Open SSID **`esp32s31-openwrt`**; upstream networking provides DHCP.
  NAT is not enabled by default.
- `uhttpd-mod-ucode`, Chinese LuCI, NTP/CST and `vm.min_free_kbytes=768`.
- Backup, segmented update, full-flash and restore utilities are included.

### Verified status

- Flash write/read-back and cold-boot checks passed.
- Writable overlay, AP-ENABLED, NTP and gateway ping passed.
- Authenticated Chinese “Overview” and “Interfaces” pages returned HTTP 200.
- A 10-minute run of 1790 requests produced p50 **0.312s**, p95 **0.317s**,
  p99 **0.428s**, with **0.39%** over 1s and **0.22%** over 2s, without
  OOM, HTTP 5xx or timeouts.
- After persistence, the overview and interface medians were **0.300s** and
  **0.284s** respectively.

### Important limitations

- **Korvo-1 only.** Do not flash this image onto other boards.
- The AP is **open**. A working WPA2 softAP configuration is not available;
  this is not a secure production router configuration.
- **Security defaults:** the documented root password and plain HTTP management
  are for isolated/trusted lab networks only. Do not expose them to untrusted
  networks. Password changes in tmpfs are lost on reboot; rebuild with your own
  security configuration for any real deployment.
- The first wireless association can fail occasionally in the current
  ESP-Hosted firmware path.
- The overlay is **tmpfs**, not persistent UBIFS. Runtime changes are lost on reboot.
- Linux `MemTotal` is about **10.8 MiB**; 16 MiB is flash capacity, not usable RAM.
  `MemAvailable` remains below the 3 MiB target. LuCI tail latency is reduced,
  not eliminated.
- X, audio, camera, Matter/OTBR and an SSH server are not included. Bluetooth
  functionality is not validated in this OpenWrt image.
- Networking is configured by `lanstatic`; standard NAT, a DHCP server, the
  firewall and LuCI network save/apply are not validated.
- An old `IMAGE.BIN` on SD p1 may take precedence over the flash kernel;
  remove or rename it before relying on the flash image.
- No shared developer random seed is shipped; each device generates a local
  seed during preinit.
- Upstream package feeds, sysupgrade and every LuCI page are not guaranteed.

### Package contents

- `Image-7.3-flash-initramfs`: Linux 7.3 and flash-init.
- `linux.size`: kernel magic/size/CRC32 manifest.
- `rootfs.squashfs`: ilp32f OpenWrt rootfs with the 768 setting.
- `openwrt-flash-16m.img`: complete 16 MiB image; **erases the entire flash**.
- `flash.sh`: backup, update, full-flash and restore entry point.
- `tools/`: build, flash, validation, serial and benchmark utilities.
- `openwrt/esp32s31/`: OpenWrt target and board overlay.
- `docs/`: handoff, performance and serial-sharing documentation.

### Requirements

- A Korvo-1 board and CP2102N serial connection, normally `/dev/ttyUSB0` on Ubuntu.
- `esptool 5.6.0`, `pyserial`, `flock` and `ping`.
- Override defaults with `S31_PORT` and `ESPTOOL` if needed.
- Do not open the serial port concurrently. Use the supplied exclusive wrapper
  when another project may be using the board.

### Back up first

```sh
./flash.sh backup
```

Two complete reads, `full.img`, logs and `SHA256SUMS` are written to
`backups/<timestamp>-openwrt/`. Keep a copy somewhere safe, not only on the
board or in a temporary directory.

### Normal update (does not explicitly erase data)

```sh
./flash.sh update
```

This backs up first, then writes kernel, manifest and rootfs in one esptool
call. Use `--no-backup` **only when a verified backup already exists**:

```sh
./flash.sh update --no-backup
```

### Full flash (erases everything)

```sh
./flash.sh full
```

**Warning:** this replaces the complete 16 MiB flash, including the data area
and any existing system. Back up and verify before using it.

### Restore a backup

```sh
./flash.sh restore backups/<backup-directory>
```

The directory must contain `full.img` and its `SHA256SUMS`. Restore is also a
complete flash erase and write.

### After boot

- The first boot and Ethernet bridge setup can take about one minute.
- LuCI: `http://10.0.0.84/`
- User: `root`
- Development password: `iesp32web` — change it after login.
- Wireless: `esp32s31-openwrt` (open network).
- Check the setting with `cat /proc/sys/vm/min_free_kbytes` (expected: `768`).
- Serial clients:

```sh
S31_SESSION=openwrt tools/srun.sh 'uname -a' 5
S31_SESSION=openwrt tools/srun-wait.sh 'cat /proc/meminfo' 20
```

### Build from source

The full upstream OpenWrt and Linux source trees are not bundled. Firmware and
boot components are included, so a normal user does not need to build anything.

For development, use OpenWrt commit `64900e756efa667774214f9c6b17c113222e01f7`,
this repository's overlay and tools, and a separate Linux mainline checkout for
kernel, loader and OpenSBI work:

```sh
git clone https://github.com/openwrt/openwrt.git openwrt/openwrt
git -C openwrt/openwrt checkout 64900e756efa667774214f9c6b17c113222e01f7
bash tools/owrt-apply-target.sh
cp openwrt/esp32s31/korvo1.config.fragment openwrt/openwrt/.config
make -C openwrt/openwrt defconfig
make -C openwrt/openwrt target/linux/install package/compile package/install -j"$(nproc)"
SKIP_KERNEL=1 bash tools/owrt-finish-all.sh
```

Linux mainline reference: [esp32-s31-linux-eXtends](https://github.com/melchior-voidwolf/esp32-s31-linux-eXtends).
Use `linux-openwrt.config` for this OpenWrt line; do not mix it with desktop or
Buildroot flash configurations.

### License

Distributed under **GPL-2.0-only**. OpenWrt, Linux, ESP-IDF, OpenSBI and other
upstream components retain their original licenses and notices. See `LICENSE`
and `NOTICE`.
