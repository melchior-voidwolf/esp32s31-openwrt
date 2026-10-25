#!/bin/bash
# User-facing backup, update, full-flash and restore entry point.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
if [ -d "$HERE/build/korvo1-openwrt" ]; then
  ROOT=$HERE
else
  ROOT=$(cd "$HERE/.." && pwd)
fi
ROOT=${ESP32S31_ROOT:-$ROOT}
. "$ROOT/tools/s31-lease-common.sh"
ACTION=${1:-help}
[ "$#" -gt 0 ] && shift || true
if ! s31_exclusive_valid "${S31_RUNTIME_DIR:-/tmp}"; then
  export S31_SESSION="${S31_SESSION:-openwrt}"
  export S31_REASON="${S31_REASON:-OpenWrt $ACTION}"
  exec "$ROOT/tools/s31-exclusive.sh" "$0" "$ACTION" "$@"
fi

usage() {
  printf '%s\n' \
    'Usage:' \
    '  ./flash.sh backup [backup-dir]' \
    '  ./flash.sh update [--no-backup]   # kernel + manifest + rootfs; keeps data' \
    '  ./flash.sh full [--no-backup]     # complete 16 MiB; erases everything' \
    '  ./flash.sh restore BACKUP_DIR|full.img' \
    '' \
    'Environment: S31_PORT=/dev/ttyUSB0 ESPTOOL=/path/to/esptool S31_SESSION=name'
}

case "$ACTION" in
  backup)
    bash "$ROOT/tools/backup-s31-flash.sh" "$@"
    ;;
  update|full)
    NO_BACKUP=0
    if [ "${1:-}" = "--no-backup" ]; then
      NO_BACKUP=1
      shift
    fi
    [ "$#" -eq 0 ] || { usage; exit 2; }
    if [ "$NO_BACKUP" = 0 ]; then
      bash "$ROOT/tools/backup-s31-flash.sh"
    else
      echo "WARNING: skipping backup; use only when a verified backup already exists" >&2
    fi
    if [ "$ACTION" = update ]; then
      bash "$ROOT/tools/flash-openwrt-all.sh"
    else
      bash "$ROOT/tools/flash-openwrt-full.sh"
    fi
    ;;
  restore)
    [ "$#" -eq 1 ] || { usage; exit 2; }
    bash "$ROOT/tools/restore-s31-flash-backup.sh" "$1"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage
    exit 2
    ;;
esac
