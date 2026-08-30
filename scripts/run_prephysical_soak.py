#!/usr/bin/env python3
"""Run and record one bounded, source-bound pre-physical Simulator soak day."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LEDGER = ROOT / "docs/evidence/prephysical-soak-ledger.json"
REQUIRED_DATES = 7
MINIMUM_SPAN_SECONDS = 6 * 24 * 60 * 60
MINIMUM_RUN_SECONDS = 180


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def source_fingerprint() -> str:
    command = [
        "git", "ls-files", "-co", "--exclude-standard", "--",
        "Packages/MacCompanionKit", "Experiments/ClientUIHarness",
        "Experiments/LiveControlLab", "scripts/verify_simulator_features.sh",
        "scripts/report_simulator_run.py", "scripts/validate_live_control_lab.py",
    ]
    result = subprocess.run(
        command, cwd=ROOT, check=True, capture_output=True, text=True,
    )
    paths = sorted({Path(line) for line in result.stdout.splitlines() if line})
    if not paths:
        raise RuntimeError("No soak source files were found")
    digest = hashlib.sha256()
    for relative in paths:
        location = ROOT / relative
        if not location.is_file() or location.is_symlink():
            raise RuntimeError(f"Unsafe soak source path: {relative}")
        digest.update(str(relative).encode() + b"\0" + location.read_bytes() + b"\0")
    return digest.hexdigest()


def validate_report(report: dict) -> None:
    tests = report.get("tests") or {}
    expected = {
        "schemaVersion": 1,
        "suite": "soak",
        "source": "generated",
        "environment": "iOS Simulator",
        "physicalDeviceUsed": False,
        "installedMacAppUsed": False,
        "exitCode": 0,
        "iterations": 1,
        "result": "passed",
        "completedExecutions": 1,
    }
    for key, value in expected.items():
        if report.get(key) != value:
            raise ValueError(f"Invalid soak report field: {key}")
    expected_tests = {
        "totalTestCount": 1, "passedTests": 1, "failedTests": 0,
        "skippedTests": 0, "expectedFailures": 0,
    }
    if tests != expected_tests:
        raise ValueError("Invalid soak test counts")
    duration = report.get("durationSeconds")
    if not isinstance(duration, (int, float)) or isinstance(duration, bool) \
            or duration < MINIMUM_RUN_SECONDS:
        raise ValueError("Soak did not retain the required real elapsed interval")


def empty_ledger() -> dict:
    return {
        "schemaVersion": 1,
        "requiredDistinctUTCDates": REQUIRED_DATES,
        "minimumCampaignSpanSeconds": MINIMUM_SPAN_SECONDS,
        "campaigns": [],
    }


def load_ledger(path: Path) -> dict:
    if not path.exists():
        return empty_ledger()
    if path.is_symlink() or not path.is_file():
        raise ValueError("Unsafe soak ledger path")
    value = json.loads(path.read_text())
    if value.get("schemaVersion") != 1 \
            or value.get("requiredDistinctUTCDates") != REQUIRED_DATES \
            or value.get("minimumCampaignSpanSeconds") != MINIMUM_SPAN_SECONDS \
            or not isinstance(value.get("campaigns"), list):
        raise ValueError("Invalid soak ledger")
    return value


def campaign_status(runs: list[dict]) -> dict:
    ordered = sorted(runs, key=lambda item: item["finishedAtUTC"])
    distinct = len({item["utcDate"] for item in ordered})
    if len(ordered) < 2:
        span = 0
    else:
        first = datetime.fromisoformat(ordered[0]["finishedAtUTC"].replace("Z", "+00:00"))
        last = datetime.fromisoformat(ordered[-1]["finishedAtUTC"].replace("Z", "+00:00"))
        span = int((last - first).total_seconds())
    return {
        "distinctUTCDates": distinct,
        "elapsedSpanSeconds": span,
        "complete": distinct >= REQUIRED_DATES and span >= MINIMUM_SPAN_SECONDS,
    }


def atomic_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w") as stream:
            json.dump(value, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def record(
    ledger_path: Path, report_path: Path, fingerprint: str,
    started: datetime, finished: datetime,
) -> dict:
    report = json.loads(report_path.read_text())
    validate_report(report)
    ledger = load_ledger(ledger_path)
    campaigns = ledger["campaigns"]
    campaign = next(
        (item for item in campaigns if item.get("sourceSHA256") == fingerprint),
        None,
    )
    if campaign is None:
        campaign = {"sourceSHA256": fingerprint, "runs": []}
        campaigns.append(campaign)
    runs = campaign.get("runs")
    if not isinstance(runs, list):
        raise ValueError("Invalid soak campaign")
    date = finished.date().isoformat()
    existing = next((item for item in runs if item.get("utcDate") == date), None)
    if existing is not None:
        campaign["status"] = campaign_status(runs)
        return {"alreadyRecorded": True, "campaign": campaign}

    report_bytes = report_path.read_bytes()
    report_hash = hashlib.sha256(report_bytes).hexdigest()
    safe_stamp = finished.strftime("%Y-%m-%dT%H-%M-%SZ")
    retained_relative = Path("docs/evidence/soak-runs") \
        / f"{safe_stamp}-{fingerprint[:12]}.json"
    retained = ROOT / retained_relative
    retained.parent.mkdir(parents=True, exist_ok=True)
    if retained.exists():
        raise FileExistsError(f"Refusing to replace retained soak report: {retained}")
    shutil.copyfile(report_path, retained)
    os.chmod(retained, 0o600)
    if hashlib.sha256(retained.read_bytes()).hexdigest() != report_hash:
        retained.unlink()
        raise RuntimeError("Retained soak report hash mismatch")
    runs.append({
        "utcDate": date,
        "startedAtUTC": started.isoformat().replace("+00:00", "Z"),
        "finishedAtUTC": finished.isoformat().replace("+00:00", "Z"),
        "sourceSHA256": fingerprint,
        "report": str(retained_relative),
        "reportSHA256": report_hash,
        "durationSeconds": report["durationSeconds"],
        "cleanupVerifiedByRunnerExit": True,
    })
    runs.sort(key=lambda item: item["finishedAtUTC"])
    campaign["status"] = campaign_status(runs)
    atomic_json(ledger_path, ledger)
    return {"alreadyRecorded": False, "campaign": campaign}


def run_soak() -> tuple[Path, datetime, datetime, str]:
    before = source_fingerprint()
    started = utc_now()
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
    process = subprocess.Popen(
        ["/bin/bash", "scripts/verify_simulator_features.sh"], cwd=ROOT,
        env=environment, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    evidence = None
    assert process.stdout is not None
    for line in process.stdout:
        print(line, end="", flush=True)
        if line.startswith("Evidence: "):
            evidence = Path(line.removeprefix("Evidence: ").strip())
    result = process.wait()
    finished = utc_now()
    if result != 0 or evidence is None:
        raise RuntimeError(f"Simulator soak failed with exit code {result}")
    after = source_fingerprint()
    if before != after:
        raise RuntimeError("Source changed during the soak")
    report = evidence / "report.json"
    if not report.is_file() or report.is_symlink():
        raise RuntimeError("Simulator soak report is unavailable")
    return report, started, finished, before


def self_test() -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        ledger = root / "ledger.json"
        report = root / "report.json"
        report.write_text(json.dumps({
            "schemaVersion": 1, "suite": "soak", "source": "generated",
            "environment": "iOS Simulator", "physicalDeviceUsed": False,
            "installedMacAppUsed": False, "exitCode": 0, "iterations": 1,
            "result": "passed", "completedExecutions": 1,
            "tests": {"totalTestCount": 1, "passedTests": 1,
                      "failedTests": 0, "skippedTests": 0,
                      "expectedFailures": 0},
            "durationSeconds": 194.0,
        }))
        # Keep retained synthetic reports under the repository out of the unit
        # exercise: validate campaign arithmetic directly instead of record().
        runs = []
        for index in range(7):
            runs.append({
                "utcDate": f"2026-09-{index + 1:02d}",
                "finishedAtUTC": f"2026-09-{index + 1:02d}T12:00:00Z",
            })
        assert campaign_status(runs)["complete"]
        assert not campaign_status(runs[:6])["complete"]
        validate_report(json.loads(report.read_text()))
        invalid = json.loads(report.read_text())
        invalid["physicalDeviceUsed"] = True
        try:
            validate_report(invalid)
        except ValueError:
            pass
        else:
            raise AssertionError("Physical-device soak report was accepted")
        assert load_ledger(ledger) == empty_ledger()
    print("Pre-physical soak ledger self-test passed")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ledger", type=Path, default=DEFAULT_LEDGER)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    ledger = args.ledger.resolve()
    allowed = (ROOT / "docs/evidence").resolve()
    if ledger != allowed / "prephysical-soak-ledger.json":
        raise ValueError("Only the repository pre-physical soak ledger is allowed")
    report, started, finished, fingerprint = run_soak()
    result = record(ledger, report, fingerprint, started, finished)
    status = result["campaign"]["status"]
    print(json.dumps({
        "alreadyRecorded": result["alreadyRecorded"],
        "sourceSHA256": fingerprint,
        "distinctUTCDates": status["distinctUTCDates"],
        "elapsedSpanSeconds": status["elapsedSpanSeconds"],
        "complete": status["complete"],
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"Pre-physical soak failed: {error}", file=sys.stderr)
        raise SystemExit(1)
