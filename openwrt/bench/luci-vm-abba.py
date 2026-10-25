#!/usr/bin/env python3
"""Exploratory same-session LuCI A/B for vm.min_free_kbytes."""

import collections
import importlib.util
import json
import math
import os
import statistics
import subprocess
from pathlib import Path

ROOT = os.environ.get("ESP32S31_ROOT", str(Path(__file__).resolve().parents[2]))
BENCH = os.path.join(ROOT, "openwrt/bench/luci-auth-bench.py")
RESULTS = os.environ.get("LUCI_VM_RESULTS", "/tmp/luci-vm-abba.json")
SNAPSHOTS = os.environ.get("LUCI_VM_SNAPSHOTS", "/tmp/luci-vm-abba-snapshots.log")
SRUN = os.path.join(ROOT, "tools/srun.sh")
PAGE = "/cgi-bin/luci/admin/status/overview"
ALT_WATERMARK = int(os.environ.get("LUCI_VM_ALT", "512"))

spec = importlib.util.spec_from_file_location("luci_auth", BENCH)
luci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(luci)


def board(command):
    result = subprocess.run(
        ["bash", SRUN, command, "2"],
        capture_output=True,
        text=True,
        timeout=15,
    )
    if result.returncode:
        raise RuntimeError(f"board command failed: {result.returncode}")
    return result.stdout


def snapshot(label):
    output = board(
        "cat /proc/sys/vm/min_free_kbytes; "
        "grep -E 'MemFree|MemAvailable|Cached|SwapFree|AnonPages|SUnreclaim' /proc/meminfo; "
        "cat /sys/block/zram0/mm_stat 2>/dev/null; "
        "cat /sys/block/mtdblock0/stat 2>/dev/null"
    )
    with open(SNAPSHOTS, "a") as stream:
        stream.write(f"\n=== {label} ===\n{output}\n")
    return output


def get_watermark():
    output = board("cat /proc/sys/vm/min_free_kbytes")
    for line in reversed(output.splitlines()):
        value = line.strip()
        if value.isdigit():
            return int(value)
    raise RuntimeError(f"could not parse watermark from: {output!r}")


def set_watermark(value):
    board(f"printf '%s\\n' '{value}' > /proc/sys/vm/min_free_kbytes")
    actual = get_watermark()
    if actual != value:
        raise RuntimeError(f"watermark mismatch: wanted {value}, got {actual}")


def get_overview(session, block, index):
    response = luci.request("GET", PAGE, headers={
        "Cookie": f"sysauth_http={session}",
        "Accept-Language": "zh-CN,zh;q=0.9",
        "Connection": "close",
    })
    body = response["body"]
    if response["status"] != 200 or b'name="luci_password"' in body:
        raise RuntimeError(f"unexpected LuCI response: HTTP {response['status']}")
    row = {
        "block": block,
        "request": index,
        "status": response["status"],
        "bytes": len(body),
        "starttransfer": response["starttransfer"],
        "total": response["total"],
    }
    print(
        f"{block} req{index}: HTTP 200 start={row['starttransfer']:.3f}s "
        f"total={row['total']:.3f}s",
        flush=True,
    )
    return row


def summarize(label, rows):
    values = [row["total"] for row in rows]
    ordered = sorted(values)
    return {
        "n": len(values),
        "p50": statistics.median(values),
        "p95": ordered[math.ceil(len(values) * 0.95) - 1],
        "max": max(values),
        "over_1s": sum(value > 1 for value in values) / len(values),
        "over_2s": sum(value > 2 for value in values) / len(values),
    }


def main():
    for path in (SNAPSHOTS,):
        with open(path, "w"):
            pass
    session = luci.login()
    rows = []
    try:
        set_watermark(1024)
        snapshot("initial")
        sequence = [
            ("warmup", 1024, 4, False),
            ("A1", 1024, 6, True),
            ("B1", ALT_WATERMARK, 6, True),
            ("B2", ALT_WATERMARK, 6, True),
            ("A2", 1024, 6, True),
            ("B3", ALT_WATERMARK, 6, True),
            ("A3", 1024, 6, True),
            ("A4", 1024, 6, True),
            ("B4", ALT_WATERMARK, 6, True),
        ]
        for block, watermark, count, scored in sequence:
            set_watermark(watermark)
            snapshot(f"{block}-before-{watermark}")
            for index in range(1, count + 1):
                row = get_overview(session, block, index)
                row["watermark"] = watermark
                row["scored"] = scored
                rows.append(row)
            snapshot(f"{block}-after-{watermark}")
    finally:
        set_watermark(1024)
        snapshot("restored-1024")
        luci.logout(session)

    scored = [row for row in rows if row["scored"]]
    by_watermark = collections.defaultdict(list)
    by_block = collections.defaultdict(list)
    for row in scored:
        by_watermark[row["watermark"]].append(row)
        by_block[row["block"]].append(row)
    summary = {
        "watermarks": {str(key): summarize(key, values) for key, values in by_watermark.items()},
        "blocks": {key: summarize(key, values) for key, values in by_block.items()},
        "rows": rows,
    }
    with open(RESULTS, "w") as stream:
        json.dump(summary, stream, indent=2)
    print("SUMMARY", json.dumps(summary["watermarks"], sort_keys=True), flush=True)
    print(f"results={RESULTS} snapshots={SNAPSHOTS}", flush=True)


if __name__ == "__main__":
    main()
