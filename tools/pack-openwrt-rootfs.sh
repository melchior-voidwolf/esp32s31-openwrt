#!/bin/bash
# Pack an OpenWrt rootfs with the deadc0de marker for the optional jffs2
# overlay.  Arguments: [staging-dir] [output-image]
set -euo pipefail

ESP32S31_ROOT=${ESP32S31_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
STAGING=${1:-/tmp/owrt-rootfs}
OUT=${2:-$ESP32S31_ROOT/build/korvo1-openwrt/rootfs.squashfs}

[ -d "$STAGING/etc" ] || { echo "invalid rootfs staging directory: $STAGING"; exit 1; }
mkdir -p "$(dirname "$OUT")"
chmod 0600 "$STAGING/etc/urandom.seed" 2>/dev/null || true
mksquashfs "$STAGING" "$OUT" -comp xz -b 128k -all-root -noappend -quiet

SZ=$(stat -c%s "$OUT")
PAD=$(( (65536 - SZ % 65536) % 65536 ))
truncate -s $(( SZ + PAD )) "$OUT"
printf '\xde\xad\xc0\xde' >> "$OUT"
NEWSZ=$(stat -c%s "$OUT")
echo "squashfs=$SZ padded=$((SZ+PAD)) final=$NEWSZ (free in 4MiB part: $((4194304 - NEWSZ)) bytes)"
xxd -s $((SZ+PAD)) -l 4 "$OUT"
