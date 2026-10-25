#!/bin/bash
# Wait until OpenWrt networking and the serial shell are both usable.
set -u

ROOT="${ESP32S31_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
HOST="${S31_HOST:-10.0.0.84}"
ATTEMPTS="${S31_BOOT_ATTEMPTS:-24}"
DELAY="${S31_BOOT_DELAY:-5}"
export S31_SESSION="${S31_SESSION:-openwrt}"

attempt=1
while [ "$attempt" -le "$ATTEMPTS" ]; do
  if ping -c 1 -W 1 "$HOST" >/dev/null 2>&1; then
    OUTPUT=$(bash "$ROOT/tools/srun.sh" 'echo $((6 * 7))' 3 2>/dev/null || true)
    if printf '%s\n' "$OUTPUT" | tr -d '\r' | grep -qx '42'; then
      echo "OPENWRT_BOOT_READY host=$HOST attempt=$attempt"
      exit 0
    fi
  fi
  sleep "$DELAY"
  attempt=$((attempt + 1))
done

echo "OPENWRT_BOOT_READY_TIMEOUT host=$HOST attempts=$ATTEMPTS" >&2
exit 1
