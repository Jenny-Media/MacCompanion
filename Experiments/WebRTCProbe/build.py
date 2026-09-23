#!/usr/bin/env python3
"""Build only a pinned, disposable Apple WebRTC API probe; never download or install."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import posixpath
import stat
import subprocess
import sys
import tempfile
import zipfile


ARCHIVE_SHA256 = "3e3a8946f27510133e3feed04d05fa23505bbe366e977620503bfc7986c2b78f"
PACKAGE_REVISION = "4266157cd08f92115de885ab12d87196a8db87e1"
SOURCE_REVISION = "9ea5afcad008b940468c2a15aec339592cf5a935"
SOURCE = Path(__file__).resolve().parent


def inspect_archive(path):
    with path.open("rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != ARCHIVE_SHA256:
            raise ValueError("Archive digest does not match the admitted WebRTC release")
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise ValueError("Archive integrity failure")
        for item in archive.infolist():
            name = posixpath.normpath(item.filename)
            if not (name == "WebRTC.xcframework" or name.startswith("WebRTC.xcframework/")):
                raise ValueError("Archive member escapes the admitted framework")
            if stat.S_ISLNK(item.external_attr >> 16):
                destination = archive.read(item).decode("utf-8")
                resolved = posixpath.normpath(posixpath.join(posixpath.dirname(name), destination))
                if not resolved.startswith("WebRTC.xcframework/"):
                    raise ValueError("Archive symlink escapes the admitted framework")


def run(args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--run-mac", action="store_true", help="Run synthetic API creation only")
    args = parser.parse_args()
    inspect_archive(args.archive)
    build = Path(tempfile.mkdtemp(prefix="maccompanion-webrtc-probe-", dir="/private/tmp"))
    print(f"Build directory: {build}", flush=True)
    # ditto preserves the versioned macOS framework's symlinks.
    run(["ditto", "-xk", str(args.archive.resolve()), str(build / "sdk")])
    framework = build / "sdk" / "WebRTC.xcframework"
    targets = [
        ("macosx", "arm64-apple-macosx26.0", "macos-x86_64_arm64", "mac-probe"),
        ("iphoneos", "arm64-apple-ios26.0", "ios-arm64", "iphone-probe.dylib"),
        ("iphonesimulator", "arm64-apple-ios26.0-simulator", "ios-x86_64_arm64-simulator", "simulator-probe.dylib"),
    ]
    record = {
        "release": "153.0.0", "packageRevision": PACKAGE_REVISION,
        "reportedSourceRevision": SOURCE_REVISION, "archiveSHA256": ARCHIVE_SHA256,
        "developerDirectory": os.environ.get("DEVELOPER_DIR", "active Xcode"),
        "builds": [], "runtime": None,
        "physicalDeviceTested": False, "releaseTargetsChanged": False,
    }
    result_path = build / "result.json"

    def save_record():
        result_path.write_text(json.dumps(record, indent=2) + "\n")

    save_record()
    for sdk, triple, slice_name, output in targets:
        sdk_path = run(["xcrun", "--sdk", sdk, "--show-sdk-path"], capture_output=True).stdout.strip()
        command = [
            "xcrun", "--sdk", sdk, "swiftc", "-swift-version", "6", "-parse-as-library",
            "-sdk", sdk_path, "-target", triple, "-F", str(framework / slice_name),
            "-framework", "WebRTC", "-module-name", "DisposableWebRTCProbe",
            str(SOURCE / "PackageProbe.swift"), "-o", str(build / output),
            "-module-cache-path", str(build / "module-cache"),
        ]
        if sdk == "macosx":
            command += [str(SOURCE / "PackageProbeMain.swift"), "-Xlinker", "-rpath", "-Xlinker", str(framework / slice_name)]
        else:
            command += ["-emit-library"]
        log = build / (sdk + ".log")
        observation = {"sdk": sdk, "sdkPath": sdk_path, "triple": triple, "compileAndLinkPassed": False}
        record["builds"].append(observation)
        save_record()
        with log.open("w") as stream:
            result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT)
        if result.returncode != 0:
            print(f"Build failed. Diagnostic log: {log}", file=sys.stderr)
            result.check_returncode()
        observation["compileAndLinkPassed"] = True
        save_record()
        print(f"Compile and link passed: {sdk}", flush=True)
    if args.run_mac:
        try:
            runtime = subprocess.run([str(build / "mac-probe")], capture_output=True, text=True, timeout=30)
        except subprocess.TimeoutExpired:
            record["runtime"] = {"passed": False, "failure": "timeout"}
            save_record()
            raise
        (build / "mac-runtime.log").write_text(runtime.stderr)
        (build / "mac-runtime.json").write_text(runtime.stdout)
        if runtime.returncode != 0:
            record["runtime"] = {"passed": False, "exitCode": runtime.returncode}
            save_record()
            print(f"Runtime failed. Diagnostic log: {build / 'mac-runtime.log'}", file=sys.stderr)
            runtime.check_returncode()
        record["runtime"] = json.loads(runtime.stdout)
    save_record()
    print(f"Evidence: {result_path}", flush=True)


if __name__ == "__main__":
    main()
