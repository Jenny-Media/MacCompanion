#!/usr/bin/env python3
"""Capture a bounded, non-physical resource baseline for the Simulator lab."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import selectors
import statistics
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "scripts/verify_simulator_features.sh"
SAMPLE_INTERVAL_SECONDS = 1.0
ALLOWED_CLASSES = {
    "disposableMacHost": ("maccompanion-test-host",),
    "simulatorClient": ("ClientUIHarness.app/ClientUIHarness",),
}


def utc_stamp() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def tested_source_sha256() -> str:
    command = [
        "git", "ls-files", "-co", "--exclude-standard", "--",
        "Packages/MacCompanionKit", "Experiments/ClientUIHarness",
        "Experiments/LiveControlLab", "scripts/verify_simulator_features.sh",
        "scripts/report_simulator_run.py", "scripts/validate_live_control_lab.py",
    ]
    result = subprocess.run(
        command, cwd=ROOT, check=True, capture_output=True, text=True,
    )
    digest = hashlib.sha256()
    paths = sorted({Path(line) for line in result.stdout.splitlines() if line})
    if not paths:
        raise RuntimeError("No performance-test source files were found")
    for relative in paths:
        location = ROOT / relative
        if not location.is_file() or location.is_symlink():
            raise RuntimeError(f"Unsafe performance-test source path: {relative}")
        digest.update(str(relative).encode() + b"\0")
        digest.update(location.read_bytes() + b"\0")
    return digest.hexdigest()


def reporter_sha256() -> str:
    return hashlib.sha256(Path(__file__).read_bytes()).hexdigest()


def process_rows() -> list[dict]:
    result = subprocess.run(
        ["ps", "-axo", "pid=,ppid=,%cpu=,rss=,command="],
        check=True, capture_output=True, text=True,
    )
    rows: list[dict] = []
    for line in result.stdout.splitlines():
        fields = line.strip().split(None, 4)
        if len(fields) != 5:
            continue
        pid, ppid, cpu, rss, command = fields
        process_class = next((
            name for name, needles in ALLOWED_CLASSES.items()
            if all(needle in command for needle in needles)
        ), None)
        if process_class is None:
            continue
        rows.append({
            "class": process_class,
            "pid": int(pid),
            "ppid": int(ppid),
            "cpuPercent": float(cpu),
            "residentKiB": int(rss),
        })
    return rows


def summarize(samples: list[dict], process_class: str) -> dict:
    matching = [item for item in samples if item["class"] == process_class]
    if not matching:
        return {"sampleCount": 0, "distinctProcessCount": 0}
    cpu = [item["cpuPercent"] for item in matching]
    rss = [item["residentKiB"] for item in matching]
    return {
        "sampleCount": len(matching),
        "distinctProcessCount": len({item["pid"] for item in matching}),
        "cpuPercentObservedMean": round(statistics.fmean(cpu), 3),
        "cpuPercentObservedMaximum": round(max(cpu), 3),
        "residentMemoryObservedMaximumMiB": round(max(rss) / 1024, 3),
    }


def validate(report: dict) -> None:
    required = {
        "schemaVersion": 1,
        "environment": "iOS Simulator",
        "source": "generated",
        "physicalDeviceUsed": False,
        "installedMacAppUsed": False,
        "result": "passed",
    }
    for key, expected in required.items():
        if report.get(key) != expected:
            raise ValueError(f"Invalid performance report field: {key}")
    if report.get("budgetsEvaluated") is not False:
        raise ValueError("An undefined performance budget was evaluated")
    if report.get("testReport", {}).get("suite") != "soak":
        raise ValueError("Performance baseline did not use the soak suite")
    if report["testReport"].get("durationSeconds", 0) < 180:
        raise ValueError("Performance baseline did not cover the bounded idle interval")
    observations = report.get("processObservations", {})
    for name in ALLOWED_CLASSES:
        item = observations.get(name)
        if not isinstance(item, dict) or item.get("sampleCount", 0) < 1:
            raise ValueError(f"No samples captured for {name}")


def self_test() -> None:
    samples = [
        {"class": "disposableMacHost", "pid": 1, "cpuPercent": 1.0,
         "residentKiB": 1024},
        {"class": "disposableMacHost", "pid": 1, "cpuPercent": 3.0,
         "residentKiB": 2048},
    ]
    value = summarize(samples, "disposableMacHost")
    assert value == {
        "sampleCount": 2, "distinctProcessCount": 1,
        "cpuPercentObservedMean": 2.0,
        "cpuPercentObservedMaximum": 3.0,
        "residentMemoryObservedMaximumMiB": 2.0,
    }
    print("Pre-physical performance reporter self-test passed")


def run() -> dict:
    started = utc_stamp()
    before = tested_source_sha256()
    environment = os.environ.copy()
    environment.update({
        "MACCOMPANION_LAB_SUITE": "soak",
        "MACCOMPANION_LAB_SOURCE": "generated",
        "MACCOMPANION_LAB_ITERATIONS": "1",
        "MACCOMPANION_DEVELOPER_DIR": environment.get(
            "MACCOMPANION_DEVELOPER_DIR",
            "/Applications/Xcode-beta.app/Contents/Developer",
        ),
    })
    samples: list[dict] = []
    output_lines: list[str] = []
    evidence: Path | None = None
    process = subprocess.Popen(
        ["/bin/bash", str(RUNNER)], cwd=ROOT, env=environment,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        bufsize=1,
    )
    assert process.stdout is not None
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    next_sample = time.monotonic()
    while process.poll() is None:
        for key, _ in selector.select(timeout=0.2):
            line = key.fileobj.readline()
            if line:
                output_lines.append(line)
                print(line, end="", flush=True)
                if line.startswith("Evidence: "):
                    evidence = Path(line.removeprefix("Evidence: ").strip())
        now = time.monotonic()
        if now >= next_sample:
            samples.extend(process_rows())
            next_sample = now + SAMPLE_INTERVAL_SECONDS
    remainder = process.stdout.read()
    if remainder:
        output_lines.append(remainder)
        print(remainder, end="", flush=True)
        for line in remainder.splitlines():
            if line.startswith("Evidence: "):
                evidence = Path(line.removeprefix("Evidence: ").strip())
    exit_code = process.wait()
    if exit_code != 0 or evidence is None:
        raise RuntimeError(f"Simulator resource baseline failed with exit code {exit_code}")
    if tested_source_sha256() != before:
        raise RuntimeError("Runner source changed during performance capture")
    test_report_path = evidence / "report.json"
    test_report = json.loads(test_report_path.read_text())
    report = {
        "schemaVersion": 1,
        "capturedAtUTC": utc_stamp(),
        "startedAtUTC": started,
        "environment": "iOS Simulator",
        "source": "generated",
        "physicalDeviceUsed": False,
        "installedMacAppUsed": False,
        "testedSourceSHA256": before,
        "reporterSHA256": reporter_sha256(),
        "result": "passed" if exit_code == 0 else "failed",
        "budgetsEvaluated": False,
        "budgetStatus": "notDefined",
        "sampleIntervalSeconds": SAMPLE_INTERVAL_SECONDS,
        "processObservations": {
            name: summarize(samples, name) for name in ALLOWED_CLASSES
        },
        "testReport": test_report,
        "limits": [
            "Observed ps snapshots are a Simulator-host baseline, not Instruments energy evidence",
            "CPU values are instantaneous host percentages and are not normalized across devices",
            "No battery, thermal, physical rendering, real-LAN, or radio claim",
            "No pass/fail resource threshold exists until Stage 0A budgets are approved",
        ],
    }
    validate(report)
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    report = run()
    output = args.output
    if output is None:
        directory = Path(tempfile.mkdtemp(prefix="maccompanion-performance-evidence."))
        output = directory / "report.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(f".{output.name}.{os.getpid()}")
    temporary.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    os.chmod(temporary, 0o600)
    os.replace(temporary, output)
    print(f"Performance evidence: {output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"Pre-physical performance capture failed: {error}", file=sys.stderr)
        raise SystemExit(1)
