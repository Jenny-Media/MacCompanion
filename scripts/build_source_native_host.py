#!/usr/bin/env python3
"""Build a development Sunshine host using verified source-built dependencies."""
import argparse
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys

from build_native_host_dependencies import LOCK, LOCK_PATH, digest, source
from build_native_host_codecs import COMMITS

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Experiments/SunshineMoonlightIntegration"))
from reference_build import verify_source


def capture(*args):
    return subprocess.check_output([str(a) for a in args], text=True).strip()


def verified_files(prefix, record):
    actual = {str(p.relative_to(prefix)): digest(p) for p in sorted(prefix.rglob("*")) if p.is_file()}
    if not record.get("sourceBuilt") or record.get("releaseAdmitted") or actual != record["files"]:
        raise ValueError("Source-built dependency files changed: " + str(prefix))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native-root", type=Path, required=True)
    parser.add_argument("--dependencies", type=Path, required=True)
    parser.add_argument("--codecs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    deps, codecs, output = args.dependencies.resolve(), args.codecs.resolve(), args.output.resolve()
    sunshine = verify_source(args.native_root.resolve(), "Sunshine")
    selected_capture = ROOT / "Native/Host"
    selected_capture_inputs = {name: digest(selected_capture / name) for name in
                               ["CompanionSelectedCapture.h", "CompanionSelectedCapture.m",
                                "CompanionSelectedCaptureContext.h", "CompanionSelectedCaptureContext.m"]}
    records = {}
    prefixes = []
    for name in LOCK["sources"]:
        source(deps, name)
        record_path = deps / (name + "-provenance.json")
        record = json.loads(record_path.read_text())
        if (record["inputs"]["source"] != LOCK["sources"][name]
                or record["inputs"]["lockSHA256"] != digest(LOCK_PATH)
                or record["inputs"]["builderSHA256"] != digest(ROOT / "scripts/build_native_host_dependencies.py")):
            raise ValueError("Dependency build inputs changed: " + name)
        prefix = deps / "prefixes" / name
        verified_files(prefix, record)
        prefixes.append(prefix)
        records[name] = {"path": str(record_path), "sha256": digest(record_path)}
    codec_record_path = codecs / "provenance.json"
    codec_record = json.loads(codec_record_path.read_text())
    if codec_record["inputs"]["builderSHA256"] != digest(ROOT / "scripts/build_native_host_codecs.py"):
        raise ValueError("Codec builder changed")
    if codec_record["inputs"]["codecCommits"] != COMMITS:
        raise ValueError("Codec source pins changed")
    for name, revision in COMMITS.items():
        path = sunshine / "third-party/build-deps/third-party/FFmpeg" / name
        if (capture("git", "-C", path, "rev-parse", "HEAD") != revision
                or capture("git", "-C", path, "diff", "HEAD", "--")
                or capture("git", "-C", path, "ls-files", "--others", "--exclude-standard")):
            raise ValueError("Codec source changed: " + name)
    verified_files(codecs / "prefix", codec_record)
    records["codecs"] = {"path": str(codec_record_path), "sha256": digest(codec_record_path)}
    output.mkdir(parents=True, exist_ok=True)
    sdk = capture("xcrun", "--sdk", "macosx", "--show-sdk-path")
    # Apple supplies system libcurl through the SDK, without a pkg-config file.
    # Describe that exact SDK library rather than discovering a Homebrew binary.
    system_pc = output / "system-pkgconfig"
    system_pc.mkdir(exist_ok=True)
    curl_pc = system_pc / "libcurl.pc"
    curl_version = capture("/usr/bin/curl-config", "--version").removeprefix("libcurl ")
    curl_pc.write_text("Name: libcurl\nDescription: Apple SDK system libcurl\nVersion: " + curl_version
                       + "\nLibs: -L" + sdk + "/usr/lib -lcurl\nCflags: -I" + sdk + "/usr/include\n")
    environment = {k: v for k, v in os.environ.items()
                   if k not in {"CC", "CXX", "CFLAGS", "CXXFLAGS", "CPPFLAGS", "LDFLAGS", "SDKROOT",
                                "CMAKE_PREFIX_PATH", "PKG_CONFIG_PATH", "PKG_CONFIG_LIBDIR"}}
    environment["SDKROOT"] = sdk
    environment["PKG_CONFIG_LIBDIR"] = os.pathsep.join(str(p / "lib/pkgconfig") for p in prefixes) + os.pathsep + str(system_pc)
    environment["PKG_CONFIG_PATH"] = ""
    build = output / "build"
    configuration = ["cmake", "-S", sunshine, "-B", build,
                     "-DCMAKE_BUILD_TYPE=Release", "-DBUILD_DOCS=OFF", "-DBUILD_TESTS=OFF",
                     "-DSUNSHINE_ENABLE_TRAY=OFF", "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
                     "-DCMAKE_C_COMPILER=" + capture("xcrun", "--find", "clang"),
                     "-DCMAKE_CXX_COMPILER=" + capture("xcrun", "--find", "clang++"),
                     "-DCMAKE_OSX_ARCHITECTURES=arm64", "-DCMAKE_OSX_DEPLOYMENT_TARGET=26.0",
                     "-DCMAKE_OSX_SYSROOT=" + sdk,
                     "-DCMAKE_EXE_LINKER_FLAGS=-L" + str(deps / "prefixes/miniupnpc/lib"),
                     "-DCMAKE_PREFIX_PATH=" + ";".join(str(p) for p in prefixes),
                     "-DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew",
                     "-DOPENSSL_ROOT_DIR=" + str(prefixes[0]),
                     "-DOpus_ROOT_DIR=" + str(deps / "prefixes/opus"),
                     "-DFFMPEG_PREPARED_BINARIES=" + str(codecs / "prefix"),
                     "-DMACCOMPANION_SELECTED_CAPTURE_SOURCE_ROOT=" + str(selected_capture)]
    inputs = {"builderSHA256": digest(Path(__file__)), "dependencyRecords": records,
              "sunshineRevision": capture("git", "-C", sunshine, "rev-parse", "HEAD"),
              "selectedCaptureSources": selected_capture_inputs,
              "toolchain": capture("xcodebuild", "-version"), "configuration": [str(a) for a in configuration],
              "pkgConfigLibdir": environment["PKG_CONFIG_LIBDIR"], "systemCurlDescriptorSHA256": digest(curl_pc),
              "systemCurlSDKStubSHA256": digest(Path(sdk) / "usr/lib/libcurl.tbd")}
    (output / "source-inputs.json").write_text(json.dumps(inputs, indent=2, sort_keys=True) + "\n")
    for label, command in [("configure", configuration), ("build", ["cmake", "--build", build, "-j4"])]:
        with (output / (label + ".log")).open("w") as log:
            subprocess.run([str(a) for a in command], cwd=sunshine, env=environment,
                           stdout=log, stderr=subprocess.STDOUT, check=True)
    binary = build / "Sunshine.app/Contents/MacOS/Sunshine"
    boost_archive = build / "_deps/boost-subbuild/boost-populate-prefix/src/boost-1.89.0-cmake.tar.xz"
    if digest(boost_archive) != "67acec02d0d118b5de9eb441f5fb707b3a1cdd884be00ca24b9a73c995511f74":
        raise ValueError("Boost source archive changed")
    link_file = build / "CMakeFiles/sunshine.dir/link.txt"
    # Retain each actual static link input, including source-built Boost and subprojects.
    static_inputs = {}
    for token in shlex.split(link_file.read_text()):
        if token.endswith(".a"):
            path = Path(token)
            if not path.is_absolute():
                path = build / path
            if path.resolve().is_relative_to(Path("/opt/homebrew")):
                raise ValueError("Unexpected prebuilt static input: " + str(path))
            static_inputs[str(path.resolve())] = digest(path)
    dynamic_inputs = {}
    for line in capture("xcrun", "otool", "-L", binary).splitlines()[1:]:
        dependency = line.strip().split(" (compatibility version", 1)[0]
        if dependency.startswith(("/System/Library/", "/usr/lib/")):
            continue
        path = Path(dependency)
        if ((dependency.startswith("@rpath/") and "/" not in dependency.removeprefix("@rpath/"))
                or (not path.is_absolute() and "/" not in dependency and dependency.endswith(".dylib"))):
            matches = [p / "lib" / path.name for p in prefixes if (p / "lib" / path.name).is_file()]
            if len(matches) != 1:
                raise ValueError("Ambiguous runtime dependency: " + dependency)
            path = matches[0]
        if not path.is_absolute() or not any(path.resolve().is_relative_to(p.resolve()) for p in prefixes):
            raise ValueError("Unexpected host runtime dependency: " + dependency)
        dynamic_inputs[str(path.resolve())] = digest(path)
    verify_source(args.native_root.resolve(), "Sunshine")
    if selected_capture_inputs != {name: digest(selected_capture / name) for name in selected_capture_inputs}:
        raise ValueError("Selected capture adapter changed during build")
    for name, prefix in zip(LOCK["sources"], prefixes):
        verified_files(prefix, json.loads((deps / (name + "-provenance.json")).read_text()))
    verified_files(codecs / "prefix", codec_record)
    report = {"profile": "maccompanion.source-built-native-host-development.v1", "inputs": inputs,
              "binary": str(binary), "binarySHA256": digest(binary), "sourceBuilt": True,
              "releaseAdmitted": False, "staticLinkInputs": static_inputs, "dynamicLinkInputs": dynamic_inputs,
              "linkCommandSHA256": digest(link_file),
              "boostSourceArchiveSHA256": digest(boost_archive),
              "boostLicenseSHA256": digest(build / "_deps/boost-src/LICENSE_1_0.txt")}
    (output / "provenance.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"binary": str(binary), "sha256": digest(binary), "releaseAdmitted": False}))


if __name__ == "__main__":
    main()
