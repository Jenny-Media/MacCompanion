#!/usr/bin/env python3
"""Package the audited source-built host for development Simulator acceptance."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil

from package_native_host import command, dependencies, digest, files, system
from build_native_host_dependencies import LOCK, LOCK_PATH
from build_source_native_host import verified_files

HERE = Path(__file__).resolve().parent
PROFILE = "maccompanion.source-built-native-host-package.v1"


def source_records(host_root):
    record_path = host_root / "provenance.json"
    record = json.loads(record_path.read_text())
    if (record["profile"] != "maccompanion.source-built-native-host-development.v1"
            or not record["sourceBuilt"] or record["releaseAdmitted"]
            or record["inputs"]["builderSHA256"] != digest(HERE / "build_source_native_host.py")):
        raise ValueError("Invalid source-built development host")
    host = Path(record["binary"])
    if host.resolve() != (host_root / "build/Sunshine.app/Contents/MacOS/Sunshine").resolve() or digest(host) != record["binarySHA256"]:
        raise ValueError("Source-built host artifact changed")
    records, prefixes = {}, {}
    for name, binding in record["inputs"]["dependencyRecords"].items():
        path = Path(binding["path"])
        if digest(path) != binding["sha256"]:
            raise ValueError("Source dependency record changed: " + name)
        value = json.loads(path.read_text())
        if name == "codecs":
            prefix = path.parent / "prefix"
            if value["inputs"]["builderSHA256"] != digest(HERE / "build_native_host_codecs.py"):
                raise ValueError("Codec builder changed")
        else:
            prefix = path.parent / "prefixes" / name
            if (value["inputs"]["source"] != LOCK["sources"][name]
                    or value["inputs"]["lockSHA256"] != digest(LOCK_PATH)
                    or value["inputs"]["builderSHA256"] != digest(HERE / "build_native_host_dependencies.py")):
                raise ValueError("Runtime dependency builder changed: " + name)
        verified_files(prefix, value)
        records[name], prefixes[name] = value, prefix
    if set(records) != {*LOCK["sources"], "codecs"}:
        raise ValueError("Incomplete source dependency records")
    for group in [record["staticLinkInputs"], record["dynamicLinkInputs"]]:
        for path, checksum in group.items():
            if digest(Path(path)) != checksum:
                raise ValueError("Host link input changed")
    return record, records, prefixes


def verify(directory):
    report = json.loads((directory / "host-package.json").read_text())
    if (report["profile"] != PROFILE or report["releaseAdmitted"]
            or report["builderSHA256"] != digest(Path(__file__))
            or report["verifierSHA256"] != digest(HERE / "package_native_host.py")
            or report["sourceHostSHA256"] != report["sourceBuildRecord"]["binarySHA256"]
            or report["origins"]["Contents/MacOS/Sunshine"]["sourceSHA256"] != report["sourceHostSHA256"]
            or set(report["origins"]) != set(report["macho"])):
        raise ValueError("Source package construction provenance changed")
    bundle = directory / "Sunshine.app"
    if files(bundle) != report["files"]:
        raise ValueError("Packaged files changed")
    for relative in report["macho"]:
        if Path(relative).is_absolute() or ".." in Path(relative).parts or not relative.startswith("Contents/"):
            raise ValueError("Invalid package binary path")
        binary = bundle / relative
        command("codesign", "--verify", "--strict", binary)
        if rpaths(binary):
            raise ValueError("Packaged binary retains a library search path")
        for dependency in dependencies(binary):
            if system(dependency):
                continue
            if not dependency.startswith("@loader_path/"):
                raise ValueError("External package dependency: " + dependency)
            resolved = (binary.parent / dependency.removeprefix("@loader_path/")).resolve()
            if not resolved.is_relative_to(bundle.resolve()) or not resolved.is_file():
                raise ValueError("Unresolved package dependency: " + dependency)
    command("codesign", "--verify", "--strict", bundle)
    return report


def rpaths(binary):
    return re.findall(r"cmd LC_RPATH\s+cmdsize \d+\s+path (.+?) \(offset \d+\)", command("xcrun", "otool", "-l", binary))


def build(native_root, host_root, output):
    host_record, records, prefixes = source_records(host_root)
    host = Path(host_record["binary"])
    libraries = {}
    for prefix in prefixes.values():
        for path in (prefix / "lib").glob("*.dylib"):
            prior = libraries.get(path.name)
            if prior is not None and prior.resolve() != path.resolve():
                raise ValueError("Conflicting source library names")
            libraries[path.name] = path

    def resolve(original, dependency):
        if dependency.startswith("@loader_path/"):
            path = original.parent / dependency.removeprefix("@loader_path/")
        elif dependency.startswith("/"):
            path = Path(dependency)
        elif (dependency.startswith("@rpath/") and "/" not in dependency.removeprefix("@rpath/")) or "/" not in dependency:
            if Path(dependency).name not in libraries:
                raise ValueError("Unknown source runtime library: " + dependency)
            path = libraries[Path(dependency).name]
        else:
            raise ValueError("Unsupported source runtime library: " + dependency)
        if not any(path.resolve() == p.resolve() for p in libraries.values()):
            raise ValueError("Library is outside verified source prefixes: " + dependency)
        return path

    output.mkdir(parents=True, exist_ok=False)
    bundle = output / "Sunshine.app"
    shutil.copytree(host.parents[2], bundle, symlinks=True)
    helpers = bundle / "Contents/Helpers"
    helpers.mkdir(exist_ok=True)
    originals = {"Contents/MacOS/Sunshine": host,
                 "Contents/Helpers/openssl": prefixes["openssl"] / "bin/openssl",
                 "Contents/Helpers/companion-supervisor": native_root / "managed-host-supervisor"}
    for relative, original in originals.items():
        if relative != "Contents/MacOS/Sunshine":
            shutil.copy2(original, bundle / relative)
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
        origins[relative] = {"sourcePath": str(original.resolve()), "sourceSHA256": digest(original)}
        for old in dependencies(original):
            if system(old) or resolve(original, old).resolve() == original.resolve():
                continue
            replacement = frameworks / Path(old).name
            changes += ["-change", old, "@loader_path/" + os.path.relpath(replacement, target.parent)]
        for path in rpaths(original):
            changes += ["-delete_rpath", path]
        if target.suffix == ".dylib":
            changes += ["-id", "@loader_path/" + target.name]
        if changes:
            command("xcrun", "install_name_tool", *changes, target)
        command("codesign", "--force", "--sign", "-", "--timestamp=none", target)
    notices = bundle / "Contents/Resources/DependencyNotices"
    notices.mkdir(parents=True, exist_ok=True)
    shutil.copy2(native_root / "upstream/Sunshine/LICENSE", notices / "Sunshine-GPL-3.0.txt")
    for name, prefix in prefixes.items():
        if name != "codecs":
            shutil.copy2(prefix / "share/maccompanion-source-notices/LICENSE.txt", notices / (name + "-LICENSE.txt"))
        (notices / (name + "-source-build.json")).write_text(json.dumps(records[name], indent=2, sort_keys=True) + "\n")
    (notices / "host-source-build.json").write_text(json.dumps(host_record, indent=2, sort_keys=True) + "\n")
    codecs = native_root / "upstream/Sunshine/third-party/build-deps/third-party/FFmpeg"
    for name, path in {
        "FFmpeg-license.md": codecs / "FFmpeg/LICENSE.md",
        "FFmpeg-GPL-2.0.txt": codecs / "FFmpeg/COPYING.GPLv2",
        "FFmpeg-GPL-3.0.txt": codecs / "FFmpeg/COPYING.GPLv3",
        "x264-GPL-2.0.txt": codecs / "x264/COPYING",
        "x265-GPL-2.0.txt": codecs / "x265_git/COPYING",
        "SVT-AV1-license.md": codecs / "SVT-AV1/LICENSE.md",
        "SVT-AV1-BSD-2-Clause.md": codecs / "SVT-AV1/LICENSE-BSD2.md",
        "Boost-license.txt": host_root / "build/_deps/boost-src/LICENSE_1_0.txt",
        "nlohmann-json-license.txt": host_root / "build/_deps/json-src/LICENSE.MIT",
    }.items():
        shutil.copy2(path, notices / name)
    (notices / "openssl.cnf").write_text("# Development enrollment uses explicit command options.\n")
    source_records(host_root)
    command("codesign", "--force", "--sign", "-", "--timestamp=none", bundle)
    report = {"profile": PROFILE, "releaseAdmitted": False, "correspondingSourceComplete": False,
              "builderSHA256": digest(Path(__file__)), "verifierSHA256": digest(HERE / "package_native_host.py"),
              "sourceHostSHA256": digest(host), "sourceBuildRecord": host_record,
              "origins": origins, "macho": sorted(originals), "files": files(bundle),
              "limits": ["Development signatures only", "Complete transitive source distribution and permanent admission remain pending",
                         "No normal-app installation or physical/system-input acceptance"]}
    (output / "host-package.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    return verify(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native-root", type=Path, required=True)
    parser.add_argument("--host-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps({"package": str(args.output), "verified": bool(build(args.native_root.resolve(), args.host_root.resolve(), args.output.resolve()))}))
