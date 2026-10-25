#!/bin/sh
# board-fetch — fastfetch-style sysinfo card for the ESP32-S31 OpenWrt AP.
# Runs on the board (busybox ash). Screenshot-worthy for SNS.
b() { printf '\033[1m%s\033[0m' "$1"; }
c() { printf '\033[36m%s\033[0m\n' "$1"; }

REL=$(grep -m1 DISTRIB_DESCRIPTION /etc/openwrt_release | cut -d\' -f2)
KER=$(uname -sr)
MT=$(awk '/MemTotal/{print $2}' /proc/meminfo)
MA=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
LOAD=$(cut -d' ' -f1 /proc/loadavg)
UP=$(awk '{d=int($1/86400);h=int($1%86400/3600);m=int($1%3600/60);printf "%dd %dh %dm",d,h,m}' /proc/uptime)
IP=$(ip -4 addr show br-lan | awk '/inet /{print $2}' | cut -d/ -f1)
SSID=$(awk -F= '/^ssid/{print $2}' /etc/hostapd.conf)
PORTS=$(ls /sys/class/net/br-lan/brif 2>/dev/null | tr '\n' ' ')
SWAP=$(awk '/zram/{printf "%s kB",$3}' /proc/swaps 2>/dev/null)
[ -n "$SWAP" ] || SWAP=off
NOW=$(date '+%Y-%m-%d %H:%M:%S %Z')

echo
c '   ┌──────────────────────────┐'
c '   │        ESP32-S31         │'
c '   │   RISC-V · 320 MHz · FPU │'
c '   └──────────────────────────┘'
echo
printf '  %s  %s\n' "$(b 'OS')"      "$REL"
printf '  %s  %s (rv32imafc)\n' "$(b 'Kernel')" "$KER"
printf '  %s  %s kB / %s kB avail\n' "$(b 'RAM')" "$MT" "$MA"
printf '  %s  %s (zram)\n' "$(b 'Swap')" "$SWAP"
printf '  %s  %s\n' "$(b 'Uptime')"  "$UP"
printf '  %s  %s\n' "$(b 'Load')"    "$LOAD"
printf '  %s  br-lan %s\n' "$(b 'LAN')" "$IP"
printf '  %s  %s\n' "$(b 'Bridge')"  "$PORTS"
printf '  %s  %s (open)\n' "$(b 'AP')" "$SSID"
printf '  %s  squashfs on 16 MB flash MTD\n' "$(b 'Rootfs')"
printf '  %s  %s\n' "$(b 'Time')"   "$NOW"
echo
