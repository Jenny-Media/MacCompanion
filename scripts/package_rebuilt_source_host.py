#!/usr/bin/env python3
"""Package the pinned archive-rebuilt host without changing historical packages."""
import argparse
import json
import os
from pathlib import Path
import shutil

from package_native_host import command, dependencies, digest, files, system
from package_source_native_host import rpaths
from package_production_native_host import SOURCE, FLAGS

PROFILE = "maccompanion.archive-rebuilt-native-host-package.v1"


def verify(output):
    record = json.loads((output / "host-package.json").read_text())
    if (record["profile"] != PROFILE or record["releaseAdmitted"] is not False or
            record["builderSHA256"] != digest(Path(__file__)) or
            record["supervisorBuild"]["sourceSHA256"] != digest(SOURCE) or
            record["supervisorBuild"]["compilerFlags"] != FLAGS or
            record["sourceHostSHA256"] != record["sourceBuildRecord"]["binarySHA256"] or
            record["origins"]["Contents/MacOS/Sunshine"]["sourceSHA256"] != record["sourceHostSHA256"] or
            set(record["macho"]) != set(record["origins"])):
        raise ValueError("Archive package construction binding changed")
    bundle = output / "Sunshine.app"
    if files(bundle) != record["files"]:
        raise ValueError("Archive package files changed")
    for relative in record["macho"]:
        path = Path(relative)
        if path.is_absolute() or ".." in path.parts or not relative.startswith("Contents/"):
            raise ValueError("Invalid packaged binary path")
        binary = bundle / path
        command("codesign", "--verify", "--strict", binary)
        if rpaths(binary):
            raise ValueError("Packaged binary retains a search path")
        for dependency in dependencies(binary):
            if system(dependency):
                continue
            if not dependency.startswith("@loader_path/"):
                raise ValueError("External packaged dependency: " + dependency)
            resolved = (binary.parent / dependency.removeprefix("@loader_path/")).resolve()
            if not resolved.is_relative_to(bundle.resolve()) or not resolved.is_file():
                raise ValueError("Unresolved packaged dependency")
    supervisor = bundle / "Contents/Helpers/companion-supervisor"
    if (digest(supervisor) != record["supervisorBuild"]["packagedSHA256"] or
            record["origins"]["Contents/Helpers/companion-supervisor"]["sourceSHA256"] !=
            record["supervisorBuild"]["compiledSHA256"]):
        raise ValueError("Supervisor construction changed")
    commands = command("xcrun", "vtool", "-show-build", supervisor)
    if "platform MACOS" not in commands or "minos 26.0" not in commands:
        raise ValueError("Supervisor deployment changed")
    command("codesign", "--verify", "--strict", bundle)
    return record


def verify_selected(output):
    profile = json.loads((output / "host-package.json").read_text())["profile"]
    if profile == PROFILE:
        return verify(output)
    from package_native_host import verify as historical_verify
    return historical_verify(output)


def openssl_binding(record):
    if record["profile"] == PROFILE:
        return record["opensslBinding"]
    if record["profile"] == "maccompanion.source-built-native-host-package.v1":
        return record["sourceBuildRecord"]["inputs"]["dependencyRecords"]["openssl"]
    return None


def build(host_root, report_sha, runtime_root, runtime_sha, output):
    host_path = host_root / "rebuild-report.json"
    runtime_path = runtime_root / "rebuild-report.json"
    if digest(host_path) != report_sha or digest(runtime_path) != runtime_sha:
        raise ValueError("Changed selected rebuild report")
    host = json.loads(host_path.read_text())
    runtime = json.loads(runtime_path.read_text())
    if (host["profile"] != "maccompanion.native-source-host-rebuild.v1" or not host["sourceBuilt"] or
            host["releaseAdmitted"] or host["inputs"]["runtimeReportSHA256"] != runtime_sha or
            host["inputs"]["sourceManifestSHA256"] != runtime["sourceManifestSHA256"]):
        raise ValueError("Different archive rebuild inputs")
    binary = host_root / "build/Sunshine.app/Contents/MacOS/Sunshine"
    if digest(binary) != host["binarySHA256"]:
        raise ValueError("Changed rebuilt host")
    for group in [host["staticLinkInputs"], host["dynamicLinkInputs"]]:
        for path, checksum in group.items():
            if digest(Path(path)) != checksum:
                raise ValueError("Changed rebuilt host link input")
    libraries, prefixes, bindings = {}, {}, {}
    for name in ["openssl", "miniupnpc", "opus", "icu"]:
        path = runtime_root / "mac-runtime" / (name + "-provenance.json")
        expected = runtime["buildRecords"][name]["recordSHA256"]
        if digest(path) != expected:
            raise ValueError("Changed runtime record")
        record = json.loads(path.read_text())
        prefix = path.parent / "prefixes" / name
        actual = {str(p.relative_to(prefix)): digest(p) for p in prefix.rglob("*") if p.is_file()}
        if not record["sourceBuilt"] or record["releaseAdmitted"] or actual != record["files"]:
            raise ValueError("Changed runtime files")
        prefixes[name] = prefix
        bindings[name] = {"path": str(path), "sha256": expected}
        for library in (prefix / "lib").glob("*.dylib"):
            if library.name in libraries and libraries[library.name].resolve() != library.resolve():
                raise ValueError("Ambiguous source library name")
            libraries[library.name] = library
    output.mkdir(parents=True, exist_ok=False)
    bundle = output / "Sunshine.app"
    shutil.copytree(binary.parents[2], bundle, symlinks=True)
    helpers = bundle / "Contents/Helpers"
    helpers.mkdir(exist_ok=True)
    supervisor = output / "compiled-supervisor"
    compiler = Path(command("xcrun", "--find", "clang"))
    sdk = Path(command("xcrun", "--sdk", "macosx", "--show-sdk-path"))
    supervisor_source_sha = digest(SOURCE)
    command(compiler, *FLAGS, "-isysroot", sdk, SOURCE, "-o", supervisor)
    supervisor_build = {"sourceSHA256": supervisor_source_sha, "compiledSHA256": digest(supervisor),
                        "compilerSHA256": digest(compiler), "compilerFlags": FLAGS,
                        "sdkVersion": command("xcrun", "--sdk", "macosx", "--show-sdk-version")}
    originals = {"Contents/MacOS/Sunshine": binary, "Contents/Helpers/companion-supervisor": supervisor,
                 "Contents/Helpers/openssl": prefixes["openssl"] / "bin/openssl"}
    for relative, original in originals.items():
        if relative != "Contents/MacOS/Sunshine":
            shutil.copy2(original, bundle / relative)

    def resolve(original, dependency):
        if dependency.startswith("@loader_path/"):
            path = original.parent / dependency.removeprefix("@loader_path/")
        elif dependency.startswith("/"):
            path = Path(dependency)
        elif Path(dependency).name in libraries and (dependency.startswith("@rpath/") or "/" not in dependency):
            path = libraries[Path(dependency).name]
        else:
            raise ValueError("Unsupported runtime dependency")
        if not any(path.resolve() == p.resolve() for p in libraries.values()):
            raise ValueError("Runtime outside verified prefixes")
        return path

    collected, queue = {}, list(originals.values())
    while queue:
        original = queue.pop()
        for dependency in dependencies(original):
            if system(dependency):
                continue
            path = resolve(original, dependency)
            if path.resolve() == original.resolve():
                continue
            if path.name not in collected:
                collected[path.name] = path
                queue.append(path)
    frameworks = bundle / "Contents/Frameworks"
    frameworks.mkdir(exist_ok=True)
    for name, original in collected.items():
        relative = "Contents/Frameworks/" + name
        shutil.copy2(original, bundle / relative)
        originals[relative] = original
    origins = {}
    for relative, original in originals.items():
        target, changes = bundle / relative, []
        origins[relative] = {"sourceSHA256": digest(original), "sourcePath": str(original.resolve())}
        for dependency in dependencies(original):
            if system(dependency) or resolve(original, dependency).resolve() == original.resolve():
                continue
            changes += ["-change", dependency, "@loader_path/" + os.path.relpath(frameworks / Path(dependency).name, target.parent)]
        for path in rpaths(original):
            changes += ["-delete_rpath", path]
        if target.suffix == ".dylib":
            changes += ["-id", "@loader_path/" + target.name]
        if changes:
            command("xcrun", "install_name_tool", *changes, target)
        command("codesign", "--force", "--sign", "-", "--timestamp=none", target)
    notices = bundle / "Contents/Resources/DependencyNotices"
    notices.mkdir(parents=True, exist_ok=True)
    shutil.copy2(host_root / "payload/upstream/Sunshine/LICENSE", notices / "Sunshine-GPL-3.0.txt")
    for name, prefix in prefixes.items():
        shutil.copy2(prefix / "share/maccompanion-source-notices/LICENSE.txt", notices / (name + "-LICENSE.txt"))
    codec_sources = host_root / "payload/upstream/Sunshine/third-party/build-deps/third-party/FFmpeg"
    for name, path in {
        "FFmpeg-license.md": codec_sources / "FFmpeg/LICENSE.md",
        "FFmpeg-GPL-2.0.txt": codec_sources / "FFmpeg/COPYING.GPLv2",
        "FFmpeg-GPL-3.0.txt": codec_sources / "FFmpeg/COPYING.GPLv3",
        "x264-GPL-2.0.txt": codec_sources / "x264/COPYING",
        "x265-GPL-2.0.txt": codec_sources / "x265_git/COPYING",
        "SVT-AV1-license.md": codec_sources / "SVT-AV1/LICENSE.md",
        "SVT-AV1-BSD-2-Clause.md": codec_sources / "SVT-AV1/LICENSE-BSD2.md",
        "Boost-license.txt": host_root / "boost-source/boost-1.89.0/LICENSE_1_0.txt",
        "nlohmann-json-license.txt": host_root / "nlohmann_json-source/json/LICENSE.MIT",
    }.items():
        shutil.copy2(path, notices / name)
    (notices / "archive-host-build.json").write_text(json.dumps(host, indent=2, sort_keys=True) + "\n")
    (notices / "openssl.cnf").write_text("# Development enrollment uses explicit command options.\n")
    command("codesign", "--force", "--sign", "-", "--timestamp=none", bundle)
    supervisor_build["packagedSHA256"] = digest(bundle / "Contents/Helpers/companion-supervisor")
    if digest(host_path) != report_sha or digest(runtime_path) != runtime_sha or digest(SOURCE) != supervisor_source_sha:
        raise ValueError("Package construction inputs changed")
    record = {"profile": PROFILE, "releaseAdmitted": False, "correspondingSourceComplete": False,
              "builderSHA256": digest(Path(__file__)), "sourceHostSHA256": host["binarySHA256"],
              "sourceBuildRecord": host, "sourceRebuildReportSHA256": report_sha, "runtimeRebuildReportSHA256": runtime_sha,
              "supervisorBuild": supervisor_build, "opensslBinding": bindings["openssl"],
              "origins": origins, "macho": sorted(originals), "files": files(bundle)}
    (output / "host-package.json").write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    return verify(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host-root", type=Path, required=True)
    parser.add_argument("--host-report-sha256", required=True)
    parser.add_argument("--runtime-root", type=Path, required=True)
    parser.add_argument("--runtime-report-sha256", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    record = build(args.host_root.resolve(), args.host_report_sha256, args.runtime_root.resolve(),
                   args.runtime_report_sha256, args.output.resolve())
    print(json.dumps({"verified": True, "machoCount": len(record["macho"]), "releaseAdmitted": False}))
