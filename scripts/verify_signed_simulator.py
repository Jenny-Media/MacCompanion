#!/usr/bin/env python3
"""Opt-in Simulator -> pinned TLS -> disposable signed Agent -> signed Mac XPC.

Local human consent and audio hardware are substituted. Never selects a physical
device, installed Mac product, production Keychain, or privacy settings.
"""
import argparse
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
    paths = [Path(__file__).resolve(), ROOT / "scripts/report_simulator_run.py",
             ROOT / "scripts/native_agent_probe_support.py"]
    for directory in ("Experiments/ClientUIHarness", "Experiments/LiveControlLab/Sources/LiveControlLabSupport"):
        paths.extend(p for p in (ROOT / directory).rglob("*") if p.suffix in {".swift", ".pbxproj", ".xcscheme"})
    for path in sorted(set(paths)):
        digest.update(str(path.relative_to(ROOT)).encode() + b"\0" + path.read_bytes())
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native-root", type=Path, help="Use the isolated native host and generated native Simulator app")
    parser.add_argument("--native-host-package", type=Path, help="Use a verified portable development host package in the native lane")
    parser.add_argument("--continuous-bootstrap", action="store_true", help="Keep the generated legacy stream running through native Stop")
    parser.add_argument("--native-ipv4-interfaces", action="store_true", help="Test the native host IPv4-interface listener; primary pairing remains isolated loopback")
    args = parser.parse_args()
    native = args.native_root is not None
    if args.native_ipv4_interfaces and not native:
        parser.error("--native-ipv4-interfaces requires --native-root")
    os.environ.pop("MACCOMPANION_NATIVE_LAB_IPV4_INTERFACES", None)
    if args.native_ipv4_interfaces:
        os.environ["MACCOMPANION_NATIVE_LAB_IPV4_INTERFACES"] = "1"
    if args.native_host_package and not native:
        parser.error("--native-host-package requires --native-root")
    portable_manifest_sha = None
    if args.native_host_package:
        from package_rebuilt_source_host import verify_selected as verify
        from package_native_host import digest
        verify(args.native_host_package.resolve())
        portable_manifest_sha = digest(args.native_host_package / "host-package.json")
    if args.continuous_bootstrap and not native:
        parser.error("--continuous-bootstrap requires --native-root")
    test = "testNativeDesktopFrameStopAndRestart" if native else TEST
    test_class = "NativeSignedAgentJourneyUITests" if native else "SignedAgentJourneyUITests"
    test_selection = ("-only-testing:ClientUIHarnessUITests/NativeSignedAgentJourneyUITests/" + test if native
                      else "-only-testing:ClientUIHarnessUITests/SignedAgentJourneyUITests/" + test)
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
    native_source = None
    if native:
        from native_agent_probe_support import digest, native_source_inputs
        native_source = native_source_inputs()[1]
    lock = Path(f"/private/tmp/maccompanion-simulator-{simulator}.lock")
    lock.mkdir()  # collision is not permission to remove someone else's lock
    probe = None
    containers = set()
    failure = None
    counts = None
    agent_cleaned = False
    capture_geometry = []
    try:
        if native:
            from native_agent_probe_support import configure_native_probe, native_simulator_project
            probe, _, _ = configure_native_probe(args.native_root.resolve(), args.native_host_package)
            project, derived = native_simulator_project(probe, args.native_root.resolve())
        else:
            probe = Probe()
            derived = Path("/private/tmp/maccompanion-live-lab-build")
            project = ROOT / "Experiments/ClientUIHarness/ClientUIHarness.xcodeproj"
        probe.prepare()
        probe.start_server()
        probe.client("enable", role="bootstrap", marker="enabled-receipt-verified")
        probe.stop_server()
        probe.start_server("productionInteractive")
        mode = ("presentation-native-simulator-continuous" if args.continuous_bootstrap else "presentation-native-simulator") if native else "presentation-simulator"
        process, menu_log = probe.background_client(mode)
        probe.wait_marker(menu_log, "signed-simulator-menu-ready")
        fixture = probe.state / "simulator-fixture.json"
        assert json.loads(fixture.read_text())["source"] == "signed-agent"
        common = ["-project", project, "-scheme", "ClientUIHarness", "-configuration", "Debug",
                  "-destination", f"platform=iOS Simulator,id={simulator}", "-derivedDataPath", derived,
                  "CODE_SIGNING_ALLOWED=NO"]
        probe.command(["xcodebuild", "build-for-testing", *common], timeout=600, name="simulator-build")
        if native:
            dependencies = derived / "Build/Products/Debug-iphonesimulator/ClientUIHarness.app/Frameworks"
            assert (dependencies / "CompanionMoonlightEngine.framework/CompanionMoonlightEngine").is_file()
            assert (dependencies / "OpenSSL.framework/OpenSSL").is_file(), "Native TLS runtime dependency missing"
        probe.command(["xcrun", "simctl", "install", simulator,
                       derived / "Build/Products/Debug-iphonesimulator/ClientUIHarness.app"], name="simulator-install")
        container = Path(probe.command(["xcrun", "simctl", "get_app_container", simulator, BUNDLE, "data"], name="simulator-container").strip())
        containers.add(container)
        destination = container / "Documents/lab-fixture.json"
        destination.parent.mkdir(exist_ok=True)
        shutil.copy2(fixture, destination)
        destination.chmod(0o600)
        text = probe.command(["xcodebuild", "test-without-building", *common,
            "-parallel-testing-enabled", "NO", test_selection,
            "-collect-test-diagnostics", "never",
            "-resultBundlePath", probe.evidence / "features.xcresult", "-test-timeouts-enabled", "YES",
            "-default-test-execution-time-allowance", "360" if native else "180",
            "-maximum-test-execution-time-allowance", "360" if native else "180"],
            timeout=420 if native else 300, name="signed-simulator-tests")
        completion = f"Test Case '-[ClientUIHarnessUITests.{test_class} {test}]' passed ("
        assert text.count(completion) == 1, "Missing exact XCTest completion"
        summary = json.loads(probe.command(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path",
            probe.evidence / "features.xcresult", "--compact"], name="test-summary"))
        counts, passed = verified_counts(summary, 0)
        assert passed and counts["totalTestCount"] == 1
        for marker in ("signed-simulator-pairing-approved", "signed-simulator-act-granted",
                       "signed-simulator-control-granted", "signed-simulator-control-media-active",
                       "signed-simulator-control-stop-clean"):
            probe.contains(menu_log.read_text(), marker)
        if not native:
            probe.contains(menu_log.read_text(), "signed-simulator-control-input-observed")
        else:
            owned = probe.state / "signed-native-owned"
            deadline = time.monotonic() + 5
            while list(owned.iterdir()) and time.monotonic() < deadline:
                time.sleep(0.05)
            assert not list(owned.iterdir()), "Native private state survived Stop"
            assert menu_log.read_text().count("native-managed-prepare-entered") == 4
            assert menu_log.read_text().count("native-backend-sample-geometry-verified") == 4
            assert menu_log.read_text().count("native-production-desktop-geometry-verified") == 4
            records = re.findall(r"^native-menu-capture-geometry-verified capture=(\d+)x(\d+) logical=(\d+)x(\d+) encoded=(\d+)x(\d+)$", menu_log.read_text(), re.MULTILINE)
            assert len(records) == 4, "Expected a current menu capture-mode measurement for each native cycle"
            for record in records:
                w, h, logical_w, logical_h, encoded_w, encoded_h = map(int, record)
                assert 1 <= w <= 32768 and 1 <= h <= 32768
                assert 1 <= logical_w <= 4294967295 and 1 <= logical_h <= 4294967295
                assert 320 <= encoded_w <= 8192 and 240 <= encoded_h <= 8192
                capture_geometry.append(dict(capturePixelWidth=w, capturePixelHeight=h,
                    logicalWidthPoints=logical_w, logicalHeightPoints=logical_h, encodedWidth=encoded_w, encodedHeight=encoded_h))
        assert "signed-simulator-media-drain-failed" not in menu_log.read_text()
        assert process.poll() is None, "Signed menu exited during the journey"
        with sqlite3.connect(f"file:{probe.state / 'media.jenny.maccompanion/Agent/v1/security-v1.sqlite3'}?mode=ro", uri=True) as store:
            assert set(store.execute("SELECT capability_id FROM device_grants").fetchall()) == {
                ("maccompanion.system.setAudioMuted",), ("maccompanion.interactive.control",)}
            assert store.execute("SELECT state FROM durable_operations").fetchall() == ([] if native else [("succeeded",)])
            assert store.execute("SELECT count(*) FROM device_authorizations").fetchone()[0] == 1
        calls = [s for s in probe.server_log.read_text().splitlines() if s.startswith("isolated-audio-execution:")]
        assert calls == ([] if native else ["isolated-audio-execution:1"])
        assert captured_source == fingerprint(), "Source changed during test"
        if args.native_host_package:
            from package_rebuilt_source_host import verify_selected as verify
            from package_native_host import digest
            verify(args.native_host_package.resolve())
            assert portable_manifest_sha == digest(args.native_host_package / "host-package.json"), "Host package changed during test"
        if native:
            assert native_source == native_source_inputs()[1], "Native candidate source changed during test"
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
            "simulatorID": simulator, "tests": counts, "nativeVideo": native,
            "nativeDecodedPresentation": native and failure is None, "nativeInputAdmitted": native and failure is None, "elapsedSeconds": round(time.time() - probe.started, 3),
            "cleanupVerified": agent_cleaned and not probe.state.exists() and not lock.exists()
                and all(not (c / "Documents/lab-fixture.json").exists() and not (c / "Documents/journey-tests").exists() for c in containers),
            "limits": ["Real signed Agent and Mac XPC with loopback TLS and production client workspace",
                "Local Mac consent and hardware custody simulated; audio controller in-memory",
                "Pair/Observe/Act plus Control media, pointer, verified focus, automatic Smart Zoom, composed/direct keyboard, Stop, client-process restart, background/foreground and route-loss recovery; signed Agent-host restart remains separate",
                "No installed Mac product, production Keychain/TCC, LAN, physical iPhone, or publication"]}
        if native:
            report["nativeListenerScope"] = "ipv4Interfaces" if args.native_ipv4_interfaces else "loopback"
            if args.native_host_package:
                report["portableNativeHostPackageVerified"] = failure is None
                report["portableNativeHostManifestSHA256"] = portable_manifest_sha
            report["nativePresentationReceiptVerified"] = failure is None
            report["nativeHostInputPermitInstalled"] = failure is None
            report["nativeKeyboardAndPointerVerified"] = failure is None
            report["nativeBackgroundAndRouteLossVerified"] = failure is None
            report["nativeBackendSampleGeometryVerified"] = failure is None
            report["nativeCaptureModeGeometryVerified"] = failure is None and len(capture_geometry) == 4
            report["nativeCaptureModeGeometry"] = capture_geometry
            report["nativeSourceInputSHA256"] = native_source
            report["nativeProbeSupportSHA256"] = digest(ROOT / "scripts/native_agent_probe_support.py")
            report["generatedProjectSHA256"] = digest(project.parent / "project.json")
            report["bootstrapSource"] = "continuous generated legacy stream" if args.continuous_bootstrap else "finite generated frames, stopped after exact surface acknowledgement"
            report["limits"] = ["Normal UIKit workspace/Control/native owners through real pairing, primary TLS and signed XPC",
                "Software test key custody/local consent and generated bootstrap/indicator/input effects; managed Sunshine captures the approved display",
                "Four visible native sessions with background revocation, reachability-loss teardown, explicit restart and correlated input admission, pointer, direct iOS keyboard, visible keyboard dismissal, modifier key and shortcut delivery to a synthetic host sink, Stop and fresh restart; same-primary Observe preserved across Stop/background; fresh-primary Observe after route return",
                ("Native host listens on IPv4 interfaces; Simulator uses the isolated loopback primary route. "
                 if args.native_ipv4_interfaces else "Loopback only; ")
                + "No permanent target dependency/TCC admission, installed Mac app, physical iPhone or publication"]
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
