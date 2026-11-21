#!/usr/bin/env python3
"""Test delta parsing, collector CPU usage, sampling, and shutdown lifecycle."""

import json
import os
import pathlib
import select
import signal
import subprocess
import tempfile
import time

root = pathlib.Path(__file__).resolve().parent.parent
helper = root / "Upstream/ResourceMonitor/Sources/NetSpeedHelper/main.swift"
fixtures = root / "Upstream/ResourceMonitor/Tests/NetworkDeltaParserTests.swift"
definitions, marker, _ = helper.read_text().partition("_ = setpgid(0, 0)")
if not marker:
    raise SystemExit("Cannot locate helper startup; refusing to run partial tests.")

with tempfile.TemporaryDirectory(prefix="resource-network-tests-") as directory:
    work = pathlib.Path(directory)
    source = work / "main.swift"
    source.write_text(definitions + "\n" + fixtures.read_text())
    binary = work / "NetworkDeltaParserTests"
    subprocess.run(["xcrun", "swiftc", "-framework", "IOKit",
                    str(source), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

    runtime = work / "NetSpeedHelper"
    subprocess.run(["xcrun", "swiftc", "-framework", "IOKit",
                    str(helper), "-o", str(runtime)], check=True)
    for mode in ("idle-cpu", "collector-exit", "helper-exit", "output-closed"):
        process = subprocess.Popen(
            [str(runtime), "--interval", "1"], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, start_new_session=True)
        child = None
        try:
            ready, _, _ = select.select([process.stdout], [], [], 5)
            assert ready, "Helper did not emit a sample."
            json.loads(process.stdout.readline())
            children = subprocess.check_output(
                ["pgrep", "-P", str(process.pid)], text=True).split()
            assert len(children) == 1, children
            child = int(children[0])
            command = subprocess.check_output(
                ["ps", "-p", str(child), "-o", "comm="], text=True).strip()
            assert command == "/usr/bin/nettop", command
            if mode == "idle-cpu":
                def cpu_seconds():
                    value = subprocess.check_output(
                        ["ps", "-p", str(child), "-o", "time="], text=True).strip()
                    return sum(float(part) * 60 ** index
                               for index, part in enumerate(reversed(value.split(":"))))

                started = time.monotonic()
                initial_cpu = cpu_seconds()
                samples = []
                for _ in range(5):
                    ready, _, _ = select.select([process.stdout], [], [], 3)
                    assert ready, "Network collector stopped producing samples."
                    sample = json.loads(process.stdout.readline())
                    for field in ("downloadBytesPerSecond", "uploadBytesPerSecond",
                                  "diskReadBytesPerSecond", "diskWriteBytesPerSecond",
                                  "cpuUsagePercent", "memoryUsagePercent"):
                        assert isinstance(sample[field], int) and sample[field] >= 0, sample
                    assert sample["cpuUsagePercent"] <= 100, sample
                    assert sample["memoryUsagePercent"] <= 100, sample
                    samples.append(sample)
                elapsed = time.monotonic() - started
                cpu_used = cpu_seconds() - initial_cpu
                # Allow ample headroom for a busy host while detecting the
                # /dev/null EOF loop, which consumes more than one CPU core.
                assert cpu_used < elapsed * 0.30, (
                    f"nettop consumed {cpu_used:.2f}s CPU in {elapsed:.2f}s; "
                    "check that stdin has an open, idle writer.")
                assert 3.5 <= elapsed <= 8, f"Unexpected one-second cadence: {elapsed:.2f}s"
                print(f"Collector CPU: {cpu_used / elapsed * 100:.2f}%; "
                      f"{len(samples)} valid samples in {elapsed:.2f}s")
            if mode == "collector-exit":
                os.kill(child, signal.SIGTERM)
            elif mode == "output-closed":
                # An exiting/crashed GUI or XCTest host closes its read end
                # without necessarily sending SIGTERM to the helper.
                process.stdout.close()
            else:
                os.killpg(process.pid, signal.SIGTERM)
            status = process.wait(timeout=4)
            assert status == (1 if mode in ("collector-exit", "output-closed") else 0), (mode, status)
            remaining = subprocess.run(
                ["ps", "-p", str(child), "-o", "comm="],
                capture_output=True, text=True)
            assert remaining.returncode != 0, "Collector remained after helper exit."
            print(f"{mode}: passed")
        finally:
            if child is not None:
                try:
                    os.kill(child, signal.SIGTERM)
                except ProcessLookupError:
                    pass
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=4)
