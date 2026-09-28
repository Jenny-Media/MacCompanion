#!/usr/bin/env python3
"""Build pinned OpenSSL source into arm64 iOS and Simulator frameworks."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tarfile
import urllib.request

from reference_build import HERE, LOCK, digest, run


def capture(*args):
    return subprocess.check_output(args, text=True).strip()


def build(root):
    artifact = LOCK["downloads"]["ios_openssl_source"]
    output = root / "source-openssl"
    output.mkdir(parents=True, exist_ok=True)
    archive = output / ("openssl-" + artifact["version"] + ".tar.gz")
    if not archive.exists():
        temporary = archive.with_suffix(".download")
        urllib.request.urlretrieve(artifact["url"], temporary)
        if digest(temporary) != artifact["sha256"]:
            raise ValueError("OpenSSL source checksum mismatch")
        temporary.replace(archive)
    if digest(archive) != artifact["sha256"]:
        raise ValueError("OpenSSL source archive changed")
    source = output / ("openssl-" + artifact["version"])
    if not source.exists():
        with tarfile.open(archive) as contents:
            contents.extractall(output, filter="data")
    # Always verify the extracted source against the locked archive before use.
    with tarfile.open(archive) as contents:
        for member in contents:
            if member.isfile():
                import hashlib
                expected = hashlib.sha256(contents.extractfile(member).read()).hexdigest()
                if digest(output / member.name) != expected:
                    raise ValueError("OpenSSL extracted source changed: " + member.name)
    toolchain = capture("xcodebuild", "-version")
    input_record = {"source": artifact, "builderSHA256": digest(HERE / "openssl_build.py"),
                    "toolchain": toolchain, "deploymentTarget": "26.0",
                    "configuration": ["no-shared", "no-module", "no-tests", "no-engine"]}
    for sdk, target, platform in [
        ("iphoneos", "ios64-xcrun", "iPhoneOS"),
        ("iphonesimulator", "iossimulator-arm64-xcrun", "iPhoneSimulator"),
    ]:
        framework = output / sdk / "OpenSSL.framework"
        provenance = output / (sdk + "-provenance.json")
        sdk_path = capture("xcrun", "--sdk", sdk, "--show-sdk-path")
        inputs = {**input_record, "sdk": sdk,
                  "sdkVersion": capture("xcrun", "--sdk", sdk, "--show-sdk-version")}
        if provenance.exists():
            prior = json.loads(provenance.read_text())
            if prior["inputs"] == inputs and all(
                (framework / p).is_file() and digest(framework / p) == checksum
                for p, checksum in prior["files"].items()
            ):
                continue
        work = output / (sdk + "-build")
        if work.exists():
            shutil.rmtree(work)
        work.mkdir()
        minimum = ("-miphoneos-version-min=26.0" if sdk == "iphoneos"
                   else "-mios-simulator-version-min=26.0")
        run("perl", str(source / "Configure"), target,
            *input_record["configuration"], "-isysroot", sdk_path, minimum,
            cwd=work, log=output / (sdk + "-configure.log"))
        run("make", "-j4", "build_libs", cwd=work,
            log=output / (sdk + "-build.log"))
        if framework.exists():
            shutil.rmtree(framework)
        (framework / "Headers" / "openssl").mkdir(parents=True)
        for headers in [source / "include/openssl", work / "include/openssl"]:
            for header in headers.glob("*.h"):
                shutil.copy2(header, framework / "Headers/openssl" / header.name)
        (framework / "Modules").mkdir()
        (framework / "Modules/module.modulemap").write_text(
            'framework module OpenSSL { umbrella "../Headers" export * module * { export * } }\n')
        (framework / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "dev.maccompanion.experiment.openssl",
            "CFBundleExecutable": "OpenSSL", "CFBundleName": "OpenSSL",
            "CFBundlePackageType": "FMWK", "CFBundleVersion": "1",
            "CFBundleShortVersionString": artifact["version"],
            "CFBundleSupportedPlatforms": [platform], "MinimumOSVersion": "26.0",
        }))
        run("xcrun", "--sdk", sdk, "clang", "-arch", "arm64", "-isysroot", sdk_path,
            minimum, "-dynamiclib", "-Wl,-all_load", str(work / "libssl.a"),
            str(work / "libcrypto.a"), "-install_name", "@rpath/OpenSSL.framework/OpenSSL",
            "-o", str(framework / "OpenSSL"), log=output / (sdk + "-framework.log"))
        shutil.copy2(source / "LICENSE.txt", framework / "LICENSE.txt")
        files = {str(p.relative_to(framework)): digest(p)
                 for p in sorted(framework.rglob("*")) if p.is_file()}
        provenance.write_text(json.dumps({"inputs": inputs, "files": files,
            "sourceBuilt": True, "releaseAdmitted": False}, indent=2, sort_keys=True) + "\n")
        # Only this builder's disposable objects; source, final products and logs survive.
        shutil.rmtree(work)
    xcframework = output / "OpenSSL.xcframework"
    if xcframework.exists():
        shutil.rmtree(xcframework)
    run("xcodebuild", "-create-xcframework", "-framework",
        str(output / "iphoneos/OpenSSL.framework"), "-framework",
        str(output / "iphonesimulator/OpenSSL.framework"), "-output", str(xcframework),
        log=output / "xcframework.log")
    return xcframework


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    args = parser.parse_args()
    print(build(args.root.resolve()))
