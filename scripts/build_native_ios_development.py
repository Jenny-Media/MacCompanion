#!/usr/bin/env python3
"""Build the normal iOS app in an explicitly admitted Debug-only native project.

Permanent release dependencies and identities remain governed by their own policy.
No reference harness, reference authority, or experimental implementation is linked.
"""
import argparse
import json
import plistlib
import shutil
import struct
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Experiments/SunshineMoonlightIntegration"))
from reference_build import digest, native_source_inputs

SIMULATOR_KEYCHAIN_ID = "dev.maccompanion.simulator.media.jenny.maccompanion.ios"


def verify_simulator_entitlements(output, app):
    expected = {"application-identifier": SIMULATOR_KEYCHAIN_ID,
                "keychain-access-groups": [SIMULATOR_KEYCHAIN_ID]}
    supplied = output / "SimulatorDevelopment.entitlements"
    assert plistlib.loads(supplied.read_bytes()) == expected
    packaged = list((output / "DerivedData/Build/Intermediates.noindex").rglob("Mac Companion.app-Simulated.xcent"))
    assert len(packaged) == 1 and plistlib.loads(packaged[0].read_bytes()) == expected
    # Simulator security reads the entitlement section, not an iPhone-style
    # entitlement manually added to the host macOS code signature.
    executable = (app / "Mac Companion").read_bytes()
    assert struct.unpack_from("<I", executable)[0] == 0xFEEDFACF
    cursor = 32
    embedded = []
    for _ in range(struct.unpack_from("<I", executable, 16)[0]):
        command, size = struct.unpack_from("<II", executable, cursor)
        if command == 0x19:
            for index in range(struct.unpack_from("<I", executable, cursor + 64)[0]):
                section = cursor + 72 + index * 80
                if executable[section:section + 16].rstrip(b"\0") == b"__entitlements":
                    length = struct.unpack_from("<Q", executable, section + 40)[0]
                    offset = struct.unpack_from("<I", executable, section + 48)[0]
                    embedded.append(plistlib.loads(executable[offset:offset + length].rstrip(b"\0")))
        cursor += size
    assert embedded == [expected], "Executable Simulator entitlements differ"
    info = plistlib.loads((app / "Info.plist").read_bytes())
    assert info["DTPlatformName"] == "iphonesimulator"
    subprocess.run(["codesign", "--verify", "--strict", str(app)], check=True)
    return {"developmentOnly": True, "generatedEntitlementsSHA256": digest(supplied),
            "packagedSimulatedEntitlementsSHA256": digest(packaged[0])}


def build(native_root, output, sdk, reuse_build=None):
    output.mkdir(parents=True, exist_ok=False)
    prior_artifact = None
    if reuse_build is not None:
        # Only a previous disposable normal development build may supply the
        # cache. Preserve its verified app before rebuilding its shared cache.
        assert reuse_build.parent == Path('/private/tmp') and reuse_build.name.startswith('maccompanion-')
        previous = json.loads((reuse_build / 'build-report.json').read_text())
        assert previous['normalSourceRoot'] and previous['releaseAdmitted'] is False and previous['sdk'] == sdk
        previous_app = Path(previous['app'])
        assert digest(previous_app / 'Mac Companion') == previous['normalApplicationBinarySHA256']
        prior_artifact = reuse_build / 'PreservedVerifiedApplication.app'
        shutil.copytree(previous_app, prior_artifact, symlinks=True)
        assert digest(prior_artifact / 'Mac Companion') == previous['normalApplicationBinarySHA256']
        (output / 'DerivedData').symlink_to((reuse_build / 'DerivedData').resolve(strict=True), target_is_directory=True)
    source_sha = native_source_inputs()[1]
    builder_sha = digest(Path(__file__))
    products = native_root / f"embedded-engine/DerivedData/Build/Products/Debug-{sdk}"
    provenance = json.loads((native_root / f"embedded-engine/provenance-{sdk}.json").read_text())
    if provenance["sourceInputSHA256"] != source_sha or provenance.get("referenceProbeIncluded", True):
        raise ValueError("Native SDK source or normal-profile admission mismatch")
    for name, checksum in provenance["binarySHA256"].items():
        if digest(products / f"{name}.framework/{name}") != checksum:
            raise ValueError("Native SDK artifact changed: " + name)
    resolved = output / "normal-project.json"
    subprocess.run(["xcodegen", "dump", "--spec", str(ROOT / "project.yml"), "--type", "json",
                    "--file", str(resolved), "--quiet"], check=True)
    original = json.loads(resolved.read_text())
    target = original["targets"]["MacCompanionIOS"]
    for source in target["sources"]:
        source["path"] = str(ROOT / source["path"])
    target["sources"] += [{"path": str(ROOT / "Native/Client" / name)} for name in
                          ["MoonlightNativeVideoDriverV0.swift", "MoonlightNativeLaunchAdapterV0.swift", "NativeLaunchResponseV0.swift"]]
    target["dependencies"] += [{"framework": str(products / f"{name}.framework"), "embed": True}
                               for name in ["CompanionMoonlightEngine", "OpenSSL"]]
    if sdk == "iphonesimulator":
        # Preserve admitted framework signatures; only the app needs Xcode's
        # Simulator entitlement section and ad hoc development signature.
        for dependency in target["dependencies"]:
            if "framework" in dependency:
                dependency["codeSign"] = False
    base = target["settings"]["base"]
    # XcodeGen's JSON dump represents YAML version 1 as a number and later
    # emits it as the boolean build setting YES. Keep the bundle version text.
    base["CURRENT_PROJECT_VERSION"] = str(base["CURRENT_PROJECT_VERSION"])
    base["INFOPLIST_FILE"] = str(ROOT / base["INFOPLIST_FILE"])
    base["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "$(inherited) DEBUG MACCOMPANION_ADMITTED_NATIVE_DEVELOPMENT"
    base["CODE_SIGNING_ALLOWED"] = "NO"
    if sdk == "iphonesimulator":
        entitlements = output / "SimulatorDevelopment.entitlements"
        entitlements.write_bytes(plistlib.dumps({"application-identifier": SIMULATOR_KEYCHAIN_ID,
                                                "keychain-access-groups": [SIMULATOR_KEYCHAIN_ID]}))
        base.update({"CODE_SIGNING_ALLOWED": "YES", "CODE_SIGN_IDENTITY": "-",
                     "CODE_SIGN_ENTITLEMENTS": str(entitlements)})
    # Keep executable provenance bound to actual app code, rather than the
    # tiny launcher stub produced by Xcode's Debug-dylib mode.
    base["ENABLE_DEBUG_DYLIB"] = "NO"
    specification = {
        "name": "NormalNativeDevelopment", "configs": {"Debug": "debug"},
        "options": original.get("options", {}), "settings": original.get("settings", {}),
        "packages": {"MacCompanionKit": {"path": str(ROOT / "Packages/MacCompanionKit")}},
        "targets": {"MacCompanionIOS": target},
        "schemes": {"MacCompanionIOS": {"build": {"targets": {"MacCompanionIOS": "all"}},
            **{action: {"config": "Debug"} for action in ["run", "test", "profile", "analyze", "archive"]}}},
    }
    # XcodeGen's intermediate-group path traversal can loop when an external
    # project crosses macOS's /tmp and /private/tmp aliases. File locations stay
    # absolute; group generation is only editor organization.
    specification["options"]["createIntermediateGroups"] = False
    specification["options"]["defaultConfig"] = "Debug"
    spec = output / "project.json"
    spec.write_text(json.dumps(specification, indent=2) + "\n")
    subprocess.run(["xcodegen", "generate", "--spec", str(spec), "--project", str(output)], check=True)
    with (output / "build.log").open("w") as log:
        subprocess.run(["xcodebuild", "-project", str(output / "NormalNativeDevelopment.xcodeproj"),
            "-scheme", "MacCompanionIOS", "-configuration", "Debug", "-sdk", sdk,
            "-destination", "generic/platform=iOS Simulator" if sdk == "iphonesimulator" else "generic/platform=iOS",
            "-derivedDataPath", str(output / "DerivedData"), "ARCHS=arm64", "ONLY_ACTIVE_ARCH=YES", "build"],
            check=True, stdout=log, stderr=subprocess.STDOUT)
    if native_source_inputs()[1] != source_sha or digest(Path(__file__)) != builder_sha:
        raise ValueError("Source changed during normal native app build")
    app = output / f"DerivedData/Build/Products/Debug-{sdk}/Mac Companion.app"
    for name in ["CompanionMoonlightEngine", "OpenSSL"]:
        if digest(app / f"Frameworks/{name}.framework/{name}") != provenance["binarySHA256"][name]:
            raise ValueError("Embedded native artifact changed: " + name)
    record = {"profile": "maccompanion.normal-ios-native-development-build.v1", "releaseAdmitted": False,
              "sourceInputSHA256": source_sha, "builderSHA256": builder_sha,
              "sdk": sdk, "app": str(app), "normalSourceRoot": True,
              "nativeFrameworksVerified": True, "referenceProbeIncluded": False,
              "simulatorEntitlements": verify_simulator_entitlements(output, app) if sdk == "iphonesimulator" else None,
              "simulatorDevelopmentBootstrap": sdk == "iphonesimulator",
              "approvalUserPresenceSubstituted": False,
              "normalApplicationBinarySHA256": digest(app / "Mac Companion"),
              "installed": False, "nativeSessionVerified": False}
    record['reusedDisposableBuildCache'] = str(reuse_build) if reuse_build else None
    record['previousVerifiedApplicationPreserved'] = str(prior_artifact) if prior_artifact else None
    (output / "build-report.json").write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    return record


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--sdk", choices=["iphonesimulator", "iphoneos"], default="iphonesimulator")
    parser.add_argument("--reuse-build-cache", type=Path, help="Reuse a disposable normal build cache after preserving its verified app")
    args = parser.parse_args()
    print(json.dumps(build(args.root.resolve(), args.output.resolve(), args.sdk,
        args.reuse_build_cache.resolve() if args.reuse_build_cache else None), sort_keys=True))
