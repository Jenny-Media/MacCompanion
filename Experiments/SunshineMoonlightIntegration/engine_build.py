#!/usr/bin/env python3
"""Build the video-only embedded Moonlight framework, without pairing or UI."""
import argparse
import hashlib
import json
import re
from pathlib import Path
import shutil
import subprocess

from reference_build import HERE, digest, native_source_inputs, run, verify_source
from openssl_build import build as build_openssl


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--sdk", choices=["iphonesimulator", "iphoneos"], default="iphonesimulator")
    parser.add_argument("--test-simulator", help="Run lifecycle tests on this existing Simulator UDID")
    parser.add_argument("--reference-probe", action="store_true", help="Include the disposable reference-only surface probe")
    args = parser.parse_args()
    root = args.root.resolve()
    upstream = verify_source(root, "moonlight-ios")
    project = root / "embedded-engine"
    sources = project / "Sources"
    sources.mkdir(parents=True, exist_ok=True)
    for name in ["CompanionMoonlightVideo.h", "CompanionMoonlightVideo.m", "CompanionNativeTLS.h", "CompanionNativeTLS.m"]:
        shutil.copy2(HERE.parents[1] / "Native/Client" / name, sources / name)
    for name in ["Stream/VideoDecoderRenderer.h", "Stream/VideoDecoderRenderer.m",
                 "Stream/ConnectionCallbacks.h", "Utility/Logger.h", "Utility/Logger.m"]:
        shutil.copy2(upstream / "Limelight" / name, sources / Path(name).name)
    # Keep Objective-C runtime classes and bridge callbacks distinct when the
    # reference application loads its original engine beside this component.
    for path in sources.iterdir():
        if path.suffix not in {".h", ".m"}:
            continue
        content = path.read_text()
        for symbol in ["VideoDecoderRenderer", "ConnectionCallbacks", "DrSubmitDecodeUnit", "Log", "LogTag"]:
            content = re.sub(r"\b" + symbol + r"\b", "CompanionMoonlight" + symbol, content)
        for header in ["VideoDecoderRenderer", "ConnectionCallbacks"]:
            content = content.replace('"CompanionMoonlight' + header + '.h"', '"' + header + '.h"')
        path.write_text(content)
    (sources / "Prefix.h").write_text('#ifdef __OBJC__\n#import <UIKit/UIKit.h>\n#import "Logger.h"\n#endif\n')
    (sources / "CompanionMoonlightEngine.h").write_text('#import <CompanionMoonlightEngine/CompanionMoonlightVideo.h>\n#import <CompanionMoonlightEngine/CompanionNativeTLS.h>\n')
    dependencies = project / "Dependencies"
    dependencies.mkdir(exist_ok=True)
    source_openssl = build_openssl(root)
    installed_openssl = dependencies / "OpenSSL.xcframework"
    if installed_openssl.exists():
        shutil.rmtree(installed_openssl)
    shutil.copytree(source_openssl, installed_openssl)
    common = upstream / "moonlight-common/moonlight-common-c"
    c_sources = sorted((common / "src").glob("*.c")) + sorted((common / "reedsolomon").glob("*.c"))
    c_sources += [common / "enet" / name for name in ["callbacks.c", "compress.c", "host.c", "list.c", "packet.c", "peer.c", "protocol.c", "unix.c"]]
    headers = [sources / name for name in ["VideoDecoderRenderer.h", "ConnectionCallbacks.h", "Logger.h", "Prefix.h"]]
    project_sources = [{"path": str(p)} for p in c_sources]
    project_sources += [{"path": str(p), "headerVisibility": "private"} for p in headers]
    project_sources += [{"path": str(sources / name)} for name in ["CompanionMoonlightVideo.m", "CompanionNativeTLS.m", "VideoDecoderRenderer.m", "Logger.m"]]
    project_sources += [{"path": str(sources / name), "headerVisibility": "public"}
                        for name in ["CompanionMoonlightVideo.h", "CompanionNativeTLS.h", "CompanionMoonlightEngine.h"]]
    dependencies_spec = [{"framework": str(dependencies / "OpenSSL.xcframework"), "embed": False}]
    # This first component is intentionally silent: no SDL, microphone or
    # gamepad integration. The native H.264/HEVC build excludes upstream's AV1
    # parser, so it needs no FFmpeg headers or static libraries.
    dependencies_spec += [{"sdk": name} for name in ["UIKit.framework", "AVFoundation.framework", "VideoToolbox.framework", "CoreMedia.framework", "QuartzCore.framework", "Security.framework", "libz.tbd", "libbz2.tbd", "libiconv.tbd"]]
    settings = {"PRODUCT_BUNDLE_IDENTIFIER": "dev.maccompanion.experiment.moonlight-engine",
                "DEFINES_MODULE": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
                "GENERATE_INFOPLIST_FILE": "YES", "GCC_PREFIX_HEADER": str(sources / "Prefix.h"),
                "GCC_PREPROCESSOR_DEFINITIONS": ["$(inherited)", "NDEBUG", "__APPLE_USE_RFC_3542", "HAS_SOCKLEN_T", "MACCOMPANION_NATIVE_H264_HEVC_ONLY=1"],
                "GCC_C_LANGUAGE_STANDARD": "gnu11", "TARGETED_DEVICE_FAMILY": "1,2",
                "ENABLE_MODULE_VERIFIER": "NO", "SKIP_INSTALL": "NO",
                "HEADER_SEARCH_PATHS": [str(common / "src"), str(common / "reedsolomon"), str(common / "enet/include"),
                                        str(sources), str(installed_openssl /
                                            ("ios-arm64-simulator" if args.sdk == "iphonesimulator" else "ios-arm64") /
                                            "OpenSSL.framework/Headers")],
                "OTHER_LDFLAGS": ["$(inherited)", "-ObjC"]}
    spec = {"name": "EmbeddedMoonlight", "targets": {"CompanionMoonlightEngine": {
        "type": "framework", "platform": "iOS", "deploymentTarget": "26.0",
        "sources": project_sources, "dependencies": dependencies_spec, "settings": {"base": settings}}}}
    spec["targets"]["CompanionMoonlightVideoTests"] = {
        "type": "bundle.unit-test", "platform": "iOS", "deploymentTarget": "26.0",
        "sources": [{"path": str(HERE / "CompanionMoonlightVideoTests.m")}],
        "dependencies": [{"target": "CompanionMoonlightEngine"}],
        "settings": {"base": {"PRODUCT_BUNDLE_IDENTIFIER": "dev.maccompanion.experiment.moonlight-tests",
                                "GENERATE_INFOPLIST_FILE": "YES"}}}
    spec["schemes"] = {"CompanionMoonlightEngine": {
        "build": {"targets": {"CompanionMoonlightEngine": "all"}},
        "test": {"targets": ["CompanionMoonlightVideoTests"]}}}
    spec["packages"] = {"MacCompanionKit": {"path": str(HERE.parents[1] / "Packages/MacCompanionKit")}}
    spec["targets"]["CompanionMoonlightAdapter"] = {
        "type": "framework", "platform": "iOS", "deploymentTarget": "26.0",
        "sources": [{"path": str(HERE.parents[1] / "Native/Client" / name)} for name in
                    ["MoonlightNativeVideoDriverV0.swift", "MoonlightNativeLaunchAdapterV0.swift", "NativeLaunchResponseV0.swift"]] + ([{"path": str(HERE / "ReferenceNativeSurfaceProbe.swift")}] if args.reference_probe else []),
        "dependencies": [{"target": "CompanionMoonlightEngine"},
                         {"package": "MacCompanionKit", "product": "CompanionClientPlatform"}],
        "settings": {"base": {"PRODUCT_BUNDLE_IDENTIFIER": "dev.maccompanion.experiment.moonlight-adapter",
                                "GENERATE_INFOPLIST_FILE": "YES", "SWIFT_VERSION": "6.0"}}}
    spec["targets"]["CompanionMoonlightAdapterTests"] = {
        "type": "bundle.unit-test", "platform": "iOS", "deploymentTarget": "26.0",
        "sources": [{"path": str(HERE / "MoonlightNativeVideoOwnerTests.swift")}],
        # The adapter already links the production product. A second direct
        # package dependency here makes Xcode turn its automatic static library
        # into a test-only dynamic framework, changing the embeddable artifact.
        "dependencies": [{"target": "CompanionMoonlightAdapter"}],
        "settings": {"base": {"PRODUCT_BUNDLE_IDENTIFIER": "dev.maccompanion.experiment.moonlight-adapter-tests",
                                "GENERATE_INFOPLIST_FILE": "YES", "SWIFT_VERSION": "6.0"}}}
    spec["schemes"]["CompanionMoonlightEngine"]["build"]["targets"]["CompanionMoonlightAdapter"] = "all"
    spec["schemes"]["CompanionMoonlightEngine"]["test"]["targets"].append("CompanionMoonlightAdapterTests")
    specification = project / "project.json"
    specification.write_text(json.dumps(spec, indent=2) + "\n")
    hashes = {str(p): digest(p) for p in sources.iterdir() if p.is_file()}
    (project / "source-hashes.json").write_text(json.dumps(hashes, indent=2) + "\n")
    run("xcodegen", "generate", "--spec", str(specification), "--project", str(project))
    _, source_input = native_source_inputs()
    run("xcodebuild", "-project", str(project / "EmbeddedMoonlight.xcodeproj"),
        "-scheme", "CompanionMoonlightEngine", "-configuration", "Debug", "-sdk", args.sdk,
        "-destination", "generic/platform=iOS Simulator" if args.sdk == "iphonesimulator" else "generic/platform=iOS",
        "-derivedDataPath", str(project / "DerivedData"), "ARCHS=arm64", "ONLY_ACTIVE_ARCH=YES",
        "CODE_SIGNING_ALLOWED=NO", "build", log=root / f"logs/embedded-{args.sdk}.log")
    if args.test_simulator:
        if args.sdk != "iphonesimulator":
            raise ValueError("Lifecycle tests require the Simulator SDK")
        run("xcodebuild", "-project", str(project / "EmbeddedMoonlight.xcodeproj"),
            "-scheme", "CompanionMoonlightEngine", "-configuration", "Debug",
            "-destination", f"platform=iOS Simulator,id={args.test_simulator}",
            "-derivedDataPath", str(project / "DerivedData"), "ARCHS=arm64", "ONLY_ACTIVE_ARCH=YES",
            "CODE_SIGNING_ALLOWED=NO", "-parallel-testing-enabled", "NO", "test",
            log=root / "logs/embedded-lifecycle-tests.log")
    if native_source_inputs()[1] != source_input:
        raise ValueError("Candidate source changed during build; rebuild before inventory")
    products = project / f"DerivedData/Build/Products/Debug-{args.sdk}"
    (project / f"provenance-{args.sdk}.json").write_text(json.dumps({
        "sdk": args.sdk, "sourceInputSHA256": source_input, "referenceProbeIncluded": args.reference_probe,
        "sourceLockSHA256": digest(HERE / "source-lock.json"),
        "binarySHA256": {name: digest(products / f"{name}.framework" / name)
                         for name in ["CompanionMoonlightEngine", "CompanionMoonlightAdapter", "OpenSSL"]}
    }, indent=2, sort_keys=True) + "\n")
    print(project / f"DerivedData/Build/Products/Debug-{args.sdk}/CompanionMoonlightEngine.framework")


if __name__ == "__main__":
    main()
