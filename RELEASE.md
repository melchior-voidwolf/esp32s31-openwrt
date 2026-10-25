# ESP32-S31 OpenWrt v0.1.0

Release date: 2026-10-25
发布日期：2026-10-25

> These are the historical v0.1.0 notes. For the later UBIFS + SquashFS DIRECT
> development update, see `README.md` and the current `SHA256SUMS`; this file
> does not imply a new release tag.
>
> 本文保留 v0.1.0 历史发布说明。后续 UBIFS + SquashFS DIRECT 开发更新见
> `README.md` 和当前 `SHA256SUMS`；此处不代表已创建新的发布标签。

## English

This is the first packaged development release of ESP32-S31 OpenWrt for the
Korvo-1 board. It includes the tested firmware, board overlay, build tools,
backup/update/restore utilities, performance results and bilingual README.

### Included

- OpenWrt 25.12.6, Linux 7.3, ilp32f musl userland.
- SPI-flash boot, Chinese LuCI, `uhttpd-mod-ucode`, static 10.0.0.84 LAN,
  open AP bridging and NTP/CST.
- `vm.min_free_kbytes=768` and the `uhttpd` ucode plugin enabled.
- Complete image, segmented kernel/manifest/rootfs images, loader/OpenSBI,
  validation and recovery tooling.

### Verification

- Flash read-back and cold boot checks passed. The no-shared-seed image generated a local seed during preinit without missing-seed or permission warnings.
- Writable overlay, AP, Ethernet, NTP and authenticated Chinese LuCI passed.
- A 10-minute, 1790-request run produced p50 0.312s, p95 0.317s and p99 0.428s,
  with no OOM or HTTP 5xx.
- Final overview/interface medians were 0.300s and 0.284s.

### Known limitations

Korvo-1 only; open AP; tmpfs rather than persistent overlay; occasional first
wireless association failure; memory below the 3 MiB target; no X, audio,
camera, Matter/OTBR or SSH server. Tail latency is reduced, not eliminated.

### Artifact hashes

- Kernel: `39bd68250240cfea5f8c8ff3afc6767e8512bcd584613745378642dbe266a1dd`
- Rootfs: `3f1311f7fbcb17a9a4a032120e7677b07ef464b10a4189b797df37b82358e09b`
- Full image: `4451e3e573d56e1ce33d34a3e90cf4fe7c37b0eb4ab51429893bf9476d4098a2`

See `SHA256SUMS` for file-specific checksums. Always create and verify a backup
before flashing. A full-image write or restore erases the complete flash.

## 中文

这是 ESP32-S31 OpenWrt 面向 Korvo-1 的首个打包开发版，包含已验证固件、
板级 overlay、构建工具、备份/更新/恢复工具、性能数据和中英文 README。

### 已包含

- OpenWrt 25.12.6、Linux 7.3、ilp32f musl 用户态。
- SPI flash 启动、中文 LuCI、`uhttpd-mod-ucode`、静态 10.0.0.84、开放 AP
  桥接和 NTP/CST。
- 持久 `vm.min_free_kbytes=768` 和 ucode 插件。
- 完整镜像、分段内核/manifest/rootfs、loader/OpenSBI、校验和恢复工具。

### 已验证

- 刷写回读与冷启动通过；无共享随机种子版本已在 preinit 生成本地种子，未出现缺失或权限警告。
- 可写 overlay、AP、有线网络、NTP、中文 LuCI 真实登录通过。
- 10 分钟 1790 请求：p50 0.312s、p95 0.317s、p99 0.428s，无 OOM/5xx。
- 持久化后概览/接口中位时延分别为 0.300s 和 0.284s。

### 已知限制

仅支持 Korvo-1；开放 AP；overlay 为 tmpfs、重启丢修改；无线首次关联偶发
失败；可用内存低于 3MiB 目标；不包含 X、音频、摄像头、Matter/OTBR 或 SSH
服务端。长尾只是减少，并未完全消失。

### 产物哈希

- 内核：`39bd68250240cfea5f8c8ff3afc6767e8512bcd584613745378642dbe266a1dd`
- Rootfs：`3f1311f7fbcb17a9a4a032120e7677b07ef464b10a4189b797df37b82358e09b`
- 完整镜像：`4451e3e573d56e1ce33d34a3e90cf4fe7c37b0eb4ab51429893bf9476d4098a2`

各文件校验值见 `SHA256SUMS`。刷写前必须完成并校验备份；整片刷写或恢复
都会擦除完整 flash。
