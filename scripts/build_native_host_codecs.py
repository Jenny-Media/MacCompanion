#!/usr/bin/env python3
"""Build the complete pinned macOS FFmpeg/codec dependency set from source."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Experiments/SunshineMoonlightIntegration"))
from reference_build import verify_source, digest

COMMITS = {
    "FFmpeg": "bf1b838f2ab88b4f8fd83443325c782ea0e0f7fa",
    "SVT-AV1": "9292ec8e32bce26f781f277ec8739b53426c4300",
    "x264": "b35605ace3ddf7c1a5d67a2eb553f034aef41d55",
    "x265_git": "1d117bed4747758b51bd2c124d738527e30392cb",
}


def capture(*args):
    return subprocess.check_output([str(a) for a in args], text=True).strip()


def run(args, environment, log):
    with log.open("w") as output:
        subprocess.run([str(a) for a in args], env=environment, stdout=output,
                       stderr=subprocess.STDOUT, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    sunshine = verify_source(args.native_root.resolve(), "Sunshine")
    source = sunshine / "third-party/build-deps"
    for name, revision in COMMITS.items():
        path = source / "third-party/FFmpeg" / name
        if capture("git", "-C", path, "rev-parse", "HEAD") != revision:
            raise ValueError("Codec source revision changed: " + name)
        if capture("git", "-C", path, "diff", "HEAD", "--") or capture("git", "-C", path, "ls-files", "--others", "--exclude-standard"):
            raise ValueError("Codec source modified: " + name)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    (output / "provenance.json").unlink(missing_ok=True)
    sdk = capture("xcrun", "--sdk", "macosx", "--show-sdk-path")
    environment = {k: v for k, v in os.environ.items()
                   if k not in {"CC", "CXX", "CFLAGS", "CXXFLAGS", "CPPFLAGS", "LDFLAGS", "SDKROOT", "PKG_CONFIG_PATH", "PKG_CONFIG_LIBDIR"}}
    environment["PKG_CONFIG_PATH"] = ""
    flags = "-arch arm64 -mmacosx-version-min=26.0 -isysroot " + sdk
    # FFmpeg's configure invokes the linker separately from CMake's compiler
    # checks. Its link command needs the same explicit Apple SDK as compilation.
    environment["LDFLAGS"] = flags
    # FFmpeg also compiles build-time host tools without extra-cflags.
    environment["SDKROOT"] = sdk
    environment["MACOSX_DEPLOYMENT_TARGET"] = "26.0"
    prefix = output / "prefix"
    environment["PKG_CONFIG_LIBDIR"] = str(prefix / "lib/pkgconfig")
    # The upstream copied x265 tree cannot resolve its Git metadata and omits
    # x265.pc. Describe only our pinned source-built prefix; never fall back to
    # the developer's installed encoder headers or libraries.
    x265_source = source / "third-party/FFmpeg/x265_git"
    tag = capture("git", "-C", x265_source, "describe", "--tags", "--abbrev=0")
    x265_pc = prefix / "lib/pkgconfig/x265.pc"
    x265_pc.parent.mkdir(parents=True, exist_ok=True)
    x265_pc.write_text("Name: x265\nDescription: Pinned source-built x265 development dependency\nVersion: " + tag
                       + "\nLibs: -L" + str(prefix / "lib") + " -lx265\nLibs.private: -lc++ -lm\nCflags: -I"
                       + str(prefix / "include") + "\n")
    configuration = ["cmake", "-S", source, "-B", output / "build",
                     "-DBUILD_ALL=OFF", "-DBUILD_FFMPEG=ON", "-DCMAKE_BUILD_TYPE=Release",
                     "-DCMAKE_C_COMPILER=" + capture("xcrun", "--find", "clang"),
                     "-DCMAKE_CXX_COMPILER=" + capture("xcrun", "--find", "clang++"),
                     "-DCMAKE_OSX_ARCHITECTURES=arm64", "-DCMAKE_OSX_DEPLOYMENT_TARGET=26.0",
                     "-DCMAKE_OSX_SYSROOT=" + sdk, "-DCMAKE_C_FLAGS=" + flags,
                     "-DARM_ARGS=-mmacosx-version-min=26.0;-isysroot;" + sdk,
                     "-DCMAKE_CXX_FLAGS=" + flags, "-DFFMPEG_INSTALL_PREFIX=" + str(prefix),
                     "-DCMAKE_POLICY_VERSION_MINIMUM=3.5", "-DN_PROC=4",
                     "-DPKG_CONFIG_PATH=" + str(prefix / "lib/pkgconfig")]
    inputs = {"builderSHA256": digest(Path(__file__)), "buildDepsRevision": capture("git", "-C", source, "rev-parse", "HEAD"),
              "codecCommits": COMMITS, "configuration": [str(a) for a in configuration],
              "toolchain": capture("xcodebuild", "-version"), "linkerFlags": flags,
              "sdkRoot": sdk, "pkgConfigLibdir": environment["PKG_CONFIG_LIBDIR"],
              "x265SourceTag": tag, "x265DescriptorSHA256": digest(x265_pc)}
    (output / "source-inputs.json").write_text(json.dumps(inputs, indent=2, sort_keys=True) + "\n")
    run(configuration, environment, output / "configure.log")
    # x265's custom assembly commands bypass CMake's normal deployment flags.
    # Recompile their generated objects when adopting the explicit ARM_ARGS.
    for object_path in (output / "build/x265").glob("*.S.o"):
        object_path.unlink()
    generated_ffmpeg = output / "build/FFmpeg/FFmpeg"
    if (generated_ffmpeg / "ffbuild/config.mak").exists():
        # FFmpeg's Makefiles do not rebuild every object when discovery flags
        # change. Discard only this generated tree's prior compiler outputs.
        run(["/usr/bin/make", "-C", generated_ffmpeg, "distclean"], environment, output / "ffmpeg-clean.log")
    run(["cmake", "--build", output / "build", "-j4"], environment, output / "build.log")
    run(["cmake", "--install", output / "build"], environment, output / "install.log")
    required = ["libavcodec.a", "libavutil.a", "libswscale.a", "libcbs.a", "libSvtAv1Enc.a", "libx264.a", "libx265.a"]
    for name in required:
        if not (prefix / "lib" / name).is_file():
            raise ValueError("Missing source-built codec: " + name)
    import re
    deployment_versions = {}
    for name in required:
        load_commands = capture("xcrun", "otool", "-l", prefix / "lib" / name)
        versions = re.findall(r"\bminos\s+(\d+\.\d+(?:\.\d+)?)", load_commands)
        versions += re.findall(r"cmd LC_VERSION_MIN_MACOSX\s+cmdsize \d+\s+version (\d+\.\d+(?:\.\d+)?)", load_commands)
        if not versions or any(tuple(map(int, version.split("."))) > (26, 0, 0) for version in versions):
            raise ValueError("Codec exceeds the requested macOS deployment target: " + name)
        deployment_versions[name] = sorted(set(versions))
    report = {"inputs": inputs, "sourceBuilt": True, "releaseAdmitted": False,
              "deploymentVersions": deployment_versions,
              "files": {str(p.relative_to(prefix)): digest(p) for p in sorted(prefix.rglob("*")) if p.is_file()}}
    (output / "provenance.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"sourceBuiltCodecLibraries": len(required), "prefix": str(prefix), "releaseAdmitted": False}))


if __name__ == "__main__":
    main()
