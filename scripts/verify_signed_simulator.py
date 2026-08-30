#!/usr/bin/env python3
"""Opt-in Simulator -> pinned TLS -> disposable signed Agent -> signed Mac XPC.

Local human consent and audio hardware are substituted. Never selects a physical
device, installed Mac product, production Keychain, or privacy settings.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import sqlite3
import subprocess
import time
import uuid

from report_simulator_run import verified_counts
from verify_agent_xpc import Probe, ROOT, source_fingerprint

TEST = "testSignedAgentPairObserveActControlAndClientRestart"
BUNDLE = "dev.maccompanion.clientuiharness"


def fingerprint():
    digest = hashlib.sha256(source_fingerprint().encode())
    paths = [Path(__file__).resolve(), ROOT / "scripts/report_simulator_run.py"]
    for directory in ("Experiments/ClientUIHarness", "Experiments/LiveControlLab/Sources/LiveControlLabSupport"):
        paths.extend(p for p in (ROOT / directory).rglob("*") if p.suffix in {".swift", ".pbxproj", ".xcscheme"})
    for path in sorted(set(paths)):
        digest.update(str(path.relative_to(ROOT)).encode() + b"\0" + path.read_bytes())
    return digest.hexdigest()


def main():
    os.environ.setdefault("DEVELOPER_DIR", "/Applications/Xcode-beta.app/Contents/Developer")
    devices = json.loads(subprocess.run(["xcrun", "simctl", "list", "devices", "booted", "--json"],
        capture_output=True, text=True, check=True, timeout=20).stdout)
    available = [d for runtime, items in devices["devices"].items() if ".iOS-" in runtime
                 for d in items if d["state"] == "Booted"]
    available.sort(key=lambda d: "iPhone" not in d["name"])
    requested = os.environ.get("MACCOMPANION_SIMULATOR_ID")
    if requested:
        available = [d for d in available if d["udid"] == requested]
    if not available:
        raise RuntimeError("A booted iOS Simulator is required; no device will be booted or erased")
    simulator = str(uuid.UUID(available[0]["udid"])).upper()
    captured_source = fingerprint()
    lock = Path(f"/private/tmp/maccompanion-simulator-{simulator}.lock")
    lock.mkdir()  # collision is not permission to remove someone else's lock
    probe = None
    containers = set()
    failure = None
    counts = None
    agent_cleaned = False
    try:
        probe = Probe()
        probe.prepare()
        probe.start_server()
        probe.client("enable", role="bootstrap", marker="enabled-receipt-verified")
        probe.stop_server()
        probe.start_server("productionInteractive")
        process, menu_log = probe.background_client("presentation-simulator")
        probe.wait_marker(menu_log, "signed-simulator-menu-ready")
        fixture = probe.state / "simulator-fixture.json"
        assert json.loads(fixture.read_text())["source"] == "signed-agent"
        derived = Path("/private/tmp/maccompanion-live-lab-build")
        project = ROOT / "Experiments/ClientUIHarness/ClientUIHarness.xcodeproj"
        common = ["-project", project, "-scheme", "ClientUIHarness", "-configuration", "Debug",
                  "-destination", f"platform=iOS Simulator,id={simulator}", "-derivedDataPath", derived,
                  "CODE_SIGNING_ALLOWED=NO"]
        probe.command(["xcodebuild", "build-for-testing", *common], timeout=600, name="simulator-build")
        probe.command(["xcrun", "simctl", "install", simulator,
                       derived / "Build/Products/Debug-iphonesimulator/ClientUIHarness.app"], name="simulator-install")
        container = Path(probe.command(["xcrun", "simctl", "get_app_container", simulator, BUNDLE, "data"], name="simulator-container").strip())
        containers.add(container)
        destination = container / "Documents/lab-fixture.json"
        destination.parent.mkdir(exist_ok=True)
        shutil.copy2(fixture, destination)
        destination.chmod(0o600)
        text = probe.command(["xcodebuild", "test-without-building", *common,
            "-parallel-testing-enabled", "NO", "-only-testing:ClientUIHarnessUITests/SignedAgentJourneyUITests/" + TEST,
            "-resultBundlePath", probe.evidence / "features.xcresult", "-test-timeouts-enabled", "YES",
            "-maximum-test-execution-time-allowance", "180"], timeout=300, name="signed-simulator-tests")
        completion = f"Test Case '-[ClientUIHarnessUITests.SignedAgentJourneyUITests {TEST}]' passed ("
        assert text.count(completion) == 1, "Missing exact XCTest completion"
        summary = json.loads(probe.command(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path",
            probe.evidence / "features.xcresult", "--compact"], name="test-summary"))
        counts, passed = verified_counts(summary, 0)
        assert passed and counts["totalTestCount"] == 1
        for marker in ("signed-simulator-pairing-approved", "signed-simulator-act-granted",
                       "signed-simulator-control-granted", "signed-simulator-control-media-active",
                       "signed-simulator-control-input-observed", "signed-simulator-control-stop-clean"):
            probe.contains(menu_log.read_text(), marker)
        assert "signed-simulator-media-drain-failed" not in menu_log.read_text()
        assert process.poll() is None, "Signed menu exited during the journey"
        with sqlite3.connect(f"file:{probe.state / 'media.jenny.maccompanion/Agent/v1/security-v1.sqlite3'}?mode=ro", uri=True) as store:
            assert set(store.execute("SELECT capability_id FROM device_grants").fetchall()) == {
                ("maccompanion.system.setAudioMuted",), ("maccompanion.interactive.control",)}
            assert store.execute("SELECT state FROM durable_operations").fetchall() == [("succeeded",)]
            assert store.execute("SELECT count(*) FROM device_authorizations").fetchone()[0] == 1
        calls = [s for s in probe.server_log.read_text().splitlines() if s.startswith("isolated-audio-execution:")]
        assert calls == ["isolated-audio-execution:1"]
        assert captured_source == fingerprint(), "Source changed during test"
        probe.stop_server()
    except (Exception, KeyboardInterrupt) as error:
        failure = f"{type(error).__name__}: {error}"
    finally:
        try:
            if containers:
                subprocess.run(["xcrun", "simctl", "terminate", simulator, BUNDLE], capture_output=True, timeout=10)
                current = subprocess.run(["xcrun", "simctl", "get_app_container", simulator, BUNDLE, "data"],
                    capture_output=True, text=True, check=True, timeout=10).stdout.strip()
                containers.add(Path(current))
                for container in containers:
                    assert container.is_absolute() and f"/Devices/{simulator}/data/Containers/Data/Application/" in str(container)
                    (container / "Documents/lab-fixture.json").unlink(missing_ok=True)
                    owned = container / "Documents/journey-tests"
                    if owned.exists():
                        assert owned.is_dir() and not owned.is_symlink()
                        shutil.rmtree(owned)
                    assert not owned.exists()
        except Exception as error:
            failure = f"{failure or ''} Simulator cleanup: {error}"
        # Agent cleanup must run even if Simulator cleanup fails.
        try:
            if probe:
                probe.cleanup()
                agent_cleaned = True
        except Exception as error:
            failure = f"{failure or ''} Agent cleanup: {error}"
        try:
            lock.rmdir()
        except Exception as error:
            failure = f"{failure or ''} Lock cleanup: {error}"
    if probe:
        report = {"schema": 1, "status": "passed" if failure is None else "failed", "failure": failure,
            "sourceSHA256": captured_source, "testID": probe.test_id, "serviceLabel": probe.label,
            "simulatorID": simulator, "tests": counts, "elapsedSeconds": round(time.time() - probe.started, 3),
            "cleanupVerified": agent_cleaned and not probe.state.exists() and not lock.exists()
                and all(not (c / "Documents/lab-fixture.json").exists() and not (c / "Documents/journey-tests").exists() for c in containers),
            "limits": ["Real signed Agent and Mac XPC with loopback TLS and production client workspace",
                "Local Mac consent and hardware custody simulated; audio controller in-memory",
                "Pair/Observe/Act plus Control media, pointer, verified focus, automatic Smart Zoom, composed/direct keyboard, Stop, client-process restart, background/foreground and route-loss recovery; signed Agent-host restart remains separate",
                "No installed Mac product, production Keychain/TCC, LAN, physical iPhone, or publication"]}
        (probe.evidence / "signed-simulator-report.json").write_text(json.dumps(report, indent=2) + "\n")
        print(f"{report['status']}: {probe.evidence / 'signed-simulator-report.json'}", flush=True)
        if failure:
            print(failure, flush=True)
    return 1 if failure else 0


if __name__ == "__main__":
    def interrupted(signum, frame):
        raise KeyboardInterrupt()
    signal.signal(signal.SIGTERM, interrupted)
    raise SystemExit(main())
