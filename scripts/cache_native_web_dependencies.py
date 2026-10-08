#!/usr/bin/env python3
"""Collect integrity-pinned Web UI packages and verify an offline build."""
import argparse
import base64
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import urllib.parse
import urllib.request

from package_native_host import digest, files
from package_native_sources import verify as verify_sources


def fetch(entry, archives):
    key, value = entry
    url = value["resolved"]
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or parsed.netloc != "registry.npmjs.org" or parsed.query or parsed.fragment:
        raise ValueError("Unexpected package registry: " + key)
    integrity = value["integrity"]
    if not integrity.startswith("sha512-") or " " in integrity:
        raise ValueError("Unsupported package integrity: " + key)
    expected = base64.b64decode(integrity.removeprefix("sha512-"), validate=True)
    target = archives / (hashlib.sha256(key.encode()).hexdigest() + ".tgz")
    with urllib.request.urlopen(url, timeout=60) as response, target.open("xb") as output:
        shutil.copyfileobj(response, output)
    with target.open("rb") as archive:
        if hashlib.file_digest(archive, "sha512").digest() != expected:
            raise ValueError("Package integrity mismatch: " + key)
    with tarfile.open(target) as stream:
        manifests = [m for m in stream if m.isfile()
                     and Path(m.name).name == "package.json"
                     and m.name.removeprefix("./").count("/") <= 1
                     and ".." not in Path(m.name).parts]
        if len(manifests) != 1:
            raise ValueError("Ambiguous package archive metadata: " + key)
        metadata = json.load(stream.extractfile(manifests[0]))
        if metadata["name"] != key.rsplit("node_modules/", 1)[1] or metadata["version"] != value["version"]:
            raise ValueError("Package metadata differs from the lock: " + key)
        notices = {m.name: hashlib.sha256(stream.extractfile(m).read()).hexdigest()
                   for m in stream if m.isfile() and Path(m.name).name.upper().startswith(("LICENSE", "COPYING", "NOTICE"))}
    return key, {"name": metadata["name"], "version": metadata["version"], "resolved": url,
                 "integrity": integrity, "archive": target.name, "archiveSHA256": digest(target),
                 "licenseMetadata": metadata.get("license", "NOASSERTION"), "noticeFiles": notices,
                 "developmentDependency": bool(value.get("dev")), "optional": bool(value.get("optional"))}


def run(args, directory, output, environment):
    with output.open("w") as log:
        subprocess.run([str(a) for a in args], cwd=directory, env=environment,
                       stdout=log, stderr=subprocess.STDOUT, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-inputs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    source_inputs, output = args.source_inputs.resolve(), args.output.resolve()
    bound = verify_sources(source_inputs)
    source = source_inputs / "payload/upstream/Sunshine"
    lock = json.loads((source / "package-lock.json").read_text())
    if lock["lockfileVersion"] != 3:
        raise ValueError("Unsupported Web UI dependency lock")
    entries = sorted((k, v) for k, v in lock["packages"].items() if k)
    output.mkdir(parents=True, exist_ok=False)
    archives = output / "archives"
    archives.mkdir()
    records = {}
    with ThreadPoolExecutor(max_workers=6) as executor:
        for key, record in executor.map(lambda entry: fetch(entry, archives), entries):
            records[key] = record
            if len(records) % 20 == 0:
                print("Verified package archives: " + str(len(records)), flush=True)
    project = output / "web-project"
    project.mkdir()
    for name in ["package.json", "package-lock.json", "vite.config.js"]:
        shutil.copyfile(source / name, project / name)
    shutil.copytree(source / "src_assets/common/assets/web", project / "src_assets/common/assets/web", symlinks=True)
    (output / "empty-user.npmrc").write_text("")
    (output / "empty-global.npmrc").write_text("")
    environment = {k: v for k, v in os.environ.items()
                   if not k.startswith(("NPM_", "npm_", "CODECOV_", "GITHUB_", "SUNSHINE_"))}
    environment["GITHUB_REPOSITORY"] = ""
    environment["npm_config_offline"] = "true"
    options = ["--cache", output / "npm-cache", "--offline", "--ignore-scripts",
               "--userconfig", output / "empty-user.npmrc", "--globalconfig", output / "empty-global.npmrc"]
    run(["npm", "cache", "add", *sorted(archives.glob("*.tgz")), *options], project, output / "cache-import.log", environment)
    print("Installing Web UI dependencies using the isolated offline cache", flush=True)
    run(["npm", "ci", *options], project, output / "offline-install.log", environment)
    print("Building the Web UI using the offline installed packages", flush=True)
    run(["npm", "run", "build"], project, output / "offline-build.log", environment)
    assets = project / "build/assets/web"
    if not (assets / "index.html").is_file() or not (assets / "pin.html").is_file():
        raise ValueError("Missing rebuilt Web UI pages")
    if digest(source / "package-lock.json") != bound["files"]["upstream/Sunshine/package-lock.json"]["sha256"]:
        raise ValueError("Web UI source lock changed")
    if any(digest(archives / r["archive"]) != r["archiveSHA256"] for r in records.values()):
        raise ValueError("Web dependency archive changed")
    report = {"profile": "maccompanion.native-web-ui-offline-inputs.v1", "builderSHA256": digest(Path(__file__)),
              "sourceManifestSHA256": digest(source_inputs / "source-inputs.json"), "sourceArchiveSHA256": bound["archiveSHA256"],
              "lockSHA256": digest(source / "package-lock.json"), "packages": records,
              "offlineCacheInstallVerified": True, "offlineWebUIBuildVerified": True,
              "rebuiltAssets": files(assets), "releaseAdmitted": False, "correspondingSourceComplete": False,
              "limits": ["Package archives retain package license metadata/notices; no legal compatibility assertion",
                         "Platform-specific optional packages include general-purpose build-tool binaries",
                         "Complete source snapshot assembly/rebuild and permanent admission remain pending"]}
    (output / "web-source-inputs.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"verifiedPackageArchives": len(records), "offlineInstallAndBuildVerified": True, "releaseAdmitted": False}))


if __name__ == "__main__":
    main()
