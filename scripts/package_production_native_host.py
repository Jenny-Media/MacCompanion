#!/usr/bin/env python3
"""Build production first-party supervisor resources around the verified host.

Development packaging only. This does not admit a foreign target or install apps.
Existing tested host packages remain immutable and separately verifiable.
"""
import argparse
import json
import os
from pathlib import Path
import shutil

from package_native_host import command, digest
from package_source_native_host import build, verify as verify_host

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Native/Host/companion-supervisor.c"
PROFILE = "maccompanion.production-supervisor-development-package.v1"
FLAGS = ["-std=c11", "-mmacosx-version-min=26.0", "-Wall", "-Wextra", "-Werror"]
RECORD_KEYS = {"profile", "releaseAdmitted", "builderSHA256", "sourcePath", "sourceSHA256",
               "compilerSHA256", "compilerVersion", "sdkVersion", "compilerFlags",
               "compiledSHA256", "packagedSHA256", "hostManifestSHA256", "limits"}


def verify(output):
    record = json.loads((output / "production-supervisor.json").read_text())
    if (not isinstance(record, dict) or set(record) != RECORD_KEYS
            or record["profile"] != PROFILE or record["releaseAdmitted"] is not False
            or record["builderSHA256"] != digest(Path(__file__))
            or record["sourcePath"] != str(SOURCE.relative_to(ROOT))
            or record["sourceSHA256"] != digest(SOURCE)
            or record["compilerFlags"] != FLAGS
            or record["hostManifestSHA256"] != digest(output / "host-package.json")):
        raise ValueError("Production supervisor construction binding changed")
    host = verify_host(output)
    origin = host["origins"]["Contents/Helpers/companion-supervisor"]
    if origin["sourceSHA256"] != record["compiledSHA256"]:
        raise ValueError("Host package selected a different supervisor")
    # Inspect the actual packaged binary, after signing and any relocation.
    binary = output / "Sunshine.app/Contents/Helpers/companion-supervisor"
    if digest(binary) != record["packagedSHA256"]:
        raise ValueError("Packaged production supervisor changed")
    commands = command("xcrun", "vtool", "-show-build", binary)
    if "platform MACOS" not in commands or "minos 26.0" not in commands:
        raise ValueError("Supervisor deployment target changed")
    return record


def construct(native_root, host_root, output):
    # Own only fresh paths; never replace historical products or working roots.
    if output.exists():
        raise ValueError("Output must be a new directory")
    staging = output.parent / (output.name + "-supervisor-build")
    staging.mkdir(mode=0o700, parents=False, exist_ok=False)
    source_sha = digest(SOURCE)
    builder_sha = digest(Path(__file__))
    compiler = Path(command("xcrun", "--find", "clang"))
    sdk = Path(command("xcrun", "--sdk", "macosx", "--show-sdk-path"))
    binary = staging / "managed-host-supervisor"
    try:
        # The reused builder reads only notices beneath this upstream tree. The
        # symlink stays in private staging; no external link enters the package.
        os.symlink(native_root / "upstream", staging / "upstream", target_is_directory=True)
        command(compiler, *FLAGS, "-isysroot", sdk, SOURCE, "-o", binary)
        compiled_sha = digest(binary)
        compiler_sha = digest(compiler)
        compiler_version = command(compiler, "--version")
        build(staging, host_root, output)
        if source_sha != digest(SOURCE) or builder_sha != digest(Path(__file__)) or compiled_sha != digest(binary):
            raise ValueError("Production supervisor input changed during packaging")
        record = {
            "profile": PROFILE, "releaseAdmitted": False,
            "builderSHA256": builder_sha,
            "sourcePath": str(SOURCE.relative_to(ROOT)), "sourceSHA256": source_sha,
            "compilerSHA256": compiler_sha, "compilerVersion": compiler_version,
            "sdkVersion": command("xcrun", "--sdk", "macosx", "--show-sdk-version"),
            "compilerFlags": FLAGS, "compiledSHA256": compiled_sha,
            "packagedSHA256": digest(output / "Sunshine.app/Contents/Helpers/companion-supervisor"),
            "hostManifestSHA256": digest(output / "host-package.json"),
            "limits": ["Development signatures only", "Normal-app resource selection and installation pending"],
        }
        (output / "production-supervisor.json").write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
        return verify(output)
    finally:
        # Failed output is retained for inspection; staging is entirely owned.
        shutil.rmtree(staging)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native-root", required=True, type=Path)
    parser.add_argument("--host-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    record = construct(args.native_root.resolve(), args.host_root.resolve(), args.output.resolve())
    print(json.dumps({"package": str(args.output), "verified": True, "supervisorSHA256": record["packagedSHA256"]}))
