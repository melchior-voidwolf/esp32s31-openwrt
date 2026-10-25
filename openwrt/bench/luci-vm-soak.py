#!/usr/bin/env python3
"""Sustained LuCI load test for a candidate vm.min_free_kbytes value."""

import collections
import importlib.util
import json
import math
import os
import statistics
import time
from pathlib import Path

ROOT = os.environ.get("ESP32S31_ROOT", str(Path(__file__).resolve().parents[2]))
DURATION = int(os.environ.get("LUCI_SOAK_SECONDS", "600"))
WATERMARK = int(os.environ.get("LUCI_VM_ALT", "768"))
RESULTS = os.environ.get("LUCI_SOAK_RESULTS", "/tmp/luci-vm-soak.json")

spec = importlib.util.spec_from_file_location(
    "luci_vm", os.path.join(ROOT, "openwrt/bench/luci-vm-abba.py")
)
vm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vm)


def percentile(values, fraction):
    ordered = sorted(values)
    return ordered[math.ceil(len(ordered) * fraction) - 1]


def summarize(rows):
    values = [row["total"] for row in rows]
    return {
        "n": len(values),
        "p50": statistics.median(values),
        "p95": percentile(values, 0.95),
        "p99": percentile(values, 0.99),
        "max": max(values),
        "over_1s": sum(value > 1 for value in values) / len(values),
        "over_2s": sum(value > 2 for value in values) / len(values),
    }


def main():
    original_watermark = vm.get_watermark()
    session = vm.luci.login()
    rows = []
    started = time.monotonic()
    next_snapshot = started + 60
    try:
        vm.set_watermark(WATERMARK)
        vm.snapshot("soak-start")
        while time.monotonic() - started < DURATION:
            if time.monotonic() >= next_snapshot:
                vm.snapshot(f"elapsed-{int(time.monotonic() - started)}")
                next_snapshot += 60
            index = len(rows) + 1
            elapsed = int(time.monotonic() - started)
            row = vm.get_overview(session, f"m{elapsed // 60:02d}", index)
            row["elapsed"] = elapsed
            row["watermark"] = WATERMARK
            rows.append(row)
            if index % 60 == 0:
                print(f"SOAK_PROGRESS seconds={elapsed} requests={index}", flush=True)
    finally:
        vm.set_watermark(original_watermark)
        vm.snapshot(f"soak-restored-{original_watermark}")
        vm.luci.logout(session)

    by_minute = collections.defaultdict(list)
    for row in rows:
        by_minute[row["elapsed"] // 60].append(row)
    summary = {
        "watermark": WATERMARK,
        "duration_seconds": DURATION,
        "overall": summarize(rows),
        "minutes": {str(key): summarize(value) for key, value in by_minute.items()},
        "rows": rows,
    }
    with open(RESULTS, "w") as stream:
        json.dump(summary, stream, indent=2)
    print("SOAK_SUMMARY", json.dumps(summary["overall"], sort_keys=True), flush=True)
    print(f"results={RESULTS}", flush=True)


if __name__ == "__main__":
    main()
