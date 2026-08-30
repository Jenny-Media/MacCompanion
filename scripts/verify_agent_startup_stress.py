#!/usr/bin/env python3
"""Repeat signed disposable Agent startups to close the pre-entry stall gate."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import signal
import statistics
import sys
import time
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
VERIFY = ROOT / "scripts/verify_agent_xpc.py"
MODES = ("normal", "slow", "productionPrimary", "productionPresentation")
BASE_MARKERS = ("probe-entered", "startup-preparing")
SERVER_MARKERS = {
    "normal": (*BASE_MARKERS, "service-running"),
    "slow": (*BASE_MARKERS, "service-running"),
    "productionPrimary": (*BASE_MARKERS, "service-running"),
    # The presentation owner is intentionally not fully ready until an
    # authenticated menu arrives. Require both the private listener boundary
    # and the complete signed menu cycle before counting the launch.
    "productionPresentation": (
        *BASE_MARKERS,
        "local-xpc-listening",
        "presentation-cycle-complete",
        "service-running",
    ),
}
CLIENT_MARKERS = {
    "normal": (),
    "slow": (),
    "productionPrimary": (),
    "productionPresentation": (
        "presentation-delivery-idempotence-verified",
        "pairing-create-dismiss-retry-verified",
        "grant-without-device-rejected",
        "status-verified",
    ),
}
SETUP_MARKERS = ("enabled-receipt-verified", "restart-requested")


def required_server_markers(mode: str) -> list[str]:
    return list(SERVER_MARKERS[mode])


def required_client_markers(mode: str) -> list[str]:
    return list(CLIENT_MARKERS[mode])


def load_probe_module():
    spec = importlib.util.spec_from_file_location("maccompanion_verify_agent_xpc", VERIFY)
    if spec is None or spec.loader is None:
        raise RuntimeError("Agent/XPC verifier module is unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def percentile95(values: list[float]) -> float:
    if not values:
        raise ValueError("empty duration set")
    ordered = sorted(values)
    return ordered[max(0, math.ceil(len(ordered) * 0.95) - 1)]


def summarize(cycles: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for mode in MODES:
        matching = [cycle for cycle in cycles if cycle["mode"] == mode]
        durations = [float(cycle["startupSeconds"]) for cycle in matching]
        result[mode] = {
            "cycleCount": len(matching),
            "meanStartupSeconds": round(statistics.fmean(durations), 4),
            "p95StartupSeconds": round(percentile95(durations), 4),
            "maximumStartupSeconds": round(max(durations), 4),
        }
    return result


def validate_report(report: dict[str, Any]) -> None:
    required = {
        "schemaVersion": 1,
        "status": "passed",
        "purpose": "signedDisposableAgentStartupStress",
        "modes": list(MODES),
        "cleanupVerified": True,
        "failure": None,
        "physicalDeviceUsed": False,
        "installedProductUsed": False,
        "productionKeychainOrTCCUsed": False,
    }
    for key, expected in required.items():
        if report.get(key) != expected:
            raise ValueError(f"invalid startup-stress report field: {key}")
    iterations = report.get("iterationsPerMode")
    setup = report.get("setup")
    if setup != {
        "purpose": "establishEnabledDurableIntent",
        "markers": list(SETUP_MARKERS),
    }:
        raise ValueError("invalid startup-stress setup evidence")
    cycles = report.get("cycles")
    if not isinstance(iterations, int) or not 1 <= iterations <= 100:
        raise ValueError("invalid startup-stress iteration count")
    if not isinstance(cycles, list) or len(cycles) != iterations * len(MODES):
        raise ValueError("incomplete startup-stress cycle set")
    expected = {(mode, index) for mode in MODES for index in range(1, iterations + 1)}
    actual: set[tuple[str, int]] = set()
    for cycle in cycles:
        if set(cycle) != {
            "mode", "iteration", "startupSeconds", "serverMarkers",
            "clientMarkers", "shutdown",
        }:
            raise ValueError("invalid startup-stress cycle shape")
        key = (cycle["mode"], cycle["iteration"])
        if key in actual or key not in expected:
            raise ValueError("duplicate or unknown startup-stress cycle")
        actual.add(key)
        duration = cycle["startupSeconds"]
        if not isinstance(duration, (int, float)) or isinstance(duration, bool) \
                or not 0 < duration < 10:
            raise ValueError("startup cycle exceeded the unchanged readiness deadline")
        if cycle["serverMarkers"] != required_server_markers(cycle["mode"]):
            raise ValueError("startup cycle did not cross server readiness")
        if cycle["clientMarkers"] != required_client_markers(cycle["mode"]):
            raise ValueError("startup cycle did not cross client readiness")
        if cycle["shutdown"] != "graceful":
            raise ValueError("startup cycle did not shut down gracefully")
    if actual != expected:
        raise ValueError("startup-stress cycles are incomplete")
    expected_summary = summarize(cycles)
    if report.get("summaries") != expected_summary:
        raise ValueError("startup-stress summary does not match cycles")
    for key in ("productSourceSHA256", "stressRunnerSHA256"):
        value = report.get(key)
        if not isinstance(value, str) or len(value) != 64 \
                or any(character not in "0123456789abcdef" for character in value):
            raise ValueError(f"invalid startup-stress hash: {key}")


def self_test() -> None:
    cycles = [
        {"mode": mode, "iteration": 1, "startupSeconds": 0.25,
         "serverMarkers": required_server_markers(mode),
         "clientMarkers": required_client_markers(mode), "shutdown": "graceful"}
        for mode in MODES
    ]
    report = {
        "schemaVersion": 1,
        "status": "passed",
        "purpose": "signedDisposableAgentStartupStress",
        "modes": list(MODES),
        "iterationsPerMode": 1,
        "setup": {
            "purpose": "establishEnabledDurableIntent",
            "markers": list(SETUP_MARKERS),
        },
        "cycles": cycles,
        "summaries": summarize(cycles),
        "cleanupVerified": True,
        "failure": None,
        "physicalDeviceUsed": False,
        "installedProductUsed": False,
        "productionKeychainOrTCCUsed": False,
        "productSourceSHA256": "a" * 64,
        "stressRunnerSHA256": "b" * 64,
    }
    validate_report(report)
    report["cycles"][0]["startupSeconds"] = 10.0
    try:
        validate_report(report)
    except ValueError:
        pass
    else:
        raise AssertionError("deadline-exceeding startup passed")
    print("Agent startup stress reporter self-test passed")


def run(iterations: int) -> tuple[dict[str, Any], Path]:
    module = load_probe_module()
    probe = module.Probe()
    started = time.time()
    cycles: list[dict[str, Any]] = []
    failure: str | None = None
    cleaned = False
    before = module.source_fingerprint()
    try:
        probe.prepare()
        # A shipping presentation launch only occurs after Enable has durably
        # committed. Establish that precondition through the signed bootstrap
        # protocol rather than writing test state directly. Without this step,
        # presentation correctly takes the disabled bootstrap path and the
        # stress runner would report a false startup failure.
        probe.start_server()
        setup_text = probe.command(
            [probe.evidence / "menu", "bootstrap", probe.test_id, "enable"],
            name="startup-stress-enable",
        )
        for marker in SETUP_MARKERS[:1]:
            probe.contains(setup_text, marker)
        probe.wait_marker(probe.server_log, SETUP_MARKERS[1])
        probe.stop_server()
        for iteration in range(1, iterations + 1):
            for mode in MODES:
                cycle_start = time.monotonic()
                probe.start_server(mode)
                client_markers = required_client_markers(mode)
                if mode == "productionPresentation":
                    client_text = probe.command(
                        [probe.evidence / "menu", "client", probe.test_id, "presentation"],
                        name=f"startup-stress-presentation-{iteration}",
                    )
                    for marker in client_markers:
                        probe.contains(client_text, marker)
                    probe.wait_marker(probe.server_log, "presentation-cycle-complete")
                    probe.wait_marker(probe.server_log, "service-running")
                startup_seconds = time.monotonic() - cycle_start
                lines = probe.server_log.read_text().splitlines()
                server_markers = required_server_markers(mode)
                for marker in server_markers:
                    if marker not in lines:
                        raise AssertionError(f"missing {marker} for {mode} cycle {iteration}")
                cycles.append({
                    "mode": mode,
                    "iteration": iteration,
                    "startupSeconds": round(startup_seconds, 4),
                    "serverMarkers": server_markers,
                    "clientMarkers": client_markers,
                    "shutdown": "graceful",
                })
                print(
                    f"PASS startup mode={mode} iteration={iteration} "
                    f"seconds={startup_seconds:.4f}",
                    flush=True,
                )
                probe.stop_server()
        if module.source_fingerprint() != before:
            raise RuntimeError("Agent startup source changed during stress run")
    except (Exception, KeyboardInterrupt) as error:
        failure = f"{type(error).__name__}: {error}"
    finally:
        try:
            probe.cleanup()
            cleaned = True
        except Exception as error:
            failure = f"{failure or ''} Cleanup: {error}"
    report = {
        "schemaVersion": 1,
        "status": "passed" if failure is None and cleaned else "failed",
        "purpose": "signedDisposableAgentStartupStress",
        "modes": list(MODES),
        "iterationsPerMode": iterations,
        "setup": {
            "purpose": "establishEnabledDurableIntent",
            "markers": list(SETUP_MARKERS),
        },
        "cycles": cycles,
        "summaries": summarize(cycles) if all(
            any(cycle["mode"] == mode for cycle in cycles) for mode in MODES
        ) else {},
        "cleanupVerified": cleaned,
        "failure": failure,
        "physicalDeviceUsed": False,
        "installedProductUsed": False,
        "productionKeychainOrTCCUsed": False,
        "productSourceSHA256": before,
        "stressRunnerSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "testID": probe.test_id,
        "serviceLabel": probe.label,
        "startedAtUTC": datetime.fromtimestamp(started, timezone.utc).isoformat().replace("+00:00", "Z"),
        "finishedAtUTC": utc_now(),
        "elapsedSeconds": round(time.time() - started, 3),
        "limits": [
            "Disposable Developer ID signed Debug process and UUID-scoped launchd job",
            "Software test identity and temporary stores; not production Keychain custody",
            "Loopback/local XPC only; no installed app, SMAppService, TCC, LAN, Simulator, or physical iPhone",
            "Presentation cycles require the signed menu handshake and generated review/pairing/status cycle before graceful shutdown",
            "Repeated readiness is reliability evidence, not causal proof of historical host scheduling",
        ],
    }
    (probe.evidence / "startup-stress-report.json").write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n"
    )
    if report["status"] == "passed":
        validate_report(report)
    return report, probe.evidence


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--iterations", type=int, default=25)
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
        return 0
    if not 1 <= arguments.iterations <= 100:
        parser.error("--iterations must be between 1 and 100")
    report, evidence = run(arguments.iterations)
    print(
        f"{report['status'].upper()}: {len(report['cycles'])} startup cycles; "
        f"cleanup={report['cleanupVerified']}; {evidence / 'startup-stress-report.json'}",
        flush=True,
    )
    if report["failure"]:
        print(report["failure"], flush=True)
        return 1
    return 0


if __name__ == "__main__":
    def interrupted(signum, frame):
        raise KeyboardInterrupt()
    signal.signal(signal.SIGTERM, interrupted)
    os.environ.setdefault("DEVELOPER_DIR", "/Applications/Xcode-beta.app/Contents/Developer")
    raise SystemExit(main())
