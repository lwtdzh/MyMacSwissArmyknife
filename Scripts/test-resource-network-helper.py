#!/usr/bin/env python3
"""Test the actual helper parser and collector shutdown lifecycle."""

import json
import os
import pathlib
import select
import signal
import subprocess
import tempfile

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
    for mode in ("collector-exit", "helper-exit"):
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
            if mode == "collector-exit":
                os.kill(child, signal.SIGTERM)
            else:
                os.killpg(process.pid, signal.SIGTERM)
            status = process.wait(timeout=4)
            assert status == (1 if mode == "collector-exit" else 0), (mode, status)
            remaining = subprocess.run(
                ["ps", "-p", str(child), "-o", "comm="],
                capture_output=True, text=True)
            assert remaining.returncode != 0, "Collector remained after helper exit."
        finally:
            if child is not None:
                try:
                    os.kill(child, signal.SIGTERM)
                except ProcessLookupError:
                    pass
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=4)
