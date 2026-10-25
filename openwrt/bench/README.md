# OpenWrt 性能验证与复现

权威状态见 `../HANDOFF.md` 顶部。这里保存原始数据，不保存密码或 session token。

## 当前已验证结论

- LuCI ucode 插件：启动期预初始化；每请求 fork 继承 VM，但不 exec。不是无 fork，也不是常驻处理全部请求。
- `vm.min_free_kbytes=768` 已持久化。高 1024 水位会造成 page-cache 回收/重读抖动；flash `_read` 是 window memcpy，不是每次 RPC。
- 768 持续 10 分钟：1790 请求，p50 0.312s、p95 0.317s、p99 0.428s；>1s 0.39%、>2s 0.22%，无 OOM/5xx/超时。
- 持久化冷启动后：概览 p50 0.300s、接口 p50 0.284s。长尾仍存在，不能宣称完全解决。
- UBIFS + `SQUASHFS_FILE_DIRECT` 12 分钟对照：1357 次请求全 HTTP 200、无 OOM，p50 0.312s、p95 2.162s、p99 3.824s；相对 FILE_CACHE 请求数 +68.4%、p95 约减半。最终 MemAvailable=1052KiB，长尾仍未消失。
- 同 GCC 无库微基准：局部 float≈1.00×、跨函数 float ABI≈1.14–1.15×、zba≈1.60×、软件位操作回退→硬件≈1.9×。受控 `-O2` 微基准，不等同 OpenWrt 包默认 `-Os`，也不能外推成 LuCI/网络吞吐提升。

## 文件索引

- `nolib-*`：同 GCC 无运行库 ABI/ISA 二进制、反汇编、原始日志、结果和哈希。
- `isa-abi-*`：带 musl 的补充基准；`sqrtf` 结果包含库/工具链差异，不是纯 ABI 数字。
- `luci-auth-bench.*`：真实登录和中文页面测试脚本/样本。运行前设置 `LUCI_PASSWORD`，可选 `LUCI_OVERVIEW_COUNT`、`LUCI_NETWORK_COUNT`。
- `luci-vm-abba-1024-512*`、`luci-vm-abba-1024-768*`：同会话水位 ABBA 原始数据。
- `luci-vm-soak-768*`：768 持续负载原始数据与每分钟内存/mtd/zram 快照。
- `ubifs-slim-20261025/`：UBIFS + FILE_CACHE 基线，含真实重启持久性前置版本、认证 smoke 和 12 分钟 soak。
- `ubifs-direct-20261025/`：UBIFS + FILE_DIRECT 对照、认证 smoke 与快照。
- `luci-vm-abba.py`、`luci-vm-soak.py`：水位对照驱动。可用 `LUCI_VM_ALT` 改候选值；ABBA 结束恢复 1024，soak 结束恢复测试前读到的原值。
- `luci-vm-block-summary.py`：按块比较时延、MemAvailable、zram 和 MTD 读增量，参数为结果 JSON 与快照日志。
- `luci-perf/`：临时分段插桩源码与安装/恢复脚本。原始 dispatcher 已恢复；插桩结果受系统状态和自身扰动影响，不是纯净基线。

## 常用复现命令

```sh
# 严格无库 ABI/ISA 构建与反汇编检查
bash tools/isa-abi-nolib-build.sh

# 真实 LuCI 登录测试（密码只走环境变量）
LUCI_PASSWORD=... python3 -I openwrt/bench/luci-auth-bench.py

# 短水位 ABBA，结束自动恢复 1024
LUCI_PASSWORD=... LUCI_VM_ALT=768 python3 -u openwrt/bench/luci-vm-abba.py

# 持续负载，结束自动恢复测试前的原水位
LUCI_PASSWORD=... LUCI_VM_ALT=768 LUCI_SOAK_SECONDS=600 \
  python3 -u openwrt/bench/luci-vm-soak.py

# 共享串口与刷写锁的主机伪 FIFO 测试
python3 -I tools/test-serial-sharing.py
```

板上并发操作必须遵守 `docs/serial-sharing.md`：普通命令走 `tools/srun.sh`，复位/刷写/长压测走 `tools/s31-exclusive.sh`。不要并发直接写 `/tmp/s31in`。
