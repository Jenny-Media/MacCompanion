#!/usr/bin/env python3
"""Rebuild all seven host codec libraries from an explicitly pinned source packet.

The retained packet stays immutable. Archive-specific version/tag handling is
applied to an owned working copy and recorded, without inventing Git history.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

from build_native_host_codecs import COMMITS
from package_native_host import digest, files
from rebuild_native_source_dependencies import extract, run

LIBRARIES = ["libavcodec.a", "libavutil.a", "libswscale.a", "libcbs.a",
             "libSvtAv1Enc.a", "libx264.a", "libx265.a"]


def capture(*args):
    return subprocess.check_output([str(a) for a in args], text=True).strip()


def build(packet, manifest_sha, output):
    builder_sha = digest(Path(__file__))
    manifest, payload = extract(packet, manifest_sha, output)
    base = "Sunshine/third-party/build-deps"
    components = manifest["components"]
    original = json.loads((payload / "build-records/codecs.json").read_text())
    inputs = original["inputs"]
    archived_builder = payload / "workspace/scripts/build_native_host_codecs.py"
    if (digest(archived_builder) != inputs["builderSHA256"] or
            inputs["codecCommits"] != COMMITS or not original["sourceBuilt"] or original["releaseAdmitted"]):
        raise ValueError("Codec source/build record mismatch")
    if components[base]["revision"] != inputs["buildDepsRevision"] or components[base]["excludedFiles"]:
        raise ValueError("Incomplete or different build-deps source")
    for name, revision in COMMITS.items():
        component = components[base + "/third-party/FFmpeg/" + name]
        if (component["revision"] != revision or component["excludedFiles"] or
                component["trackedDiffSHA256"] != "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"):
            raise ValueError("Incomplete or modified codec source: " + name)
    if capture("xcodebuild", "-version") != inputs["toolchain"]:
        raise ValueError("Rebuild requires the recorded Apple toolchain")
    sdk = capture("xcrun", "--sdk", "macosx", "--show-sdk-path")
    if sdk != inputs["sdkRoot"]:
        raise ValueError("Rebuild requires the recorded SDK")
    source = output / "working-build-deps"
    shutil.copytree(payload / "upstream" / base, source, symlinks=True)
    # The archive has no Git database. These two calls only fetch version tags;
    # source revisions and complete payload bytes have already been checked.
    tag_macro = source / "cmake/git_fetch_tags.cmake"
    version = source / "third-party/FFmpeg/x265_git/x265Version.txt"
    patches = {}
    for path in [tag_macro, version]:
        patches[str(path.relative_to(source))] = {"beforeSHA256": digest(path)}
    tag_macro.write_text('macro(GIT_FETCH_TAGS repo_path)\n'
                         '    message(STATUS "Pinned archive source: ${repo_path}; no tag fetch")\n'
                         'endmacro()\n')
    tag = inputs["x265SourceTag"]
    if not re.fullmatch(r"\d+\.\d+(?:\.\d+)?", tag):
        raise ValueError("Invalid retained x265 release tag")
    version.write_text("repositorychangeset: " + COMMITS["x265_git"][:12] +
                       "\nreleasetagdistance: 0\nreleasetag: " + tag + "\n")
    for path in [tag_macro, version]:
        patches[str(path.relative_to(source))]["afterSHA256"] = digest(path)
    configuration = inputs["configuration"]
    if configuration[:2] != ["cmake", "-S"] or configuration[3] != "-B":
        raise ValueError("Unexpected retained codec build command")
    old_source, old_output = configuration[2], str(Path(configuration[4]).parent)
    command = [arg.replace(old_source, str(source)).replace(old_output, str(output)) for arg in configuration]
    prefix = output / "prefix"
    pc = prefix / "lib/pkgconfig/x265.pc"
    pc.parent.mkdir(parents=True)
    pc.write_text("Name: x265\nDescription: Pinned archive-built x265 dependency\nVersion: " + tag +
                  "\nLibs: -L" + str(prefix / "lib") + " -lx265\nLibs.private: -lc++ -lm\nCflags: -I" +
                  str(prefix / "include") + "\n")
    environment = dict(os.environ)
    for key in list(environment):
        if key.startswith(("DYLD_", "OPENSSL_")) or key in {
            "CC", "CXX", "CFLAGS", "CXXFLAGS", "CPPFLAGS", "LDFLAGS", "SDKROOT",
            "CMAKE_PREFIX_PATH", "PKG_CONFIG_PATH", "PKG_CONFIG_LIBDIR"}:
            environment.pop(key)
    environment.update(SDKROOT=sdk, MACOSX_DEPLOYMENT_TARGET="26.0", PKG_CONFIG_PATH="",
                       PKG_CONFIG_LIBDIR=str(pc.parent), LDFLAGS=inputs["linkerFlags"],
                       CPM_SOURCE_CACHE=str(output / "cpm-cache"))
    record = {"sourceManifestSHA256": manifest_sha, "sourceArchiveSHA256": manifest["archiveSHA256"],
              "builderSHA256": builder_sha, "archiveAdaptations": patches, "configuration": command,
              "codecCommits": COMMITS, "retainedCodecRecordSHA256": digest(payload / "build-records/codecs.json")}
    (output / "source-inputs.json").write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    print("Configuring codecs from the verified source archive", flush=True)
    run(command, output, "configure", environment)
    print("Building all seven codec libraries", flush=True)
    run(["cmake", "--build", output / "build", "-j4"], output, "build", environment)
    run(["cmake", "--install", output / "build"], output, "install", environment)
    versions = {}
    for name in LIBRARIES:
        path = prefix / "lib" / name
        commands = capture("xcrun", "otool", "-l", path)
        found = re.findall(r"\bminos\s+(\d+\.\d+(?:\.\d+)?)", commands)
        found += re.findall(r"cmd LC_VERSION_MIN_MACOSX\s+cmdsize \d+\s+version (\d+\.\d+(?:\.\d+)?)", commands)
        if not found or any(tuple(map(int, item.split("."))) > (26, 0, 0) for item in found):
            raise ValueError("Invalid codec deployment target: " + name)
        versions[name] = sorted(set(found))
    if files(payload) != manifest["files"] or digest(Path(__file__)) != builder_sha:
        raise ValueError("Source packet or builder changed during rebuild")
    report = {"profile": "maccompanion.native-source-codec-rebuild.v1", "inputs": record,
              "sourceBuilt": True, "sourcePayloadUnchanged": True, "deploymentVersions": versions,
              "files": files(prefix), "correspondingSourceComplete": False, "releaseAdmitted": False,
              "videoAcceptanceVerified": False, "bitIdenticalReproductionClaimed": False}
    (output / "rebuild-report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"passed": True, "sourceBuiltCodecLibraries": len(LIBRARIES), "releaseAdmitted": False}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-inputs", required=True, type=Path)
    parser.add_argument("--manifest-sha256", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    build(args.source_inputs.resolve(), args.manifest_sha256, args.output.resolve())
