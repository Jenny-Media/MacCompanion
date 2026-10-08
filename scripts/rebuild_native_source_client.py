#!/usr/bin/env python3
"""Rebuild the historical client snapshot with its frozen builder and source SSL.

The frozen builder receives explicit archive verification and already source-built
OpenSSL providers. Neither its source nor Git history is rewritten or fabricated.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

from package_native_host import digest, files
from rebuild_native_source_dependencies import extract, run

RUNNER = r'''
import hashlib, importlib.util, json, pathlib, sys
sys.dont_write_bytecode = True
state = json.loads(pathlib.Path(sys.argv[1]).read_text())
sdk, simulator = sys.argv[2:4]
here = pathlib.Path(state["builder"]).parent
sys.path.insert(0, str(here))
spec = importlib.util.spec_from_file_location("frozen_engine_builder", state["builder"])
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)
def checksum(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()
def archive_source(root, name):
    if name != "moonlight-ios" or pathlib.Path(root).resolve() != pathlib.Path(state["root"]).resolve():
        raise ValueError("Unexpected source request")
    payload = pathlib.Path(state["payload"])
    for relative, expected in state["upstreamFiles"].items():
        path = payload / relative
        if "sha256" in expected and checksum(path) != expected["sha256"]:
            raise ValueError("Archived client source changed: " + relative)
        if "symlink" in expected and (not path.is_symlink() or str(path.readlink()) != expected["symlink"]):
            raise ValueError("Archived source link changed")
    return payload / "upstream/moonlight-ios"
def source_openssl(root):
    if pathlib.Path(root).resolve() != pathlib.Path(state["root"]).resolve():
        raise ValueError("Unexpected dependency request")
    for path, expected in state["opensslFiles"].items():
        if checksum(path) != expected:
            raise ValueError("Rebuilt client OpenSSL changed")
    return pathlib.Path(state["opensslXCFramework"])
engine.verify_source = archive_source
engine.build_openssl = source_openssl
sys.argv = [state["builder"], "--root", state["root"], "--sdk", sdk]
if simulator:
    sys.argv += ["--test-simulator", simulator]
engine.main()
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-inputs", type=Path, required=True)
    parser.add_argument("--manifest-sha256", required=True)
    parser.add_argument("--dependency-rebuild", type=Path, required=True)
    parser.add_argument("--dependency-report-sha256", required=True)
    parser.add_argument("--test-simulator", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    dependency = args.dependency_rebuild.resolve()
    report_path = dependency / "rebuild-report.json"
    if digest(report_path) != args.dependency_report_sha256:
        raise ValueError("Different selected dependency rebuild")
    dependency_record = json.loads(report_path.read_text())
    if (dependency_record["sourceManifestSHA256"] != args.manifest_sha256 or
            not dependency_record["bothClientOpenSSLSourceRebuilt"] or dependency_record["releaseAdmitted"]):
        raise ValueError("Different client dependency source packet")
    output = args.output.resolve()
    builder_sha = digest(Path(__file__))
    manifest, payload = extract(args.source_inputs.resolve(), args.manifest_sha256, output)
    here = payload / "workspace/Experiments/SunshineMoonlightIntegration"
    lock = json.loads((here / "source-lock.json").read_text())
    upstream = lock["sources"]["moonlight-ios"]
    if manifest["components"]["moonlight-ios"]["revision"] != upstream["revision"]:
        raise ValueError("Client source revision mismatch")
    # Omitted prebuilt FFmpeg/SDL/Opus libraries are outside the video-only
    # profile. Every source component actually consumed by it must be complete.
    for relative in ["moonlight-common/moonlight-common-c", "moonlight-common/moonlight-common-c/enet"]:
        component = manifest["components"]["moonlight-ios/" + relative]
        if component["revision"] != upstream["submodules"][relative] or component["excludedFiles"]:
            raise ValueError("Incomplete native client source component")
    retained = {sdk: json.loads((payload / ("build-records/client-engine-" + sdk + ".json")).read_text())
                for sdk in ["iphoneos", "iphonesimulator"]}
    if any(record["sourceInputSHA256"] != manifest["nativeSourceInputSHA256"] or
           record["sourceLockSHA256"] != digest(here / "source-lock.json") for record in retained.values()):
        raise ValueError("Retained client build binding mismatch")
    openssl = dependency / "client-native-root/source-openssl"
    openssl_files = {}
    openssl_records = {}
    for sdk in ["iphoneos", "iphonesimulator"]:
        path = openssl / (sdk + "-provenance.json")
        binding = dependency_record["buildRecords"]["client-openssl-" + sdk]
        if digest(path) != binding["recordSHA256"]:
            raise ValueError("Client OpenSSL provenance changed")
        record = json.loads(path.read_text())
        framework = openssl / sdk / "OpenSSL.framework"
        actual = {str(p.relative_to(framework)): digest(p) for p in framework.rglob("*") if p.is_file()}
        if actual != record["files"] or record["inputs"]["source"]["sha256"] != lock["downloads"]["ios_openssl_source"]["sha256"]:
            raise ValueError("Client OpenSSL artifact changed")
        slice_name = "ios-arm64" if sdk == "iphoneos" else "ios-arm64-simulator"
        copied = openssl / "OpenSSL.xcframework" / slice_name / "OpenSSL.framework"
        if {str(p.relative_to(copied)): digest(p) for p in copied.rglob("*") if p.is_file()} != record["files"]:
            raise ValueError("XCFramework slice differs from the pinned source-built OpenSSL")
        openssl_records[sdk] = digest(path)
        openssl_files.update({str(p): digest(p) for p in framework.rglob("*") if p.is_file()})
    xcframework = openssl / "OpenSSL.xcframework"
    openssl_files.update({str(p): digest(p) for p in xcframework.rglob("*") if p.is_file()})
    root = output / "client-native-root"
    root.mkdir()
    state = {"builder": str(here / "engine_build.py"), "payload": str(payload), "root": str(root),
             "upstreamFiles": {k: v for k, v in manifest["files"].items() if k.startswith("upstream/moonlight-ios/")},
             "opensslFiles": openssl_files, "opensslXCFramework": str(xcframework)}
    state_path = output / "build-state.json"
    state_path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
    runner = output / "run_frozen_builder.py"
    runner.write_text(RUNNER)
    runner_sha = digest(runner)
    environment = {k: v for k, v in os.environ.items() if not k.startswith(("DYLD_", "OPENSSL_"))}
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    environment["MACCOMPANION_DISABLE_SWIFTPM_SANDBOX"] = "1"
    records = {}
    for sdk in ["iphoneos", "iphonesimulator"]:
        print("Rebuilding frozen client snapshot: " + sdk, flush=True)
        run([sys.executable, runner, state_path, sdk, args.test_simulator if sdk == "iphonesimulator" else ""],
            output, "client-" + sdk, environment)
        provenance = root / "embedded-engine" / ("provenance-" + sdk + ".json")
        record = json.loads(provenance.read_text())
        if record["sourceInputSHA256"] != manifest["nativeSourceInputSHA256"]:
            raise ValueError("Frozen first-party source digest changed")
        products = root / "embedded-engine/DerivedData/Build/Products" / ("Debug-" + sdk)
        for name, checksum in record["binarySHA256"].items():
            if digest(products / (name + ".framework") / name) != checksum:
                raise ValueError("Rebuilt framework changed")
        records[sdk] = {"provenanceSHA256": digest(provenance), "binarySHA256": record["binarySHA256"]}
    if (files(payload) != manifest["files"] or digest(Path(__file__)) != builder_sha or
            digest(runner) != runner_sha or digest(report_path) != args.dependency_report_sha256 or
            any(digest(Path(p)) != checksum for p, checksum in openssl_files.items())):
        raise ValueError("Rebuild inputs changed")
    report = {"profile": "maccompanion.native-source-client-rebuild.v1", "sourceManifestSHA256": args.manifest_sha256,
              "sourceArchiveSHA256": manifest["archiveSHA256"], "nativeSourceInputSHA256": manifest["nativeSourceInputSHA256"],
              "builderSHA256": builder_sha, "frozenEngineBuilderSHA256": digest(here / "engine_build.py"),
              "runnerSHA256": runner_sha, "dependencyReportSHA256": args.dependency_report_sha256,
              "opensslProvenanceSHA256": openssl_records, "sdkBuildRecords": records,
              "bothClientSDKsRebuilt": True, "simulatorComponentTestsPassed": True,
              "opensslSlicesBoundToSourceBuilds": True,
              "simulatorID": args.test_simulator, "sourcePayloadUnchanged": True,
              "historicalReferenceProbeIncluded": True, "currentNormalCandidateAdmission": False,
              "correspondingSourceComplete": False, "releaseAdmitted": False,
              "videoAcceptanceVerified": False, "bitIdenticalReproductionClaimed": False}
    (output / "rebuild-report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"passed": True, "rebuiltSDKFrameworks": 6, "releaseAdmitted": False}))


if __name__ == "__main__":
    main()
