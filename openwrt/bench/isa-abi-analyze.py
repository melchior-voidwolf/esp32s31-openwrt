#!/usr/bin/env python3
"""Aggregate S31 ABI/ISA benchmark output and check checksum consistency."""

import argparse
import collections
import json
import re
import statistics

RESULT = re.compile(
    r"RESULT mode=(\S+) iterations=(\d+) seconds=(\d+\.\d+) checksum=([0-9a-f]+)"
)
VARIANT = re.compile(r"VARIANT=(\S+) ROUND=(\d+)")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("log")
    parser.add_argument("--json")
    args = parser.parse_args()
    samples = collections.defaultdict(list)
    checksums = collections.defaultdict(set)
    variant = None
    with open(args.log, errors="replace") as stream:
        for line in stream:
            match = VARIANT.search(line)
            if match:
                variant = match.group(1)
                continue
            match = RESULT.search(line)
            if match and variant:
                mode, iterations, seconds, checksum = match.groups()
                samples[(mode, variant)].append(float(seconds))
                checksums[mode].add(checksum)

    modes = ["float", "abi-call", "sqrt", "double", "bits", "zba", "int-control"]
    variants = ["soft-base", "hard-base", "soft-full", "hard-full"]
    summary = {"modes": {}, "speedups": {}, "speedups_min": {}, "checksums_ok": True}
    for mode in modes:
        if not any((mode, variant) in samples for variant in variants):
            continue
        summary["modes"][mode] = {}
        print(f"\n[{mode}]")
        if len(checksums[mode]) == 1:
            print(f"CHECKSUM_OK {next(iter(checksums[mode]))}")
        else:
            summary["checksums_ok"] = False
            print(f"CHECKSUM_MISMATCH {sorted(checksums[mode])}")
        for variant in variants:
            values = samples.get((mode, variant), [])
            if not values:
                print(f"{variant:12s} MISSING")
                continue
            row = {
                "n": len(values),
                "median": statistics.median(values),
                "min": min(values),
                "max": max(values),
                "samples": values,
            }
            summary["modes"][mode][variant] = row
            print(
                f"{variant:12s} n={len(values)} median={row['median']:.6f}s "
                f"min={row['min']:.6f}s max={row['max']:.6f}s"
            )
        comparisons = [
            ("ABI base: soft-base / hard-base", "soft-base", "hard-base"),
            ("ABI full: soft-full / hard-full", "soft-full", "hard-full"),
            ("ISA soft: soft-base / soft-full", "soft-base", "soft-full"),
            ("ISA hard: hard-base / hard-full", "hard-base", "hard-full"),
        ]
        summary["speedups"][mode] = {}
        summary["speedups_min"][mode] = {}
        for label, baseline, optimized in comparisons:
            if baseline not in summary["modes"][mode] or optimized not in summary["modes"][mode]:
                continue
            speedup = (
                summary["modes"][mode][baseline]["median"]
                / summary["modes"][mode][optimized]["median"]
            )
            speedup_min = (
                summary["modes"][mode][baseline]["min"]
                / summary["modes"][mode][optimized]["min"]
            )
            summary["speedups"][mode][label] = speedup
            summary["speedups_min"][mode][label] = speedup_min
            print(f"SPEEDUP {speedup:7.3f}x  {label}")
            print(f"BEST_RATIO {speedup_min:7.3f}x  {label}")

    if args.json:
        with open(args.json, "w") as stream:
            json.dump(summary, stream, indent=2)
        print(f"\nJSON={args.json}")


if __name__ == "__main__":
    main()
