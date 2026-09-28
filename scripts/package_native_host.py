#!/usr/bin/env python3
"""Construct and verify a relocatable development host; no release admission."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PINNED_HOST = "c48a6824dea93f0157bc1bcbd3819201da671610895a2c5c7885173c9044582d"


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def command(*args, environment=None):
    try:
        return subprocess.check_output([str(a) for a in args], text=True, stderr=subprocess.STDOUT,
                                       env=environment, timeout=60).strip()
    except subprocess.CalledProcessError as error:
        raise RuntimeError(str(args[0]) + " failed: " + error.output.strip()) from None


def dependencies(binary):
    return [line.strip().split(" (compatibility version", 1)[0]
            for line in command("xcrun", "otool", "-L", binary).splitlines()[1:]
            if line[:1].isspace()]


def system(path):
    return path.startswith(("/System/Library/", "/usr/lib/"))


def dependency_path(original, dependency):
    if dependency.startswith("@loader_path/"):
        return original.parent / dependency.removeprefix("@loader_path/")
    path = Path(dependency)
    if not path.is_absolute():
        raise ValueError("Unsupported source dependency: " + dependency)
    return path


def files(bundle):
    result = {}
    for path in sorted(bundle.rglob("*")):
        if path.is_symlink():
            # No dependency can escape the package through a copied symlink.
            if not path.resolve().is_relative_to(bundle.resolve()):
                raise ValueError("Escaping package symlink: " + str(path))
            result[str(path.relative_to(bundle))] = {"symlink": os.readlink(path)}
        elif path.is_file():
            result[str(path.relative_to(bundle))] = {"sha256": digest(path)}
    return result


def verify(directory):
    report = json.loads((directory / "host-package.json").read_text())
    if report.get("profile") == "maccompanion.source-built-native-host-package.v1":
        from package_source_native_host import verify as verify_source_package
        return verify_source_package(directory)
    bundle = directory / "Sunshine.app"
    if report["profile"] != "maccompanion.native-host-development-package.v1" or report["releaseAdmitted"]:
        raise ValueError("Not a development package")
    if (report["builderSHA256"] != digest(Path(__file__))
            or report["sourceHostSHA256"] != PINNED_HOST
            or report["origins"]["Contents/MacOS/Sunshine"]["sourceSHA256"] != PINNED_HOST
            or set(report["macho"]) != set(report["origins"])):
        raise ValueError("Package construction provenance changed")
    if files(bundle) != report["files"]:
        raise ValueError("Packaged files changed")
    for relative in report["macho"]:
        if Path(relative).is_absolute() or ".." in Path(relative).parts or not relative.startswith("Contents/"):
            raise ValueError("Invalid package binary path")
        binary = bundle / relative
        command("codesign", "--verify", "--strict", binary)
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


def build(root, output):
    source = root / "upstream/Sunshine/cmake-build-maccompanion-reference/Sunshine.app"
    host = source / "Contents/MacOS/Sunshine"
    if digest(host) != PINNED_HOST:
        raise ValueError("Unreviewed host artifact")
    # No overwrite of a caller's existing candidate.
    output.mkdir(parents=True, exist_ok=False)
    bundle = output / "Sunshine.app"
    shutil.copytree(source, bundle, symlinks=True)
    helpers = bundle / "Contents/Helpers"
    helpers.mkdir(exist_ok=True)
    originals = {"Contents/MacOS/Sunshine": host,
                 "Contents/Helpers/openssl": Path("/opt/homebrew/opt/openssl@3/bin/openssl"),
                 "Contents/Helpers/companion-supervisor": root / "managed-host-supervisor"}
    for relative, original in originals.items():
        if relative != "Contents/MacOS/Sunshine":
            shutil.copy2(original, bundle / relative)
    library_sources = {}
    queue = list(originals.values())
    while queue:
        original = queue.pop()
        for dependency in dependencies(original):
            if system(dependency):
                continue
            path = dependency_path(original, dependency)
            if not path.resolve().is_relative_to(Path("/opt/homebrew/Cellar")):
                raise ValueError("Unreviewed dependency location: " + dependency)
            # A dylib's first LC_ID_DYLIB entry refers to itself.
            if path.resolve() == original.resolve():
                continue
            prior = library_sources.get(path.name)
            if prior and prior.resolve() != path.resolve():
                raise ValueError("Conflicting dependency basenames")
            if not prior:
                library_sources[path.name] = path
                queue.append(path)
    frameworks = bundle / "Contents/Frameworks"
    frameworks.mkdir(exist_ok=True)
    for name, original in library_sources.items():
        relative = "Contents/Frameworks/" + name
        shutil.copy2(original, bundle / relative)
        originals[relative] = original
    origins = {}
    for relative, original in originals.items():
        target = bundle / relative
        origins[relative] = {"sourcePath": str(original.resolve()), "sourceSHA256": digest(original)}
        old_dependencies = dependencies(original)
        changes = []
        for old in old_dependencies:
            if system(old) or dependency_path(original, old).resolve() == original.resolve():
                continue
            replacement = bundle / "Contents/Frameworks" / Path(old).name
            changes += ["-change", old, "@loader_path/" + os.path.relpath(replacement, target.parent)]
        if target.suffix == ".dylib":
            changes += ["-id", "@loader_path/" + target.name]
        if changes:
            command("xcrun", "install_name_tool", *changes, target)
        command("codesign", "--force", "--sign", "-", "--timestamp=none", target)
    notices = bundle / "Contents/Resources/DependencyNotices"
    notices.mkdir(parents=True, exist_ok=True)
    shutil.copy2(root / "upstream/Sunshine/LICENSE", notices / "Sunshine-GPL-3.0.txt")
    provenance = {}
    for name, prefix, license_path in [
        ("openssl", Path("/opt/homebrew/opt/openssl@3"), "LICENSE.txt"),
        ("miniupnpc", Path("/opt/homebrew/opt/miniupnpc"), "LICENSE"),
        ("icu", Path("/opt/homebrew/opt/icu4c@78"), "share/icu/78.3/LICENSE"),
    ]:
        formula = next((prefix / ".brew").glob("*.rb"))
        shutil.copy2(prefix / license_path, notices / (name + "-LICENSE.txt"))
        shutil.copy2(formula, notices / (name + "-installed-formula.rb"))
        provenance[name] = {"receiptSHA256": digest(prefix / "INSTALL_RECEIPT.json"),
                            "formulaSHA256": digest(formula),
                            "licenseSHA256": digest(prefix / license_path)}
    # Use a package-owned empty configuration for certificate operations.
    (notices / "openssl.cnf").write_text("# Development enrollment uses explicit command options.\n")
    command("codesign", "--force", "--sign", "-", "--timestamp=none", bundle)
    report = {"profile": "maccompanion.native-host-development-package.v1",
              "releaseAdmitted": False, "correspondingSourceComplete": False,
              "builderSHA256": digest(Path(__file__)), "toolchain": command("xcodebuild", "-version"),
              "sourceHostSHA256": PINNED_HOST, "origins": origins, "dependencyProvenance": provenance,
              "macho": sorted(originals), "files": files(bundle),
              "limits": ["Ad-hoc development signatures only", "Homebrew dependency binaries with retained licenses/formulas; complete source build provenance pending",
                         "No permanent target, process/TCC admission, normal-app installation or physical acceptance"]}
    (output / "host-package.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    verify(output)
    return report


def smoke(directory):
    verify(directory)
    bundle = directory / "Sunshine.app"
    # No loader or OpenSSL lookup into the developer's dependency installation.
    environment = {k: v for k, v in os.environ.items() if not k.startswith(("DYLD_", "OPENSSL_"))}
    environment["OPENSSL_CONF"] = str(bundle / "Contents/Resources/DependencyNotices/openssl.cnf")
    environment["OPENSSL_MODULES"] = str(bundle / "Contents/Helpers/no-external-modules")
    help_text = command(bundle / "Contents/MacOS/Sunshine", "--help", environment=environment)
    if "Usage" not in help_text and "usage" not in help_text:
        raise ValueError("Host help probe did not start")
    command(bundle / "Contents/Helpers/openssl", "version", environment=environment)
    # Exercise the credential CLI without preserving certificates or keys.
    with tempfile.TemporaryDirectory(prefix="maccompanion-package-crypto-", dir="/private/tmp") as temporary:
        path = Path(temporary)
        command(bundle / "Contents/Helpers/openssl", "req", "-x509", "-newkey", "rsa:2048",
                "-nodes", "-sha256", "-days", "1", "-subj", "/CN=localhost",
                "-keyout", path / "key.pem", "-out", path / "cert.pem", environment=environment)
        command(bundle / "Contents/Helpers/openssl", "verify", "-check_ss_sig", "-CAfile",
                path / "cert.pem", path / "cert.pem", environment=environment)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--smoke", action="store_true")
    args = parser.parse_args()
    output = args.output.resolve()
    if args.verify:
        report = verify(output)
    else:
        if args.root is None:
            parser.error("--root is required for construction")
        report = build(args.root.resolve(), output)
    if args.smoke:
        smoke(output)
    print(json.dumps({"package": str(output), "verified": True,
                      "bundledMachOFiles": len(report["macho"]), "releaseAdmitted": False}))
