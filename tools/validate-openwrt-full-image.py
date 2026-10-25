#!/usr/bin/env python3
"""Verify a complete 16 MiB OpenWrt image against its exact source components."""

import argparse
from pathlib import Path

FLASH_SIZE = 16 * 1024 * 1024


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", required=True, type=Path)
    parser.add_argument("--build-root", required=True, type=Path)
    parser.add_argument("--linux-repo", required=True, type=Path)
    args = parser.parse_args()
    build = args.build_root
    linux = args.linux_repo
    expected = [
        (0x2000, linux / "build/korvo1/bootloader/bootloader/bootloader.bin"),
        (0x8000, linux / "build/korvo1/bootloader/partition_table/partition-table.bin"),
        (0x20000, linux / "build/korvo1/bootloader/s31-linux-loader.bin"),
        (0x220000, linux / "build/korvo1/opensbi.bin"),
        (0x2A0000, build / "Image-7.3-flash-initramfs"),
        (0xA1FFF4, build / "linux.size"),
        (0xA20000, build / "rootfs.squashfs"),
    ]
    image = args.image.read_bytes()
    if len(image) != FLASH_SIZE:
        raise ValueError(f"full image must be {FLASH_SIZE} bytes, got {len(image)}")
    covered = bytearray(FLASH_SIZE)
    for offset, path in expected:
        data = path.read_bytes()
        end = offset + len(data)
        if end > FLASH_SIZE:
            raise ValueError(f"segment outside flash: {path}")
        if image[offset:end] != data:
            raise ValueError(f"full image segment mismatch at {offset:#x}: {path}")
        covered[offset:end] = b"\x01" * len(data)
        print(f"SEGMENT_OK offset={offset:#x} size={len(data)} file={path.name}")
    for index, value in enumerate(image):
        if not covered[index] and value != 0xFF:
            raise ValueError(f"non-erased byte outside expected segments at {index:#x}")
    print("FULL_IMAGE_OK size=16777216 erased-space=0xff")


if __name__ == "__main__":
    main()
