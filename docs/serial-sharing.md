# 共享 S31 串口守护台

Linux 与 OpenWrt session 共用同一个常驻 daemon，不因普通命令或 OS 切换而重开串口。默认设备为 `${S31_PORT:-/dev/ttyUSB0}`；只有 esptool 等必须独占串口硬件的操作才临时停止 daemon，并在同一事务结束后恢复。

## 普通命令

```sh
S31_SESSION=linux-flash tools/srun.sh 'uname -a' 5
S31_SESSION=openwrt tools/srun.sh 'cat /proc/meminfo' 5
```

保留原接口：`srun.sh 'command' [wait_seconds]`。不要绕过客户端直接写 `/tmp/s31in`。

普通请求按以下顺序持锁，直到“发送 + 固定 wait + 截取输出”完成：

1. `/tmp/s31-board.lock` shared；
2. `/tmp/s31-command.lock` exclusive。

因此普通请求可以快速串行执行，且不会和独占事务同时写板。固定 wait 不是板上命令的退出状态；它只截取该等待窗口内的字节，不吞掉窗口后的迟到输出。FIFO 写入使用有超时的非阻塞 helper，FIFO 无读者时会明确失败而不是永久卡住。

需要等待真实完成和板上退出码时，使用完成感知客户端：

```sh
S31_SESSION=linux-flash tools/srun-wait.sh '/tmp/s31-system-bench full /bin/busybox' 120
```

`srun-wait.sh` 注入唯一完成标记并轮询本次输出，直到收到板上退出码或超时。超时返回 124，不能继续发送下一轮；不要重发仍在运行的命令。

## 独占事务

```sh
S31_SESSION=linux-flash S31_REASON='flash ilp32f A/B' \
  tools/s31-exclusive.sh bash tools/flash-linux-headless.sh

S31_SESSION=openwrt S31_REASON='30 minute network benchmark' \
  tools/s31-exclusive.sh bash tools/openwrt-bench.sh
```

独占 helper 对 `/tmp/s31-board.lock` 持 exclusive，并导出 `S31_BOARD_EXCLUSIVE=1` 与唯一 `S31_EXCLUSIVE_ID`。嵌套请求必须同时匹配 lease ID、owner 文件和实际排他锁才能绕过 board lock；**command lock 始终保留**，所以并发嵌套 `srun` 仍然串行。过期后台子进程只会得到“stale lease”错误，不能在其他 owner 取得板子后绕过锁。重复进入 helper 只在 lease 仍活跃时允许。

lease 必须覆盖整个干扰窗口：

- 复位、刷写、停/起 daemon；
- OS 切换直到新系统 boot-ready；
- 长压测全过程，而不只是启动压测的那一条命令。

默认锁等待 60 秒，可用 `S31_LOCK_TIMEOUT` 调整；忙时退出码为 75。锁由进程异常退出自动释放。`/tmp/s31-exclusive.owner` 保存 lease ID/owner/PID/reason，客户端还会用实际 flock 验证它是否仍活跃；异常退出后的残留文件本身不会授权 bypass。普通子进程继承锁 FD，使 lease 覆盖所有后代；长期驻留的 daemon 启动时会清除继承的 lease 环境并显式 `9>&-`，避免锁永不释放。

## 请求日志与敏感信息

`/tmp/s31-requests.log` 记录 request-id、owner、PID、开始/结束时间、普通请求的输出偏移和独占结果。**默认不记录板上命令内容**。原始 `/tmp/s31out.log` 仍可能因 shell echo 而包含命令或敏感输出，不要写入该日志或公开发布其中的凭据。

`s31out.log` 跨多次启动追加，不能仅凭旧 banner 认定本次启动成功。每次 OS/内核切换都要使用新的时间/偏移和本次启动证据。

原始 FIFO 工具（如 `push-serial.sh`、`serial-stream.py`、`verify-calm-boot.sh`）在迁移前一律放入独占 helper 中运行。OpenWrt 的 `flash-openwrt-{all,kernel,rootfs}.sh` 已通过重入自身接入同一 lease，并在写盘、恢复 daemon 后调用 `tools/wait-openwrt-boot.sh`，直到网络与串口 shell 均可用才释放。`tools/flash-openwrt-console.sh` 的 EXIT trap 也会在 flash 失败路径恢复 daemon，重启时用 `env -u S31_BOARD_EXCLUSIVE -u S31_EXCLUSIVE_ID` 清除继承 lease；可用 `tools/test-flash-console.sh` 做无硬件生命周期测试。

## 主机测试

```sh
python3 -I tools/test-serial-sharing.py
```

测试使用临时目录中的伪 FIFO/log，不打开真实串口。默认运行时目录是 `/tmp`；测试或特殊环境可设置 `S31_RUNTIME_DIR`，客户端和真实 daemon 都会使用其中的 `s31in`、`s31out.log`、锁、请求日志和 daemon 日志。测试还覆盖无 FIFO 读者、迟到输出、完成标记、嵌套并发、lease 过期和自定义运行时路径。
