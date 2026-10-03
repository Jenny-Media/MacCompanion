#!/usr/bin/env python3
"""Fetch, verify and build pinned streaming references outside release targets."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path
import subprocess
import tarfile
import urllib.request

HERE = Path(__file__).resolve().parent
LOCK = json.loads((HERE / "source-lock.json").read_text())
MAC_SUBMODULES = [
    "third-party/build-deps", "third-party/libvirtualhid",
    "third-party/lizardbyte-common", "third-party/moonlight-common-c",
    "third-party/Simple-Web-Server", "third-party/TPCircularBuffer",
    "third-party/libdisplaydevice",
]
MAC_VERIFIED_SUBMODULES = MAC_SUBMODULES + ["third-party/moonlight-common-c/enet"]


def run(*args, cwd=None, log=None):
    if log:
        log.parent.mkdir(parents=True, exist_ok=True)
        with log.open("w") as output:
            subprocess.run(args, cwd=cwd, stdout=output,
                           stderr=subprocess.STDOUT, check=True)
    else:
        subprocess.run(args, cwd=cwd, check=True)


def git(path, *args):
    return subprocess.check_output(["git", "-C", str(path), *args], text=True).strip()


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def native_source_inputs():
    """Content-bound first-party candidate inputs, excluding private state."""
    repository = HERE.parents[1]
    files = {}
    for directory in [HERE, repository / "Native/Client", repository / "Native/Host", repository / "Packages/MacCompanionKit/Sources"]:
        for path in sorted(directory.rglob("*")):
            if path.is_file() and path.suffix in {".swift", ".c", ".h", ".m", ".py", ".patch", ".json", ".template"}:
                files[str(path.relative_to(repository))] = digest(path)
    for relative in ["Native/Host/companion-supervisor.c", "Packages/MacCompanionKit/Package.swift",
                     "spec/interactive-control/v0/native-video-lifecycle.md",
                     "spec/interactive-control/v0/native-input-posting.md",
                     "spec/fixtures/valid/native-input-posting.json",
                     "spec/interactive-control/v0/native-client-launch.md",
                     "spec/interactive-control/v0/native-presentation-geometry.md",
                     "spec/fixtures/valid/native-video-content-geometry.json",
                     "spec/fixtures/valid/native-backend-capture-evidence.json",
                     "spec/capability-protocol/v0/managed-native-host.md",
                     "spec/capability-protocol/v0/simulator-native-development.md",
                     "spec/fixtures/valid/normal-native-simulator-development.json",
                     "spec/capability-protocol/v0/local-native-runtime-snapshot.md",
                     "spec/capability-protocol/v0/local-native-backend.md",
                     "spec/capability-protocol/v0/native-stream-continuity.md",
                     "spec/fixtures/native-stream-continuity-v0.1.json",
                     "spec/fixtures/local-xpc-native-backend-v0.1.json",
                     "spec/fixtures/local-xpc-native-runtime-snapshot-v0.1.json",
                     "spec/fixtures/valid/managed-native-host-admission.json",
                     "spec/fixtures/valid/native-client-launch-admission.json",
                     "spec/capability-protocol/v0/native-video-enrollment-signing.md",
                     "spec/capability-protocol/v0/native-video-primary-messages.md",
                     "spec/fixtures/valid/native-video-enroll-request.json",
                     "spec/fixtures/valid/native-video-enroll-challenge.json",
                     "spec/fixtures/valid/native-video-enroll-proof.json",
                     "spec/fixtures/valid/native-video-ready.json",
                     "spec/fixtures/valid/native-video-present-request.json",
                     "spec/fixtures/valid/native-video-present-receipt.json",
                     "spec/fixtures/valid/native-video-cancel.json",
                     "spec/fixtures/valid/native-video-cancelled.json",
                     "spec/fixtures/manifest.json", "spec/fixtures/valid/native-video-lifecycle.json",
                     "spec/fixtures/valid/native-video-enrollment-admission.json",
                     "spec/fixtures/crypto/native-video-enrollment-v0.1.json",
                     "spec/fixtures/crypto/native-video-enrollment-coordinator-v0.1.json"]:
        files[relative] = digest(repository / relative)
    canonical = json.dumps(files, sort_keys=True, separators=(",", ":")).encode()
    return files, hashlib.sha256(canonical).hexdigest()


def normalized_diff(data):
    return sorted(b"diff --git " + section for section in data.split(b"diff --git ")[1:])


def verify_source(root, name):
    expected = LOCK["sources"][name]
    path = root / "upstream" / name
    if git(path, "rev-parse", "HEAD") != expected["revision"]:
        raise ValueError(f"{name}: source revision changed")
    # Check each gitlink selected for this platform, including nested links.
    selected = (MAC_VERIFIED_SUBMODULES if name == "Sunshine" else
                list(expected["submodules"]))
    for submodule in selected:
        revision = expected["submodules"][submodule]
        if git(path / submodule, "rev-parse", "HEAD") != revision:
            raise ValueError(f"{name}: submodule revision changed: {submodule}")
        if git(path / submodule, "diff", "HEAD", "--"):
            raise ValueError(f"{name}: modified submodule: {submodule}")
        if git(path / submodule, "ls-files", "--others", "--exclude-standard"):
            raise ValueError(f"{name}: untracked submodule files: {submodule}")
    for relative, checksum in expected["vendored_artifacts_sha256"].items():
        if digest(path / relative) != checksum:
            raise ValueError(f"{name}: vendored artifact changed: {relative}")
    for relative, checksum in expected["license_files_sha256"].items():
        if digest(path / relative) != checksum:
            raise ValueError(f"{name}: upstream license changed: {relative}")
    patches = [(HERE / "patches" / filename, item)
               for filename, item in LOCK["patches"].items()
               if item["source"] == name]
    # Compare the complete tracked diff to the admitted local patch. Reject
    # unrelated edits rather than resetting a caller's source checkout.
    expected_diff = b"".join(p.read_bytes() for p, _ in patches)
    for patch, item in patches:
        if digest(patch) != item["sha256"]:
            raise ValueError(f"Local patch changed: {patch.name}")
    actual = subprocess.check_output(["git", "diff", "HEAD", "--"], cwd=path)
    if normalized_diff(actual) != normalized_diff(expected_diff):
        raise ValueError(f"{name}: unexpected source modifications")
    if git(path, "ls-files", "--others", "--exclude-standard"):
        raise ValueError(f"{name}: unexpected untracked source files")
    return path


def fetch(root, name):
    item = LOCK["sources"][name]
    path = root / "upstream" / name
    if not path.exists():
        path.mkdir(parents=True)
        run("git", "init", str(path))
        run("git", "remote", "add", "origin", item["url"], cwd=path)
        run("git", "fetch", "--depth", "1", "origin", item["revision"], cwd=path)
        run("git", "checkout", "--detach", "FETCH_HEAD", cwd=path)
    if git(path, "rev-parse", "HEAD") != item["revision"]:
        raise ValueError(f"Refusing to alter an existing {name} checkout")
    if name == "Sunshine":
        run("git", "submodule", "update", "--init", "--depth", "1",
            *MAC_SUBMODULES, cwd=path)
        run("git", "submodule", "update", "--init", "--depth", "1", "enet",
            cwd=path / "third-party/moonlight-common-c")
    else:
        run("git", "submodule", "update", "--init", "--recursive", "--depth", "1", cwd=path)
    for filename, patch in LOCK["patches"].items():
        if patch["source"] != name:
            continue
        patch_path = HERE / "patches" / filename
        if digest(patch_path) != patch["sha256"]:
            raise ValueError("Local patch checksum mismatch")
        applied = subprocess.run(["git", "apply", "--reverse", "--check", str(patch_path)],
                                 cwd=path, capture_output=True).returncode == 0
        if not applied:
            run("git", "apply", "--check", str(patch_path), cwd=path)
            run("git", "apply", str(patch_path), cwd=path)
    verify_source(root, name)


def mac(root):
    source = verify_source(root, "Sunshine")
    artifact = LOCK["downloads"]["macos_ffmpeg"]
    archive = root / "ffmpeg.tar.gz"
    if not archive.exists():
        partial = archive.with_suffix(".download")
        urllib.request.urlretrieve(artifact["url"], partial)
        if digest(partial) != artifact["sha256"]:
            raise ValueError("FFmpeg download checksum mismatch")
        partial.replace(archive)
    if digest(archive) != artifact["sha256"]:
        raise ValueError("FFmpeg archive checksum mismatch")
    dependencies = root / "deps"
    dependencies.mkdir(exist_ok=True)
    with tarfile.open(archive) as stream:
        stream.extractall(dependencies, filter="data")
    build = source / "cmake-build-maccompanion-reference"
    run("cmake", "-S", str(source), "-B", str(build),
        "-DCMAKE_BUILD_TYPE=Release", "-DBUILD_DOCS=OFF", "-DBUILD_TESTS=OFF",
        "-DSUNSHINE_ENABLE_TRAY=OFF", "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
        "-DCMAKE_PREFIX_PATH=/opt/homebrew/opt/openssl@3;/opt/homebrew/opt/opus;/opt/homebrew/opt/icu4c@78;/opt/homebrew",
        f"-DFFMPEG_PREPARED_BINARIES={dependencies / 'ffmpeg'}",
        log=root / "logs/mac-configure.log")
    run("cmake", "--build", str(build), "-j", "8", log=root / "logs/mac-build.log")
    binary = build / "Sunshine.app/Contents/MacOS/Sunshine"
    run(str(binary), "--help", log=root / "logs/mac-help.log")
    return {"binary": str(binary), "sha256": digest(binary)}


def ios(root, embedded=False):
    source = verify_source(root, "moonlight-ios")
    extra = []
    if embedded:
        run("python3", str(HERE / "engine_build.py"), "--root", str(root), "--sdk", "iphonesimulator", "--reference-probe")
        framework_directory = root / "embedded-engine/DerivedData/Build/Products/Debug-iphonesimulator"
        extra = [f"FRAMEWORK_SEARCH_PATHS=$(inherited) {framework_directory}",
                 "OTHER_LDFLAGS=$(inherited) -framework CompanionMoonlightEngine -framework CompanionMoonlightAdapter",
                 "GCC_PREPROCESSOR_DEFINITIONS=$(inherited) MACCOMPANION_REFERENCE_EMBEDDED_ENGINE=1",
                 "LD_RUNPATH_SEARCH_PATHS=$(inherited) @executable_path/Frameworks"]
    run("xcodebuild", "-project", str(source / "Moonlight.xcodeproj"),
        "-scheme", "Moonlight", "-configuration", "Debug", "-sdk", "iphonesimulator",
        "-destination", "generic/platform=iOS Simulator",
        "-derivedDataPath", str(root / "build/ios-reference"),
        "-disableAutomaticPackageResolution", "-onlyUsePackageVersionsFromResolvedFile",
        "IPHONEOS_DEPLOYMENT_TARGET=26.0", "ARCHS=arm64", "ONLY_ACTIVE_ARCH=YES",
        "CODE_SIGNING_ALLOWED=NO", *extra, "build", log=root / "logs/ios-build.log")
    binary = root / "build/ios-reference/Build/Products/Debug-iphonesimulator/Moonlight.app/Moonlight"
    if embedded:
        for name in ["CompanionMoonlightEngine", "CompanionMoonlightAdapter", "OpenSSL"]:
            shutil.copytree(framework_directory / f"{name}.framework",
                            binary.parent / f"Frameworks/{name}.framework", dirs_exist_ok=True)
    return {"binary": str(binary), "sha256": digest(binary)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["fetch", "verify", "mac", "ios", "ios-embedded"])
    parser.add_argument("--root", type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    if args.action == "fetch":
        for name in LOCK["sources"]:
            fetch(root, name)
    elif args.action == "verify":
        for name in LOCK["sources"]:
            verify_source(root, name)
        print("Pinned sources, submodules, artifacts, and patches verified.")
    else:
        result = mac(root) if args.action == "mac" else ios(root, embedded=args.action == "ios-embedded")
        (root / f"{args.action}-build-result.json").write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
