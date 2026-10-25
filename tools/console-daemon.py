#!/usr/bin/env python3
"""Persistent UART console daemon for the ESP32-S31-Korvo-1 Linux board.

Holds the serial port open forever (so the board is never reset again by
port-open DTR/RTS transitions). Commands are read from the FIFO
/tmp/s31in (one per line, echo or printf into it); everything the board
prints is appended to /tmp/s31out.log.

Start:   nohup python3 console-daemon.py > /tmp/s31-daemon.log 2>&1 &
Send:    echo "your command" > /tmp/s31in
Read:    tail /tmp/s31out.log
"""
import os
import sys
import time

import serial

PORT = sys.argv[1] if len(sys.argv) > 1 else os.environ.get(
    "S31_PORT", "/dev/cu.usbserial-214420")
RUNTIME = os.environ.get("S31_RUNTIME_DIR", "/tmp")
FIFO = os.path.join(RUNTIME, "s31in")
LOG = os.path.join(RUNTIME, "s31out.log")
DAEMON_LOG = os.path.join(RUNTIME, "s31-daemon.log")


def log(msg):
    with open(DAEMON_LOG, "a") as f:
        f.write(time.strftime("[%H:%M:%S] ") + msg + "\n")


def main():
    os.makedirs(RUNTIME, exist_ok=True)
    s = serial.Serial(PORT, 115200, timeout=0.2)
    s.dtr = False
    s.rts = False
    if not os.path.exists(FIFO):
        os.mkfifo(FIFO)
    out = open(LOG, "ab", buffering=0)
    log("daemon up, port held open")
    # O_RDWR: opening read-only would block until a writer attaches, and a
    # read-only fd sees EOF when the writer closes.  Both freeze serial
    # reading while the board keeps printing.  A read-write fd stays open
    # forever; our own writes never come back because srun writers append.
    fifo_fd = os.open(FIFO, os.O_RDWR | os.O_NONBLOCK)
    fifo = os.fdopen(fifo_fd, "rb", buffering=0)
    while True:
        import select

        r, _, _ = select.select([fifo, s], [], [], 0.2)
        if fifo in r:
            data = fifo.read(4096)
            if data:
                s.write(data)
                s.flush()
        if s in r:
            data = s.read(4096)
            if data:
                out.write(data)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        log("daemon died: %r" % e)
        sys.exit(1)
