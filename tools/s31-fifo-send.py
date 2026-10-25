#!/usr/bin/env python3
"""Write one console command without blocking forever on a stale FIFO."""

import errno
import os
import select
import sys
import time


def main():
    if len(sys.argv) not in (3, 4):
        raise SystemExit("usage: s31-fifo-send.py <fifo> <command> [timeout]")
    path, command = sys.argv[1], sys.argv[2]
    timeout = float(sys.argv[3]) if len(sys.argv) == 4 else 5.0
    try:
        fd = os.open(path, os.O_WRONLY | os.O_NONBLOCK)
    except OSError as error:
        if error.errno in (errno.ENXIO, errno.ENOENT):
            print(f"s31-fifo-send: no reader on {path}", file=sys.stderr)
            raise SystemExit(75)
        raise
    payload = memoryview((command + "\n").encode())
    deadline = time.monotonic() + timeout
    try:
        while payload:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                print("s31-fifo-send: write timed out", file=sys.stderr)
                raise SystemExit(75)
            _, writable, _ = select.select([], [fd], [], remaining)
            if not writable:
                continue
            try:
                written = os.write(fd, payload)
            except BlockingIOError:
                continue
            except BrokenPipeError:
                print("s31-fifo-send: reader closed", file=sys.stderr)
                raise SystemExit(75)
            payload = payload[written:]
    finally:
        os.close(fd)


if __name__ == "__main__":
    main()
