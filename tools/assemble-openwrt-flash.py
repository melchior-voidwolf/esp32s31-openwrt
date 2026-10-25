#!/usr/bin/env python3
"""Assemble a 16 MiB, 0xff-filled ESP32-S31 flash image."""

import os
import sys
from pathlib import Path

FLASH_SIZE = 16 * 1024 * 1024


def main():
    if len(sys.argv) < 4 or len(sys.argv[2:]) % 2:
        raise SystemExit(
            f"usage: {sys.argv[0]} OUTPUT OFFSET FILE [OFFSET FILE ...]"
        )
    output = Path(sys.argv[1])
    segments = []
    for offset_text, file_text in zip(sys.argv[2::2], sys.argv[3::2]):
        offset = int(offset_text, 0)
        path = Path(file_text)
        data = path.read_bytes()
        end = offset + len(data)
        if offset < 0 or end > FLASH_SIZE:
            raise ValueError(f"segment outside 16 MiB flash: {path} {offset:#x}+{len(data):#x}")
        segments.append((offset, end, path, data))
    segments.sort(key=lambda item: item[0])
    for previous, current in zip(segments, segments[1:]):
        if current[0] < previous[1]:
            raise ValueError(f"overlapping segments: {previous[2]} and {current[2]}")

    image = bytearray(b"\xff") * FLASH_SIZE
    for offset, end, path, data in segments:
        image[offset:end] = data
        print(f"  @{offset:#010x} {path.name} ({len(data)} B)")

    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(output.name + ".tmp")
    with temporary.open("wb") as stream:
        stream.write(image)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, output)
    if output.read_bytes() != image:
        raise IOError(f"read-back verification failed: {output}")
    print("ASSEMBLE_VERIFY_OK")


if __name__ == "__main__":
    main()
