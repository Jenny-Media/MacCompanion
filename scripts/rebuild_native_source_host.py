#!/usr/bin/env python3
"""Rebuild Sunshine with pinned packet sources and separately pinned rebuilt inputs."""
import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tarfile

from package_native_host import digest, files
from rebuild_native_source_dependencies import extract, run


def capture(*args):
    return subprocess.check_output([str(arg) for arg in args], text=True).strip()


def pinned(path, checksum):
    if digest(path) != checksum:
        raise ValueError("Changed pinned record: " + str(path))
    return json.loads(path.read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-inputs", required=True, type=Path)
    parser.add_argument("--manifest-sha256", required=True)
    parser.add_argument("--runtime-rebuild", required=True, type=Path)
    parser.add_argument("--runtime-report-sha256", required=True)
    parser.add_argument("--codec-rebuild", required=True, type=Path)
    parser.add_argument("--codec-report-sha256", required=True)
    parser.add_argument("--web-inputs", required=True, type=Path)
    parser.add_argument("--web-report-sha256", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    builder_sha = digest(Path(__file__))
    runtime, codecs, web, output = (p.resolve() for p in
                                  [args.runtime_rebuild, args.codec_rebuild, args.web_inputs, args.output])
    runtime_report = pinned(runtime / "rebuild-report.json", args.runtime_report_sha256)
    codec_report = pinned(codecs / "rebuild-report.json", args.codec_report_sha256)
    web_report = pinned(web / "web-source-inputs.json", args.web_report_sha256)
    for record in [runtime_report, web_report]:
        if record["sourceManifestSHA256"] != args.manifest_sha256 or record["releaseAdmitted"]:
            raise ValueError("Rebuild input belongs to a different source packet")
    if (codec_report["inputs"]["sourceManifestSHA256"] != args.manifest_sha256 or
            not codec_report["sourceBuilt"] or codec_report["releaseAdmitted"] or
            files(codecs / "prefix") != codec_report["files"]):
        raise ValueError("Changed source-rebuilt codecs")
    if not runtime_report["macRuntimeSourceRebuilt"] or not web_report["offlineWebUIBuildVerified"]:
        raise ValueError("Missing prior source-rebuild acceptance")
    manifest, payload = extract(args.source_inputs.resolve(), args.manifest_sha256, output)
    host_record = json.loads((payload / "build-records/host.json").read_text())
    inputs = host_record["inputs"]
    if digest(payload / "workspace/scripts/build_source_native_host.py") != inputs["builderSHA256"]:
        raise ValueError("Retained host builder mismatch")
    if (inputs["sunshineRevision"] != manifest["components"]["Sunshine"]["revision"] or
            manifest["components"]["Sunshine"]["excludedFiles"] or
            capture("xcodebuild", "-version") != inputs["toolchain"]):
        raise ValueError("Source revision or Apple toolchain mismatch")
    dependencies = runtime / "mac-runtime"
    prefixes = []
    dependency_records = {}
    for name in ["openssl", "miniupnpc", "opus", "icu"]:
        path = dependencies / (name + "-provenance.json")
        record = pinned(path, runtime_report["buildRecords"][name]["recordSHA256"])
        prefix = dependencies / "prefixes" / name
        actual = {str(p.relative_to(prefix)): digest(p) for p in prefix.rglob("*") if p.is_file()}
        if (not record["sourceBuilt"] or record["releaseAdmitted"] or actual != record["files"] or
                digest(payload / "workspace/scripts/build_native_host_dependencies.py") != record["inputs"]["builderSHA256"]):
            raise ValueError("Changed source-rebuilt runtime: " + name)
        prefixes.append(prefix)
        dependency_records[name] = digest(path)
    source = output / "working-Sunshine"
    shutil.copytree(payload / "upstream/Sunshine", source, symlinks=True)
    archive_sources = {}
    for name in ["boost", "nlohmann_json"]:
        binding = manifest["archives"][name]
        archive = payload / binding["path"]
        if digest(archive) != binding["sha256"]:
            raise ValueError("Changed dependency archive: " + name)
        destination = output / (name + "-source")
        destination.mkdir()
        with tarfile.open(archive) as stream:
            stream.extractall(destination, filter="data")
        roots = list(destination.iterdir())
        if len(roots) != 1 or not roots[0].is_dir():
            raise ValueError("Unexpected source archive layout: " + name)
        archive_sources[name] = roots[0]
    lock = json.loads((source / "package-lock.json").read_text())
    if (digest(source / "package-lock.json") != web_report["lockSHA256"] or
            set(web_report["packages"]) != {key for key in lock["packages"] if key}):
        raise ValueError("Different Web UI source lock")
    archives = []
    for key, record in web_report["packages"].items():
        path = web / "archives" / record["archive"]
        binding = lock["packages"][key]
        if (digest(path) != record["archiveSHA256"] or binding["integrity"] != record["integrity"] or
                binding["version"] != record["version"]):
            raise ValueError("Changed Web UI package: " + key)
        archives.append(path)
    environment = {key: value for key, value in os.environ.items()
                   if not key.startswith(("DYLD_", "OPENSSL_", "NPM_", "npm_", "CODECOV_", "GITHUB_", "SUNSHINE_", "CPM_"))
                   and key not in {"CC", "CXX", "CFLAGS", "CXXFLAGS", "CPPFLAGS", "LDFLAGS", "SDKROOT",
                                   "CMAKE_PREFIX_PATH", "PKG_CONFIG_PATH", "PKG_CONFIG_LIBDIR", "BRANCH",
                                   "BUILD_VERSION", "COMMIT", "TAG", "CLONE_URL"}}
    sdk = capture("xcrun", "--sdk", "macosx", "--show-sdk-path")
    empty_user, empty_global = output / "empty-user.npmrc", output / "empty-global.npmrc"
    empty_user.write_text(""); empty_global.write_text("")
    environment.update(SDKROOT=sdk, PKG_CONFIG_PATH="", GITHUB_REPOSITORY="",
                       npm_config_cache=str(output / "npm-cache"), npm_config_offline="true",
                       npm_config_userconfig=str(empty_user), npm_config_globalconfig=str(empty_global),
                       BRANCH="source-archive", BUILD_VERSION="0.0.0", COMMIT=inputs["sunshineRevision"])
    npm_options = ["--offline", "--ignore-scripts", "--userconfig", empty_user, "--globalconfig", empty_global]
    run(["npm", "cache", "add", *archives, *npm_options], output, "npm-cache-import", environment)
    system_pc = output / "system-pkgconfig"
    system_pc.mkdir()
    curl = system_pc / "libcurl.pc"
    curl.write_text("Name: libcurl\nDescription: Apple SDK system libcurl\nVersion: " +
                    capture("/usr/bin/curl-config", "--version").removeprefix("libcurl ") +
                    "\nLibs: -L" + sdk + "/usr/lib -lcurl\nCflags: -I" + sdk + "/usr/include\n")
    environment["PKG_CONFIG_LIBDIR"] = os.pathsep.join(str(p / "lib/pkgconfig") for p in prefixes) + os.pathsep + str(system_pc)
    configuration = inputs["configuration"]
    if configuration[:2] != ["cmake", "-S"] or configuration[3] != "-B":
        raise ValueError("Unexpected retained host configuration")
    selected_capture_replacements = []
    selected_flag = "-DMACCOMPANION_SELECTED_CAPTURE_SOURCE_ROOT="
    selected_flags = [arg for arg in configuration if arg.startswith(selected_flag)]
    if "selectedCaptureSources" in inputs:
        selected_sources = inputs["selectedCaptureSources"]
        selected_root = payload / "workspace/Native/Host"
        admitted_source_sets = [
            {"CompanionSelectedCapture.h", "CompanionSelectedCapture.m"},
            {"CompanionSelectedCapture.h", "CompanionSelectedCapture.m",
             "CompanionSelectedCaptureContext.h", "CompanionSelectedCaptureContext.m"},
            {"CompanionSelectedCapture.h", "CompanionSelectedCapture.m",
             "CompanionSelectedCaptureContext.h", "CompanionSelectedCaptureContext.m",
             "CompanionSelectedCaptureHandoff.h", "CompanionSelectedCaptureHandoff.m",
             "CompanionNativeEpochAssociation.h", "../Client/CompanionNativeSurfaceEpoch.h"},
        ]
        if (set(selected_sources) not in admitted_source_sets
                or len(selected_flags) != 1
                or {name: digest(selected_root / name) for name in selected_sources} != selected_sources):
            raise ValueError("Selected capture adapter differs from retained host inputs")
        selected_capture_replacements.append((selected_flags[0], selected_flag + str(selected_root)))
    elif selected_flags:
        raise ValueError("Selected capture build lacks retained adapter source bindings")
    old_dependencies = str(Path(inputs["dependencyRecords"]["openssl"]["path"]).parent)
    old_codecs = str(Path(inputs["dependencyRecords"]["codecs"]["path"]).parent)
    replacements = selected_capture_replacements + [(configuration[2], str(source)), (str(Path(configuration[4]).parent), str(output)),
                    (old_dependencies, str(dependencies)), (old_codecs, str(codecs))]
    command = []
    for arg in configuration:
        for old, new in replacements:
            arg = arg.replace(old, new)
        command.append(arg)
    if "-DCMAKE_OSX_SYSROOT=" + sdk not in command:
        raise ValueError("Apple SDK mismatch")
    command += ["-DFETCHCONTENT_SOURCE_DIR_BOOST=" + str(archive_sources["boost"]),
                "-DFETCHCONTENT_SOURCE_DIR_JSON=" + str(archive_sources["nlohmann_json"]),
                "-DFETCHCONTENT_FULLY_DISCONNECTED=ON", "-DNPM_OFFLINE=ON"]
    record = {"sourceManifestSHA256": args.manifest_sha256, "sourceArchiveSHA256": manifest["archiveSHA256"],
              "builderSHA256": builder_sha, "runtimeReportSHA256": args.runtime_report_sha256,
              "codecReportSHA256": args.codec_report_sha256, "webReportSHA256": args.web_report_sha256,
              "configuration": command, "archiveBuildVersion": "0.0.0", "sunshineRevision": inputs["sunshineRevision"],
              "runtimeDependencyRecords": dependency_records, "webPackageArchives": len(archives)}
    (output / "source-inputs.json").write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    print("Configuring Sunshine with local source archives and rebuilt dependencies", flush=True)
    run(command, output, "configure", environment)
    print("Building Sunshine and its Web UI using the isolated offline npm cache", flush=True)
    run(["cmake", "--build", output / "build", "-j4"], output, "build", environment)
    binary = output / "build/Sunshine.app/Contents/MacOS/Sunshine"
    static_inputs = {}
    for token in shlex.split((output / "build/CMakeFiles/sunshine.dir/link.txt").read_text()):
        if token.endswith(".a"):
            path = Path(token)
            path = path if path.is_absolute() else output / "build" / path
            if not any(path.resolve().is_relative_to(root) for root in [output, codecs]):
                raise ValueError("Unexpected static link input: " + str(path))
            static_inputs[str(path.resolve())] = digest(path)
    dynamic_inputs = {}
    for line in capture("xcrun", "otool", "-L", binary).splitlines()[1:]:
        dependency = line.strip().split(" (compatibility version", 1)[0]
        if dependency.startswith(("/System/Library/", "/usr/lib/")):
            continue
        path = Path(dependency)
        if not path.is_absolute():
            matches = [p / "lib" / path.name for p in prefixes if (p / "lib" / path.name).is_file()]
            if len(matches) != 1:
                raise ValueError("Ambiguous native runtime: " + dependency)
            path = matches[0]
        if not any(path.resolve().is_relative_to(p.resolve()) for p in prefixes):
            raise ValueError("Unexpected native runtime: " + dependency)
        dynamic_inputs[str(path.resolve())] = digest(path)
    if (files(payload) != manifest["files"] or digest(Path(__file__)) != builder_sha or
            files(codecs / "prefix") != codec_report["files"]):
        raise ValueError("Pinned build inputs changed during host rebuild")
    for name, prefix in zip(["openssl", "miniupnpc", "opus", "icu"], prefixes):
        path = dependencies / (name + "-provenance.json")
        bound = pinned(path, dependency_records[name])
        if {str(p.relative_to(prefix)): digest(p) for p in prefix.rglob("*") if p.is_file()} != bound["files"]:
            raise ValueError("Runtime changed during host rebuild: " + name)
    if any(digest(path) != web_report["packages"][key]["archiveSHA256"]
           for key, path in zip(web_report["packages"], archives)):
        raise ValueError("Web input changed during host rebuild")
    assets = output / "build/assets/web"
    if not (assets / "index.html").is_file() or not (assets / "pin.html").is_file():
        raise ValueError("Missing freshly rebuilt Web UI")
    report = {"profile": "maccompanion.native-source-host-rebuild.v1", "inputs": record,
              "binary": str(binary), "binarySHA256": digest(binary), "staticLinkInputs": static_inputs,
              "dynamicLinkInputs": dynamic_inputs, "rebuiltWebAssets": files(assets),
              "sourceBuilt": True, "sourcePayloadUnchanged": True, "releaseAdmitted": False,
              "correspondingSourceComplete": False, "videoAcceptanceVerified": False,
              "bitIdenticalReproductionClaimed": False}
    (output / "rebuild-report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"passed": True, "nativeHostSourceRebuilt": True, "releaseAdmitted": False}))


if __name__ == "__main__":
    main()
