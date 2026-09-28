#!/usr/bin/env python3
"""Inventory owned development artifacts; never assert release admission."""
import argparse
import json
from pathlib import Path
import subprocess

from reference_build import HERE, LOCK, digest, native_source_inputs, verify_source


def capture(*command):
    return subprocess.check_output(command, text=True).strip()


def macho_dependencies(binary):
    # Universal binaries have one unindented header per architecture. Only
    # indented records are load commands; headers are never dependencies.
    return sorted({line.strip().split(" (compatibility version", 1)[0]
                   for line in capture("xcrun", "otool", "-L", str(binary)).splitlines()
                   if line and line[0].isspace()})


def framework_record(directory, name):
    binary = directory / f"{name}.framework" / name
    if not binary.is_file():
        return None
    dependencies = macho_dependencies(binary)
    # Scan defined and undefined symbols: a statically linked parser would no
    # longer appear in `nm -u`, but still belongs in the dependency inventory.
    symbols = capture("xcrun", "nm", "-a", str(binary))
    if name == "CompanionMoonlightAdapter" and "ReferenceNativeSurfaceProbe" in symbols:
        raise ValueError("Normal native adapter contains a reference-only probe")
    if name == "CompanionMoonlightEngine" and any(
            symbol in symbols for symbol in ["_ff_cbs_", "_ff_isom_write_av1c", "_avio_", "_avcodec_"]):
        raise ValueError("Native H.264/HEVC candidate still references FFmpeg")
    allowed_native = {f"@rpath/{item}.framework/{item}" for item in
                      ["CompanionMoonlightEngine", "CompanionMoonlightAdapter", "OpenSSL"]}
    unresolved = [item for item in dependencies
                  if not item.startswith(("/System/Library/", "/usr/lib/"))
                  and item not in allowed_native]
    if unresolved:
        raise ValueError(f"{name}: untracked native framework dependencies: {unresolved}")
    return {"name": name, "sha256": digest(binary),
            "architectures": capture("xcrun", "lipo", "-archs", str(binary)).split(),
            "dynamicDependencies": dependencies,
            "containsFFmpegParserReferences": False if name == "CompanionMoonlightEngine" else None,
            "releaseAdmitted": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    for name in LOCK["sources"]:
        verify_source(root, name)
    repository = HERE.parents[1]
    first_party, source_input = native_source_inputs()
    # Deliberately exclude raw logs, credentials, signing state, and app data.
    artifacts = {}
    for sdk in ["iphonesimulator", "iphoneos"]:
        directory = root / f"embedded-engine/DerivedData/Build/Products/Debug-{sdk}"
        artifacts[sdk] = []
        for name in ["CompanionMoonlightEngine", "CompanionMoonlightAdapter", "OpenSSL"]:
            record = framework_record(directory, name)
            if record is None:
                raise ValueError(f"{sdk}: missing required candidate framework {name}")
            artifacts[sdk].append(record)
        if artifacts[sdk]:
            provenance = json.loads((root / f"embedded-engine/provenance-{sdk}.json").read_text())
            if provenance.get("referenceProbeIncluded", True) or provenance["sourceInputSHA256"] != source_input:
                raise ValueError(f"{sdk}: artifacts were built from different candidate inputs")
            for record in artifacts[sdk]:
                if provenance["binarySHA256"].get(record["name"]) != record["sha256"]:
                    raise ValueError(f"{sdk}: artifact changed after build")
            openssl = json.loads((root / "source-openssl" / f"{sdk}-provenance.json").read_text())
            if (openssl["inputs"]["source"] != LOCK["downloads"]["ios_openssl_source"]
                    or openssl["inputs"]["builderSHA256"] != digest(HERE / "openssl_build.py")
                    or not openssl["sourceBuilt"]):
                raise ValueError(f"{sdk}: OpenSSL source provenance changed")
            if openssl["files"]["OpenSSL"] != digest(directory / "OpenSSL.framework/OpenSSL"):
                raise ValueError(f"{sdk}: OpenSSL candidate differs from source-built dependency")
    report = {"profile": "maccompanion.native-video-development-inventory.v1",
              "releaseAdmitted": False, "correspondingSourceComplete": False,
              "sourceLockSHA256": digest(HERE / "source-lock.json"),
              "repositoryHEAD": capture("git", "-C", str(repository), "rev-parse", "HEAD"),
              "repositoryDirty": bool(capture("git", "-C", str(repository), "status", "--porcelain")),
              "sourceInputSHA256": source_input,
              "sourceFileSHA256": first_party,
              "upstreamSources": LOCK["sources"], "patches": LOCK["patches"],
              "clientOpenSSLSource": LOCK["downloads"]["ios_openssl_source"],
              "clientOpenSSLSourceBuilt": True,
              "nativeCandidateCodecs": ["H264", "HEVC"], "nativeInputRequiresPresentationAdmission": True, "normalAppNativeInputEnabled": False,
              "artifacts": artifacts,
              "remainingAdmission": ["Complete host/transitive source, build and license inventory",
                  "Managed Sunshine process identity, capture ownership, packaging and TCC evidence",
                  "Normal-app composition of authenticated enrollment, native presentation and input",
                  "Exact signed normal-app artifacts and physical acceptance",
                  "Corresponding-source delivery and distribution review"]}
    host = root / "upstream/Sunshine/cmake-build-maccompanion-reference/Sunshine.app/Contents/MacOS/Sunshine"
    if host.is_file():
        host_dependencies = macho_dependencies(host)
        report["hostArtifact"] = {"sha256": digest(host),
            "architectures": capture("xcrun", "lipo", "-archs", str(host)).split(),
            "dynamicDependencies": host_dependencies,
            "nonSystemDependencies": [value for value in host_dependencies
                                      if not value.startswith(("/System/Library/", "/usr/lib/"))],
            "buildProvenanceComplete": False, "releaseAdmitted": False}
    output = root / "native-video-candidate-inventory.json"
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"inventory": str(output), "releaseAdmitted": False,
                      "nativeFrameworksInventoried": sum(map(len, artifacts.values()))}))


if __name__ == "__main__":
    main()
