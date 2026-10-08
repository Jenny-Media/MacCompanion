#!/usr/bin/env python3
"""Retain verified native candidate source inputs without credentials or binaries."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile

from package_native_host import digest, files, verify as verify_package
from package_source_native_host import source_records
from build_native_host_dependencies import LOCK as DEPENDENCIES

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Experiments/SunshineMoonlightIntegration"))
from reference_build import LOCK, verify_source, native_source_inputs

PROFILE = "maccompanion.native-candidate-source-inputs.v1"
PREFIXES = ("Native/", "Apps/", "Packages/", "Tests/", "scripts/", "spec/", "LICENSES/",
            "docs/", ".github/",
            "MacCompanion.xcodeproj/", "Experiments/SunshineMoonlightIntegration/",
            "Experiments/LiveControlLab/", "Experiments/ClientUIHarness/",
            "Experiments/NormalNativeSimulatorQA/")
ROOT_FILES = {"LICENSE", "LICENSING.md", "NOTICE", "README.md", "SECURITY.md",
              "TRADEMARKS.md", "CONTRIBUTING.md", "project.yml", ".gitignore"}
PRIVATE_EXTENSIONS = {".pem", ".p12", ".pfx", ".cer", ".crt", ".key", ".mobileprovision", ".provisionprofile"}
BINARY_EXTENSIONS = {".a", ".dylib", ".so", ".dll", ".exe", ".o", ".pyc", ".node"}


def capture(path, *args):
    return subprocess.check_output(["git", "-C", str(path), *args])


def omitted(path):
    if path.suffix.lower() in PRIVATE_EXTENSIONS:
        return "credential/certificate-shaped file excluded"
    if path.suffix.lower() in BINARY_EXTENSIONS or any(p.endswith((".framework", ".xcframework")) for p in path.parts):
        return "prebuilt binary excluded"
    return None


def copy_file(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    if source.is_symlink():
        link = os.readlink(source)
        if Path(link).is_absolute():
            raise ValueError("Absolute source symlink: " + str(source))
        target.symlink_to(link)
    else:
        with source.open("rb") as stream:
            magic = stream.read(4)
        if magic in {b"\x7fELF", b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbe"}:
            raise ValueError("Unindexed executable binary: " + str(source))
        shutil.copyfile(source, target)
        target.chmod(0o755 if source.stat().st_mode & 0o111 else 0o644)


def git_tree(source, target, expected_revision, allow_patch=False):
    if capture(source, "rev-parse", "HEAD").decode().strip() != expected_revision:
        raise ValueError("Source revision changed: " + str(source))
    if not allow_patch and capture(source, "diff", "HEAD", "--"):
        raise ValueError("Source modifications: " + str(source))
    if capture(source, "ls-files", "--others", "--exclude-standard"):
        raise ValueError("Untracked upstream source: " + str(source))
    exclusions = {}
    for entry in capture(source, "ls-files", "--stage", "-z").split(b"\0"):
        if not entry:
            continue
        metadata, filename = entry.split(b"\t", 1)
        if metadata.split()[0] == b"160000":
            continue
        relative = Path(os.fsdecode(filename))
        path = source / relative
        if path.is_dir():  # Gitlinks are exported independently at their pins.
            continue
        reason = omitted(relative)
        if reason:
            exclusions[str(relative)] = reason
            continue
        copy_file(path, target / relative)
    # Retain the exact admitted local changes and base commit as build evidence.
    return {"revision": expected_revision, "trackedDiffSHA256": hashlib.sha256(capture(source, "diff", "HEAD", "--")).hexdigest(),
            "excludedFiles": exclusions}


def verify(output):
    manifest = json.loads((output / "source-inputs.json").read_text())
    if (manifest["profile"] != PROFILE or manifest["releaseAdmitted"]
            or manifest["correspondingSourceComplete"] or manifest["builderSHA256"] != digest(Path(__file__))):
        raise ValueError("Invalid candidate source input profile")
    payload = output / "payload"
    if files(payload) != manifest["files"]:
        raise ValueError("Source payload changed")
    archive = output / "native-source-inputs.tar.gz"
    if digest(archive) != manifest["archiveSHA256"]:
        raise ValueError("Source input archive changed")
    actual = {}
    with tarfile.open(archive) as stream:
        for member in stream:
            if member.name in actual or member.name.startswith("/") or ".." in Path(member.name).parts:
                raise ValueError("Invalid source archive path")
            if member.issym():
                actual[member.name] = {"symlink": member.linkname}
            elif member.isfile():
                actual[member.name] = {"sha256": hashlib.sha256(stream.extractfile(member).read()).hexdigest()}
            else:
                raise ValueError("Unexpected source archive entry")
    if actual != manifest["files"]:
        raise ValueError("Source archive differs from verified payload")
    return manifest


def build(native_root, host_root, package, output):
    package_record = verify_package(package)
    package_sha = digest(package / "host-package.json")
    host_record, records, prefixes = source_records(host_root)
    if package_record["sourceHostSHA256"] != host_record["binarySHA256"]:
        raise ValueError("Source archive and packaged host differ")
    source_inputs, source_sha = native_source_inputs()
    subprocess.run([sys.executable, ROOT / "Experiments/SunshineMoonlightIntegration/candidate_inventory.py",
                    "--root", native_root], check=True, stdout=subprocess.DEVNULL)
    client_inventory_path = native_root / "native-video-candidate-inventory.json"
    client_inventory = json.loads(client_inventory_path.read_text())
    if client_inventory["sourceInputSHA256"] != source_sha or sum(map(len, client_inventory["artifacts"].values())) != 6:
        raise ValueError("Missing exact iPhone and Simulator framework evidence")
    client_inventory_sha = digest(client_inventory_path)
    output.mkdir(parents=True, exist_ok=False)
    payload = output / "payload"
    payload.mkdir()
    components = {}
    for name in ["Sunshine", "moonlight-ios"]:
        source = verify_source(native_root, name)
        destination = payload / "upstream" / name
        components[name] = git_tree(source, destination, LOCK["sources"][name]["revision"], allow_patch=True)
        for relative, revision in LOCK["sources"][name]["submodules"].items():
            path = source / relative
            if not (path / ".git").exists():
                continue
            components[name + "/" + relative] = git_tree(path, destination / relative, revision)
    first_party = capture(ROOT, "ls-files", "--cached", "--others", "--exclude-standard", "-z")
    for entry in sorted(set(first_party.split(b"\0"))):
        if not entry:
            continue
        relative = Path(os.fsdecode(entry))
        if str(relative) not in ROOT_FILES and not str(relative).startswith(PREFIXES):
            continue
        if str(relative).startswith("docs/") and relative.suffix not in {".md", ".json", ".txt", ".plist"}:
            continue
        if omitted(relative):
            raise ValueError("Unexpected binary or private material in first-party source: " + str(relative))
        if not (ROOT / relative).exists() and not (ROOT / relative).is_symlink():
            continue
        copy_file(ROOT / relative, payload / "workspace" / relative)
    for relative, checksum in source_inputs.items():
        if digest(payload / "workspace" / relative) != checksum:
            raise ValueError("Missing current first-party native source: " + relative)
    archives = {}
    for name, entry in DEPENDENCIES["sources"].items():
        original = Path(host_record["inputs"]["dependencyRecords"][name]["path"]).parent / "archives" / (name + ".tar.gz")
        if digest(original) != entry["sha256"]:
            raise ValueError("Source archive changed: " + name)
        target = payload / "archives" / (name + ".tar.gz")
        copy_file(original, target)
        archives[name] = {"path": str(target.relative_to(payload)), **entry}
    for name, original in {
        "boost": host_root / "build/_deps/boost-subbuild/boost-populate-prefix/src/boost-1.89.0-cmake.tar.xz",
        "nlohmann_json": host_root / "build/_deps/json-subbuild/json-populate-prefix/src/json.tar.xz",
    }.items():
        expected = LOCK["downloads"][name]
        if digest(original) != expected["sha256"]:
            raise ValueError("Fetched source archive changed: " + name)
        target = payload / "archives" / (name + ".tar.xz")
        copy_file(original, target)
        archives[name] = {"path": str(target.relative_to(payload)), **expected}
    evidence = payload / "build-records"
    evidence.mkdir()
    for name, record in {**records, "host": host_record, "package": package_record}.items():
        (evidence / (name + ".json")).write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    shutil.copyfile(client_inventory_path, evidence / "client-candidate-inventory.json")
    for sdk in ["iphoneos", "iphonesimulator"]:
        shutil.copyfile(native_root / "embedded-engine" / ("provenance-" + sdk + ".json"), evidence / ("client-engine-" + sdk + ".json"))
        shutil.copyfile(native_root / "source-openssl" / (sdk + "-provenance.json"), evidence / ("client-openssl-" + sdk + ".json"))
    (payload / "BUILDING.md").write_text(
        "# Native candidate source inputs\n\n"
        "This snapshot binds the tested development host package and current client source inputs.\n"
        "Source trees contain admitted local changes; workspace/Experiments/SunshineMoonlightIntegration/patches retains patch files.\n"
        "Upstream component revisions and excluded unused binaries are in the outer source-inputs.json manifest.\n"
        "Runtime archives include the shared Mac/iOS OpenSSL source. Codec sources are under Sunshine/third-party/build-deps.\n"
        "Build and package scripts are under workspace/scripts; client engine scripts are under workspace/Experiments/SunshineMoonlightIntegration.\n\n"
        "Offline reconstruction and source-to-candidate rebuild verification remain pending.\n"
        "The original builders currently require Git checkouts and validate unused vendored binaries omitted here.\n"
        "The Sunshine Web UI also needs its pinned npm dependency sources. This snapshot does not claim complete GPL corresponding source or release admission.\n"
    )
    # Recheck mutable source/build inputs after collecting the snapshot.
    for component, expected in components.items():
        source = native_root / "upstream" / component
        if (capture(source, "rev-parse", "HEAD").decode().strip() != expected["revision"]
                or hashlib.sha256(capture(source, "diff", "HEAD", "--")).hexdigest() != expected["trackedDiffSHA256"]
                or capture(source, "ls-files", "--others", "--exclude-standard")):
            raise ValueError("Upstream component changed during source snapshot: " + component)
    source_records(host_root)
    for sdk, artifacts in client_inventory["artifacts"].items():
        product_root = native_root / "embedded-engine/DerivedData/Build/Products" / ("Debug-" + sdk)
        for artifact in artifacts:
            binary = product_root / (artifact["name"] + ".framework") / artifact["name"]
            if digest(binary) != artifact["sha256"]:
                raise ValueError("Client candidate changed during source snapshot")
    if (native_source_inputs()[1] != source_sha or digest(package / "host-package.json") != package_sha
            or digest(client_inventory_path) != client_inventory_sha):
        raise ValueError("Candidate changed during source snapshot")
    inventory = files(payload)
    archive = output / "native-source-inputs.tar.gz"
    with archive.open("xb") as raw, gzip.GzipFile(fileobj=raw, mode="wb", filename="", mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode="w") as stream:
            for relative in inventory:
                path = payload / relative
                info = stream.gettarinfo(path, arcname=relative)
                info.uid = info.gid = info.mtime = 0
                info.uname = info.gname = ""
                if info.isfile():
                    with path.open("rb") as contents:
                        stream.addfile(info, contents)
                else:
                    stream.addfile(info)
    manifest = {"profile": PROFILE, "builderSHA256": digest(Path(__file__)),
                "releaseAdmitted": False, "correspondingSourceComplete": False, "offlineRebuildVerified": False,
                "candidateHostManifestSHA256": package_sha,
                "clientCandidateInventorySHA256": client_inventory_sha,
                "nativeSourceInputSHA256": source_sha, "components": components, "archives": archives,
                "files": inventory, "archiveSHA256": digest(archive),
                "remaining": ["Offline reconstruction and rebuild verification", "Sunshine Web UI transitive npm source closure",
                              "Permanent dependency and process/TCC admission"]}
    (output / "source-inputs.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return verify(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native-root", type=Path)
    parser.add_argument("--host-root", type=Path)
    parser.add_argument("--host-package", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    if args.verify:
        record = verify(args.output.resolve())
    else:
        if None in [args.native_root, args.host_root, args.host_package]:
            parser.error("construction requires --native-root, --host-root and --host-package")
        record = build(args.native_root.resolve(), args.host_root.resolve(), args.host_package.resolve(), args.output.resolve())
    print(json.dumps({"verified": True, "sourceComponents": len(record["components"]), "files": len(record["files"]),
                      "archiveSHA256": record["archiveSHA256"], "correspondingSourceComplete": False}))
