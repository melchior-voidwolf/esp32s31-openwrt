import json
import re
import sys

RESULTS = sys.argv[1] if len(sys.argv) > 1 else "/tmp/luci-vm-abba-run1.json"
SNAPSHOTS = sys.argv[2] if len(sys.argv) > 2 else "/tmp/luci-vm-abba-run1-snapshots.log"

with open(RESULTS) as stream:
    results = json.load(stream)
with open(SNAPSHOTS, errors="replace") as stream:
    text = stream.read()

snapshots = {}
for match in re.finditer(r"^=== ([^\r\n]+) ===\r?\n(.*?)(?=^=== |\Z)", text, re.M | re.S):
    label, body = match.groups()
    def field(name):
        found = re.search(rf"{name}:\s+(\d+) kB", body)
        return int(found.group(1)) if found else None
    numeric_lines = []
    for line in body.splitlines():
        fields = line.split()
        if len(fields) >= 8 and all(field.isdigit() for field in fields):
            numeric_lines.append([int(field) for field in fields])
    snapshots[label] = {
        "available": field("MemAvailable"),
        "swapfree": field("SwapFree"),
        "zram": numeric_lines[0] if numeric_lines else [],
        "mtd": numeric_lines[1] if len(numeric_lines) > 1 else [],
    }

for block in ["warmup", "A1", "B1", "B2", "A2", "B3", "A3", "A4", "B4"]:
    watermark = next(row["watermark"] for row in results["rows"] if row["block"] == block)
    before = snapshots.get(f"{block}-before-{watermark}", {})
    after = snapshots.get(f"{block}-after-{watermark}", {})
    if not before or not after:
        continue
    bz, az = before["zram"], after["zram"]
    bm, am = before["mtd"], after["mtd"]
    def delta(after_values, before_values, index):
        if len(after_values) <= index or len(before_values) <= index:
            return None
        return after_values[index] - before_values[index]
    read_ops = delta(am, bm, 0)
    read_sectors = delta(am, bm, 2)
    read_ms = delta(am, bm, 3)
    zram_delta = delta(az, bz, 2)
    stats = results["blocks"].get(block, {})
    print(
        f"{block:6s} p50={stats.get('p50', 0):.3f}s tail1s={stats.get('over_1s', 0):.2f} "
        f"avail={before['available']}->{after['available']}K "
        f"swapfree={before['swapfree']}->{after['swapfree']}K "
        f"zram_mem_delta={zram_delta}B mtd_ops+={read_ops} "
        f"sectors+={read_sectors} read_ms+={read_ms}"
    )
