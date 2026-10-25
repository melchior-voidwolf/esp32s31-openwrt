#!/usr/bin/env python3
"""Host-only tests for shared console, leases and bounded FIFO I/O."""

import os
from pathlib import Path
import runpy
import select
import subprocess
import sys
import tempfile
import threading
import time
import types

ROOT = Path(__file__).resolve().parent.parent
SRUN = ROOT / "tools" / "srun.sh"
SWAIT = ROOT / "tools" / "srun-wait.sh"
EXCLUSIVE = ROOT / "tools" / "s31-exclusive.sh"


def environment(runtime, session):
    env = os.environ.copy()
    env["S31_RUNTIME_DIR"] = str(runtime)
    env["S31_SESSION"] = session
    env["S31_LOCK_TIMEOUT"] = "1"
    env["S31_SEND_TIMEOUT"] = "0.3"
    return env


def run_srun(runtime, session, command, wait="0.15", completion=False, timeout=6):
    script = SWAIT if completion else SRUN
    return subprocess.run(
        ["bash", str(script), command, wait],
        env=environment(runtime, session), text=True,
        capture_output=True, timeout=timeout, check=False,
    )


def fake_daemon(runtime, stop, log_lock):
    fifo = runtime / "s31in"
    log = runtime / "s31out.log"
    fd = os.open(fifo, os.O_RDWR | os.O_NONBLOCK)
    pending = b""

    def append(data):
        with log_lock, log.open("ab", buffering=0) as output:
            output.write(data)

    try:
        while not stop.is_set():
            readable, _, _ = select.select([fd], [], [], 0.1)
            if not readable:
                continue
            data = os.read(fd, 4096)
            if not data:
                continue
            pending += data
            lines = pending.split(b"\n")
            pending = lines.pop()
            for raw in lines:
                if not raw:
                    continue
                append(b"FAKE_RESPONSE " + raw + b"\n")
                text = raw.decode(errors="replace")
                if "printf WINDOW_TEST" in text:
                    timer = threading.Timer(.5, lambda: append(b"LATE_OUTPUT\n"))
                    timer.start()
                prefix = "printf '\\n"
                if prefix in text and "NEVER_DONE" not in text:
                    marker = text.split(prefix, 1)[1].split(":%s\\n", 1)[0]
                    rc = b"1" if text.startswith("false") else b"0"
                    append(b"\n" + marker.encode() + b":" + rc + b"\n")
    finally:
        os.close(fd)


def hold_mode():
    time.sleep(1.5)
    return 0


def nested_concurrent_mode(runtime):
    first = subprocess.Popen(
        ["bash", str(SWAIT), "printf NESTED_A", "2"],
        env=environment(runtime, "nested-a"), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    second = subprocess.Popen(
        ["bash", str(SWAIT), "printf NESTED_B", "2"],
        env=environment(runtime, "nested-b"), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out1, err1 = first.communicate(timeout=6)
    out2, err2 = second.communicate(timeout=6)
    if first.returncode or second.returncode:
        print(out1, err1, out2, err2, file=sys.stderr)
        return 1
    if "NESTED_A" not in out1 or "NESTED_B" in out1:
        return 1
    if "NESTED_B" not in out2 or "NESTED_A" in out2:
        return 1
    return 0


def spawn_late_mode():
    subprocess.Popen([sys.executable, "-I", __file__, "--late-srun"],
                     env=os.environ.copy(), stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, close_fds=False)
    return 0


def late_srun_mode(runtime):
    time.sleep(.8)
    result = run_srun(runtime, "late-owner", "printf STALE_OK", "0.1")
    (runtime / "late-result.txt").write_text(str(result.returncode))
    return 0


def main():
    if len(sys.argv) > 1:
        mode = sys.argv[1]
        runtime = Path(os.environ.get("S31_RUNTIME_DIR", "/tmp"))
        if mode == "--hold":
            return hold_mode()
        if mode == "--nested-concurrent":
            return nested_concurrent_mode(runtime)
        if mode == "--spawn-late":
            return spawn_late_mode()
        if mode == "--late-srun":
            return late_srun_mode(runtime)
        if mode == "--fail":
            return 7
        raise SystemExit("unknown test mode")

    with tempfile.TemporaryDirectory(prefix="s31-serial-test-") as tmp:
        runtime = Path(tmp)
        os.mkfifo(runtime / "s31in")
        (runtime / "s31out.log").touch()
        stop = threading.Event()
        log_lock = threading.Lock()
        daemon = threading.Thread(target=fake_daemon, args=(runtime, stop, log_lock), daemon=True)
        daemon.start()
        time.sleep(.1)
        try:
            first = subprocess.Popen(
                ["bash", str(SRUN), "printf LINUX_OK", "0.2"],
                env=environment(runtime, "linux-flash"), text=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            second = subprocess.Popen(
                ["bash", str(SRUN), "printf OPENWRT_OK", "0.2"],
                env=environment(runtime, "openwrt"), text=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            out1, err1 = first.communicate(timeout=6)
            out2, err2 = second.communicate(timeout=6)
            assert first.returncode == 0, err1
            assert second.returncode == 0, err2
            assert "LINUX_OK" in out1 and "OPENWRT_OK" not in out1, (out1, out2)
            assert "OPENWRT_OK" in out2 and "LINUX_OK" not in out2, (out1, out2)

            complete = run_srun(runtime, "linux-flash", "printf COMPLETE_OK", "2", True)
            assert complete.returncode == 0, (complete.stdout, complete.stderr)
            assert "COMPLETE_OK" in complete.stdout
            failed = run_srun(runtime, "linux-flash", "false", "2", True)
            assert failed.returncode == 1, (failed.returncode, failed.stdout)
            timed_out = run_srun(runtime, "linux-flash", "printf NEVER_DONE", "1", True)
            assert timed_out.returncode == 124, timed_out.returncode

            window = run_srun(runtime, "linux-flash", "printf WINDOW_TEST", "0.1")
            assert window.returncode == 0
            assert "WINDOW_TEST" in window.stdout and "LATE_OUTPUT" not in window.stdout
            time.sleep(.7)

            with tempfile.TemporaryDirectory(prefix="s31-no-reader-") as empty:
                empty_runtime = Path(empty)
                os.mkfifo(empty_runtime / "s31in")
                (empty_runtime / "s31out.log").touch()
                started = time.monotonic()
                no_reader = run_srun(empty_runtime, "linux-flash", "printf NO_READER", "0.1", timeout=3)
                assert time.monotonic() - started < 2
                assert no_reader.returncode == 75, (no_reader.returncode, no_reader.stderr)

            env = environment(runtime, "linux-flash")
            env["S31_REASON"] = "host lock test"
            exclusive = subprocess.Popen(
                ["bash", str(EXCLUSIVE), sys.executable, "-I", __file__, "--hold"],
                env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            for _ in range(50):
                if (runtime / "s31-exclusive.owner").exists():
                    break
                time.sleep(.05)
            else:
                raise AssertionError("exclusive owner was not registered")
            blocked_env = environment(runtime, "openwrt")
            blocked_env["S31_LOCK_TIMEOUT"] = "0.2"
            blocked = subprocess.run(
                ["bash", str(SRUN), "printf SHOULD_NOT_RUN", "0.1"],
                env=blocked_env, text=True, capture_output=True, timeout=3, check=False)
            assert blocked.returncode == 75, (blocked.returncode, blocked.stderr)
            assert "SHOULD_NOT_RUN" not in (runtime / "s31out.log").read_text()
            assert exclusive.wait(timeout=6) == 0

            nested = subprocess.run(
                ["bash", str(EXCLUSIVE), sys.executable, "-I", __file__, "--nested-concurrent"],
                env=env, text=True, capture_output=True, timeout=8, check=False)
            assert nested.returncode == 0, (nested.stdout, nested.stderr)

            late = subprocess.run(
                ["bash", str(EXCLUSIVE), sys.executable, "-I", __file__, "--spawn-late"],
                env=env, text=True, capture_output=True, timeout=5, check=False)
            assert late.returncode == 0
            contending_env = environment(runtime, "openwrt")
            contending_env["S31_LOCK_TIMEOUT"] = "0.2"
            contending = subprocess.run(
                ["bash", str(EXCLUSIVE), sys.executable, "-I", __file__, "--hold"],
                env=contending_env, text=True, capture_output=True, timeout=3, check=False)
            assert contending.returncode == 75, (
                "late child did not keep the board lease", contending.stdout, contending.stderr)
            for _ in range(60):
                if (runtime / "late-result.txt").exists():
                    break
                time.sleep(.05)
            else:
                raise AssertionError("late child did not finish")
            assert (runtime / "late-result.txt").read_text() == "75"
            assert "STALE_OK" not in (runtime / "s31out.log").read_text()

            failed = subprocess.run(
                ["bash", str(EXCLUSIVE), sys.executable, "-I", __file__, "--fail"],
                env=env, text=True, capture_output=True, timeout=5, check=False)
            assert failed.returncode == 7
            after = run_srun(runtime, "openwrt", "printf AFTER_OK")
            assert after.returncode == 0 and "AFTER_OK" in after.stdout

            requests = (runtime / "s31-requests.log").read_text()
            assert "exclusive-start" in requests and "exclusive-end" in requests
            for secret in ("LINUX_OK", "OPENWRT_OK", "SHOULD_NOT_RUN", "NESTED_A", "STALE_OK"):
                assert secret not in requests

            custom = runtime / "custom-runtime"
            old_runtime = os.environ.get("S31_RUNTIME_DIR")
            os.environ["S31_RUNTIME_DIR"] = str(custom)
            try:
                previous_serial = sys.modules.get("serial")
                sys.modules["serial"] = types.ModuleType("serial")
                globals_for_test = runpy.run_path(str(ROOT / "tools" / "console-daemon.py"),
                                                  run_name="s31_uartd_test")
                assert globals_for_test["FIFO"] == str(custom / "s31in")
                assert globals_for_test["LOG"] == str(custom / "s31out.log")
                assert globals_for_test["DAEMON_LOG"] == str(custom / "s31-daemon.log")
            finally:
                if previous_serial is None:
                    sys.modules.pop("serial", None)
                else:
                    sys.modules["serial"] = previous_serial
                if old_runtime is None:
                    del os.environ["S31_RUNTIME_DIR"]
                else:
                    os.environ["S31_RUNTIME_DIR"] = old_runtime
        finally:
            stop.set()
            daemon.join(timeout=3)

    print("SERIAL_SHARING_TEST_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
