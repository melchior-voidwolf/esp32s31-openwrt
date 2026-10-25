"""Regenerate linux.size manifest for the flashed kernel Image.
Usage: python3 gen-linux-size.py <Image> <out-linux.size>
Format (see br2-external/board/esp32s31/post-image.sh):
  struct.pack("<III", 0x455A4953, len(data), zlib.crc32(data))
"""
import struct
import sys
import zlib

data = open(sys.argv[1], "rb").read()
manifest = struct.pack("<III", 0x455A4953, len(data), zlib.crc32(data))
open(sys.argv[2], "wb").write(manifest)
print("size=%d crc32=%#010x" % (len(data), zlib.crc32(data)))
