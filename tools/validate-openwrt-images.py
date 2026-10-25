#!/usr/bin/env python3
"""Validate ESP32-S31 OpenWrt kernel/manifest/rootfs flash inputs."""

import argparse
import hashlib
import struct
import zlib
from pathlib import Path

MAGIC = 0x455A4953
LINUX_SIZE = 0x780000
# A separate manifest write erases the final 4 KiB sector of this partition.
KERNEL_SAFE_SIZE = LINUX_SIZE - 0x1000
ROOTFS_SIZE = 0x400000


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_kernel(path, manifest_path):
    data = path.read_bytes()
    size = len(data)
    if not data:
        raise ValueError(f"empty kernel: {path}")
    if size > KERNEL_SAFE_SIZE:
        raise ValueError(
            f"kernel enters manifest sector: {size:#x} > {KERNEL_SAFE_SIZE:#x}"
        )
    manifest = manifest_path.read_bytes()
    if len(manifest) != 12:
        raise ValueError(f"manifest must be 12 bytes, got {len(manifest)}")
    magic, manifest_size, manifest_crc = struct.unpack("<III", manifest)
    crc = zlib.crc32(data) & 0xFFFFFFFF
    if magic != MAGIC:
        raise ValueError(f"bad manifest magic: {magic:#x}")
    if manifest_size != size:
        raise ValueError(f"manifest size {manifest_size:#x} != kernel {size:#x}")
    if manifest_crc != crc:
        raise ValueError(f"manifest crc {manifest_crc:#010x} != kernel {crc:#010x}")
    print(
        f"KERNEL_OK size={size} crc32={crc:#010x} sha256={digest(path)}"
    )
    print(f"MANIFEST_OK magic={magic:#010x} size={size} crc32={crc:#010x}")


def check_rootfs(path):
    data = path.read_bytes()
    if len(data) > ROOTFS_SIZE:
        raise ValueError(f"rootfs too large: {len(data):#x} > {ROOTFS_SIZE:#x}")
    if not data.startswith(b"hsqs"):
        raise ValueError("rootfs lacks little-endian squashfs hsqs magic")
    if len(data) < 0x10004 or len(data) % 0x10000 != 4:
        raise ValueError("rootfs is not 64 KiB aligned plus 4-byte marker")
    if data[-4:] != b"\xde\xad\xc0\xde":
        raise ValueError("rootfs lacks trailing deadc0de marker")
    print(f"ROOTFS_OK size={len(data)} sha256={digest(path)}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--kernel", type=Path)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--rootfs", type=Path)
    args = parser.parse_args()
    if bool(args.kernel) != bool(args.manifest):
        parser.error("--kernel and --manifest must be supplied together")
    if not args.kernel and not args.rootfs:
        parser.error("nothing to validate")
    for path in (args.kernel, args.manifest, args.rootfs):
        if path and not path.is_file():
            parser.error(f"missing input: {path}")
    if args.kernel:
        check_kernel(args.kernel, args.manifest)
    if args.rootfs:
        check_rootfs(args.rootfs)


if __name__ == "__main__":
    main()
