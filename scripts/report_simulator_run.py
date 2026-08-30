#!/usr/bin/env python3
"""Emit a content-free pass/fail summary; never copy console text or fixtures."""
import argparse
import json
from pathlib import Path
import re
import subprocess


def verified_counts(summary: dict, exit_code: int) -> tuple[dict, bool]:
    counts = {name: summary[name] for name in
              ("totalTestCount", "passedTests", "failedTests", "skippedTests", "expectedFailures")}
    if any(type(value) is not int or value < 0 for value in counts.values()):
        raise ValueError("Invalid test counts")
    platforms = {entry["device"]["platform"] for entry in summary["devicesAndConfigurations"]}
    passed = (exit_code == 0 and counts["totalTestCount"] > 0
              and counts["passedTests"] == counts["totalTestCount"]
              and counts["failedTests"] == counts["skippedTests"] == counts["expectedFailures"] == 0
              and platforms == {"iOS Simulator"})
    return counts, passed


def executions_match(suite: str, iterations: int, completed: int) -> bool:
    required = {"full": 16, "integration": 3, "journey": 1, "journey-observe": 1, "journey-renewal": 1,
                "live": 1, "soak": 1, "reconnect": 1, "lifecycle": 1, "semantic": 1}
    return iterations > 0 and suite in required and completed == required[suite] * iterations


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("run", type=Path)
    parser.add_argument("suite")
    parser.add_argument("source")
    parser.add_argument("exit_code", type=int)
    parser.add_argument("iterations", type=int, nargs="?", default=1)
    args = parser.parse_args()
    report = {
        "schemaVersion": 1,
        "suite": args.suite,
        "source": args.source,
        "environment": "iOS Simulator",
        "physicalDeviceUsed": False,
        "installedMacAppUsed": False,
        "exitCode": args.exit_code,
        "iterations": args.iterations,
        "result": "failed",
        "tests": None,
        "limits": [
            "Software test keys and simulated local consent; not Face ID or Secure Enclave evidence",
            "Loopback transport; not LAN, Bonjour, or shipping release-bootstrap evidence",
            "Disposable host runtime and lease issuance; authenticated lanes use the production renewal scheduler, not the installed Agent lifecycle",
        ],
    }
    try:
        result = subprocess.run([
            "xcrun", "xcresulttool", "get", "test-results", "summary", "--path",
            str(args.run / "features.xcresult"), "--compact",
        ], capture_output=True, text=True, check=True, timeout=30)
        summary = json.loads(result.stdout)
        counts, passed = verified_counts(summary, args.exit_code)
        report["tests"] = counts
        report["durationSeconds"] = round(summary["finishTime"] - summary["startTime"], 3)
        # xcresult can aggregate repeated executions under one test identity.
        # Require the expected individual completion lines as well, so missing
        # repetitions or an accidentally narrowed full suite cannot pass.
        log = (args.run / "features.log").read_text()
        completed = len(re.findall(r"^Test Case '-\[ClientUIHarnessUITests\.ClientUIHarnessUITests test\w+\]' passed \(", log, re.MULTILINE))
        report["completedExecutions"] = completed
        if passed and executions_match(args.suite, args.iterations, completed):
            report["result"] = "passed"
    except (OSError, subprocess.SubprocessError, KeyError, ValueError, TypeError):
        report["reportError"] = "Result bundle unavailable or invalid"
    (args.run / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Simulator report: {args.run / 'report.json'} ({report['result']})")
    return 0 if report["result"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
