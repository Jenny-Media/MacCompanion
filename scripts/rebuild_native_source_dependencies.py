#!/usr/bin/env python3
"""Rebuild Mac runtime and iOS OpenSSL dependencies from pinned source inputs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile

from package_native_host import digest, files
from package_native_sources import PROFILE


def extract(source_inputs, manifest_sha, output):
    manifest_path = source_inputs / "source-inputs.json"
    if digest(manifest_path) != manifest_sha:
        raise ValueError("Source manifest differs from the requested candidate")
    manifest = json.loads(manifest_path.read_text())
    if manifest["profile"] != PROFILE or manifest["releaseAdmitted"] or manifest["correspondingSourceComplete"]:
        raise ValueError("Not a development source input snapshot")
    archive = source_inputs / "native-source-inputs.tar.gz"
    if digest(archive) != manifest["archiveSHA256"]:
        raise ValueError("Source input archive changed")
    output.mkdir(parents=True, exist_ok=False)
    payload = output / "payload"
    payload.mkdir()
    with tarfile.open(archive) as stream:
        observed = {}
        for member in stream:
            if member.name in observed or member.name.startswith("/") or ".." in Path(member.name).parts:
                raise ValueError("Invalid source archive path")
            if member.isfile():
                observed[member.name] = {"sha256": hashlib.sha256(stream.extractfile(member).read()).hexdigest()}
            elif member.issym():
                observed[member.name] = {"symlink": member.linkname}
            else:
                raise ValueError("Unexpected source archive entry")
        if observed != manifest["files"]:
            raise ValueError("Source archive differs from the bound manifest")
        stream.extractall(payload, filter="data")
    if files(payload) != manifest["files"]:
        raise ValueError("Extracted source payload changed")
    return manifest, payload


def run(command, output, name, environment):
    with (output / (name + ".log")).open("w") as log:
        subprocess.run([str(a) for a in command], env=environment, stdout=log,
                       stderr=subprocess.STDOUT, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-inputs", type=Path, required=True)
    parser.add_argument("--manifest-sha256", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    manifest, payload = extract(args.source_inputs.resolve(), args.manifest_sha256, output)
    workspace = payload / "workspace"
    environment = dict(os.environ)
    # Do not pass developer provider/search overrides into reconstructed builds.
    for key in list(environment):
        if key.startswith(("DYLD_", "OPENSSL_")):
            environment.pop(key)
    mac = output / "mac-runtime"
    archives = mac / "archives"
    archives.mkdir(parents=True)
    for name in ["openssl", "miniupnpc", "opus", "icu"]:
        binding = manifest["archives"][name]
        original = payload / binding["path"]
        if digest(original) != binding["sha256"]:
            raise ValueError("Runtime source archive changed: " + name)
        shutil.copyfile(original, archives / (name + ".tar.gz"))
    print("Rebuilding all four Mac runtime dependencies from extracted sources", flush=True)
    run([sys.executable, workspace / "scripts/build_native_host_dependencies.py", "--root", mac],
        output, "mac-runtime-build", environment)
    # The same verified archive supplies both iPhone and Simulator OpenSSL builds.
    client = output / "client-native-root"
    client_sources = client / "source-openssl"
    client_sources.mkdir(parents=True)
    source_lock = json.loads((workspace / "Experiments/SunshineMoonlightIntegration/source-lock.json").read_text())
    openssl = source_lock["downloads"]["ios_openssl_source"]
    archive = payload / manifest["archives"]["openssl"]["path"]
    if digest(archive) != openssl["sha256"]:
        raise ValueError("Mac and client OpenSSL source differs")
    shutil.copyfile(archive, client_sources / ("openssl-" + openssl["version"] + ".tar.gz"))
    print("Rebuilding iPhone and Simulator OpenSSL from extracted sources", flush=True)
    run([sys.executable, workspace / "Experiments/SunshineMoonlightIntegration/openssl_build.py",
         "--root", client], output, "client-openssl-build", environment)
    build_records = {}
    for name in ["openssl", "miniupnpc", "opus", "icu"]:
        path = mac / (name + "-provenance.json")
        record = json.loads(path.read_text())
        prefix = mac / "prefixes" / name
        actual = {str(p.relative_to(prefix)): digest(p) for p in prefix.rglob("*") if p.is_file()}
        if not record["sourceBuilt"] or actual != record["files"]:
            raise ValueError("Rebuilt Mac dependency changed: " + name)
        build_records[name] = {"recordSHA256": digest(path), "installedFiles": len(actual)}
    for sdk in ["iphoneos", "iphonesimulator"]:
        path = client_sources / (sdk + "-provenance.json")
        record = json.loads(path.read_text())
        framework = client_sources / sdk / "OpenSSL.framework"
        actual = {str(p.relative_to(framework)): digest(p) for p in framework.rglob("*") if p.is_file()}
        if actual != record["files"] or record["inputs"]["source"]["sha256"] != openssl["sha256"]:
            raise ValueError("Rebuilt client OpenSSL changed: " + sdk)
        build_records["client-openssl-" + sdk] = {"recordSHA256": digest(path), "binarySHA256": actual["OpenSSL"]}
    # Generated bytecode is not a change to the retained source payload.
    for path in workspace.rglob("__pycache__"):
        shutil.rmtree(path)
    if files(payload) != manifest["files"]:
        raise ValueError("Source payload changed during dependency rebuild")
    report = {"profile": "maccompanion.native-source-dependency-rebuild.v1",
              "sourceManifestSHA256": args.manifest_sha256,
              "sourceArchiveSHA256": manifest["archiveSHA256"], "builderSHA256": digest(Path(__file__)),
              "macRuntimeSourceRebuilt": True, "bothClientOpenSSLSourceRebuilt": True,
              "sourcePayloadUnchanged": True, "buildRecords": build_records,
              "correspondingSourceComplete": False, "releaseAdmitted": False,
              "remaining": ["Native codec/Sunshine and client engine/adapter rebuild from extracted source",
                            "Git metadata reconstruction and unused-vendor source-only admission",
                            "Sunshine Web UI npm source closure", "Normal-app composition and physical/system-input acceptance"]}
    (output / "rebuild-report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"passed": True, "rebuiltDependencyConfigurations": len(build_records),
                      "correspondingSourceComplete": False}))


if __name__ == "__main__":
    main()
