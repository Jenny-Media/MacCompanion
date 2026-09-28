#!/usr/bin/env python3
"""Exercise the Swift Control/process adapter with a real owned disposable child."""
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix="maccompanion-process-owner-", dir="/private/tmp") as value:
    root = Path(value)
    subprocess.run(["xcrun", "clang", "-std=c11", "-mmacosx-version-min=26.0", "-Wall", "-Wextra", "-Werror",
                    str(HERE.parents[1] / "Native/Host/companion-supervisor.c"), "-o", str(root / "supervisor")], check=True)
    subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                    "-module-cache-path", str(root / "module-cache"),
                    str(HERE.parents[1] / "Packages/MacCompanionKit/Sources/CompanionMacApplicationPlatform/MacManagedSunshineProcessOwnerV1.swift"), str(HERE / "ProcessOwnerTests.swift"),
                    "-o", str(root / "owner-tests")], check=True)
    subprocess.run([str(root / "owner-tests"), str(root)], check=True, timeout=15)
