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

- 完整刷写与回读校验通过；无共享随机种子版本已冷启动并生成本地种子，未见缺失或权限警告。
- AP-ENABLED、NTP 正常、网关 ping 无丢包；中文“概览”和“接口”页面真实登录均为 HTTP 200。
- **UBIFS 持久 overlay 已通过真实重启验证**：测试文件在根文件系统和 UBIFS upper 中一致，Buildroot 的 `/upper`、`/work` 保持独立。
- `SQUASHFS_FILE_DIRECT` 的 12 分钟持续测试中，**1357 次请求全部 HTTP 200，无 OOM、5xx 或超时**，最终 `MemAvailable=1052KiB`。

### 性能优化：原理与实测

这次优化分为两个独立部分，不把内核裁剪的收益与 DIRECT 的收益混算：

1. **内核减负解决稳定性**：把无效的 `# CONFIG_X=y (dropped)` 改为真正的
   `# CONFIG_X is not set`，移除 JFFS2、HID 和多余 USB 网卡，Image 减少
   **192,432 bytes**，为 UBIFS 留出内存，避免启动期连续 OOM。
2. **DIRECT 缩短解压路径**：旧 `SQUASHFS_FILE_CACHE` 路径是
   `Flash → XZ 解压到中间缓冲区 → memcpy 到页缓存`；新
   `SQUASHFS_FILE_DIRECT` 路径是 `Flash → 直接解压到页缓存`。effective
   配置同时使用适合单核的 `SQUASHFS_DECOMP_SINGLE`。
3. **减少缓存抖动**：少了中间缓冲区和一次复制，降低内存回收与重复 Flash
   读取。实测 DIRECT 在完成更多请求的同时 MTD 读取量反而更低，因此主要改善的是
   缓存未命中和内存回收造成的长尾，不是所有指令都等比加速。

相同 UBIFS、`vm.min_free_kbytes=768`、12 分钟 LuCI 认证请求对照：

| 指标 | FILE_CACHE | SQUASHFS_FILE_DIRECT |
|---|---:|---:|
| 完成请求数 | 806 | **1357（+68.4%）** |
| p50 | 0.324s | **0.312s** |
| p95 | 4.237s | **2.162s** |
| p99 | 5.534s | **3.824s** |
| >1s 请求比例 | 18.49% | **8.33%** |
| 结束 MemAvailable | 948KiB | **1052KiB** |
| OOM / 5xx / 超时 | 均无 | 均无 |

这里的 **+68.4% 是这组 LuCI 负载在固定 12 分钟内完成请求数的提升**，不是全系统
统一提速。典型热缓存请求仍受 uhttpd/ucode/fork/ubus 等路径限制，p50 只小幅改善；
长尾显著减少但未消失。原始数据和复现脚本见
`openwrt/bench/ubifs-slim-20261025/`、`openwrt/bench/ubifs-direct-20261025/`。

### 重要限制

- **仅支持 Korvo-1**，不要刷到其他 ESP32/ESP32-S3/S31 开发板。
- **开放 AP**：默认仍是开放网络；WPA2 开发配置只验证到 `AP-ENABLED`，尚未通过真实客户端关联，不能当作安全路由器使用。
- **安全默认值**：默认 root 密码和 HTTP 明文管理只适合隔离/可信实验网络。持久 UBIFS 会保存改密等运行时修改，但这不改变镜像默认凭据不安全的起点；首次登录后应改密，不要暴露到不可信网络。
- 无线首次关联仍需真实客户端回归，不能把 ESP-Hosted 的 AP-ENABLED 日志视为首连问题已修复。
- **持久化边界**：目前验证的是复用已有 UBI data 卷；全空 MTD 的初始化路径尚未板上验收，非 UBI 数据不会被主动擦除，失败时回退 tmpfs（此时修改重启丢失）。Buildroot 回切交叉验收尚未完成。
- Linux `MemTotal` 约 **10.8 MiB**；16 MiB 是 flash 容量，不是可用 RAM。`MemAvailable` 仍低于 3 MiB 的目标；LuCI 长尾只是显著减少，并未完全消失。
- 不包含 X、音频、摄像头、Matter/OTBR，也不包含 SSH 服务端；Bluetooth 功能未在本 OpenWrt 镜像中验收。
- 网络由 `lanstatic` 直接配置，未验证标准 NAT、DHCP 服务器、防火墙或 LuCI 网络保存/应用。
- SD p1 中旧的 `IMAGE.BIN` 可能优先于 flash 内核启动，使用前请移除或改名。
- 公开镜像不带开发者的共享随机种子，preinit 会在每台设备上生成本地随机种子。
- 本项目不保证上游 OpenWrt 的包仓库、sysupgrade 或所有 LuCI 页面均可用。

### 文件说明

| 文件 | 用途 |
|---|---|
| `build/korvo1-openwrt/Image-7.3-flash-initramfs` | Linux 7.3、flash-init、UBIFS 与 SquashFS DIRECT |
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

- Flash write/read-back and cold-boot checks passed. The no-shared-seed image generated a local seed during preinit without missing-seed or permission warnings.
- AP-ENABLED, NTP and gateway ping passed. Authenticated Chinese “Overview” and “Interfaces” pages returned HTTP 200.
- **The persistent UBIFS overlay passed a real reboot test:** the test file matched in the root filesystem and the UBIFS upper directory, while Buildroot's `/upper` and `/work` remained separate.
- A 12-minute `SQUASHFS_FILE_DIRECT` run completed **1357 authenticated LuCI requests with HTTP 200 throughout and no OOM, HTTP 5xx or timeouts**, ending with `MemAvailable=1052KiB`.

### Performance optimization: mechanism and measurements

Kernel slimming and DIRECT address different problems, so their effects are not
lumped together:

1. **Kernel slimming improves stability.** Ineffective
   `# CONFIG_X=y (dropped)` comments were changed to real
   `# CONFIG_X is not set` entries. Removing JFFS2, HID and unused USB NIC
   drivers reduced the Image by **192,432 bytes**, leaving enough memory for
   UBIFS instead of repeated boot-time OOM kills.
2. **DIRECT shortens the decompression path.** `SQUASHFS_FILE_CACHE` uses
   `Flash → XZ decompress into an intermediate buffer → memcpy into page cache`.
   `SQUASHFS_FILE_DIRECT` uses `Flash → decompress directly into page-cache pages`.
   The effective configuration also selects `SQUASHFS_DECOMP_SINGLE`, matching
   the single-CPU board.
3. **Less cache churn.** Removing an intermediate buffer and a copy reduces
   reclaim pressure and repeated Flash reads. DIRECT completed more requests
   while recording fewer MTD reads, so its main benefit is fewer cache-miss and
   reclaim stalls, not a uniform speedup for every instruction.

Same UBIFS setup, `vm.min_free_kbytes=768`, and 12 minutes of authenticated LuCI
requests:

| Metric | FILE_CACHE | SQUASHFS_FILE_DIRECT |
|---|---:|---:|
| Completed requests | 806 | **1357 (+68.4%)** |
| p50 | 0.324s | **0.312s** |
| p95 | 4.237s | **2.162s** |
| p99 | 5.534s | **3.824s** |
| Requests over 1s | 18.49% | **8.33%** |
| Final MemAvailable | 948KiB | **1052KiB** |
| OOM / HTTP 5xx / timeouts | None | None |

The **68.4% gain is the number of completed requests in this fixed-duration LuCI
workload**, not a system-wide performance claim. Hot-cache requests are still
bounded by uhttpd/ucode/fork/ubus and similar work, so p50 changes only slightly.
Tail latency is substantially reduced, not eliminated. Raw data and reproduction
scripts are in `openwrt/bench/ubifs-slim-20261025/` and
`openwrt/bench/ubifs-direct-20261025/`.

### Important limitations

- **Korvo-1 only.** Do not flash this image onto other boards.
- The AP is **open** by default. The development WPA2 configuration reached only `AP-ENABLED`; no real client association has been validated, so this is not a secure production router configuration.
- **Security defaults:** the documented root password and plain HTTP management are for isolated/trusted lab networks only. Persistent UBIFS retains password changes and other runtime modifications, but it does not make the insecure defaults safe. Change the password after the first login and do not expose management to untrusted networks.
- First-association behavior still needs a real-client regression test; an ESP-Hosted AP-ENABLED log does not prove that the issue is fixed.
- **Persistence boundaries:** validation currently covers an existing UBI data volume. The all-empty-MTD initialization path has not been accepted on hardware. Non-UBI data is not explicitly erased; failure falls back to tmpfs, where changes are lost on reboot. A Buildroot switch-back cross-check has not been completed.
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

- `Image-7.3-flash-initramfs`: Linux 7.3, flash-init, UBIFS and SquashFS DIRECT.
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
