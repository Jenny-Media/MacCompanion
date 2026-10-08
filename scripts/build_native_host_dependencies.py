#!/usr/bin/env python3
"""Build pinned Mac host dependencies outside permanent targets."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import urllib.request

HERE = Path(__file__).resolve().parent
LOCK_PATH = HERE / "native_host_dependency_sources.json"
LOCK = json.loads(LOCK_PATH.read_text())


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def capture(*args):
    return subprocess.check_output([str(a) for a in args], text=True).strip()


def run(args, directory, environment, log):
    with log.open("w") as stream:
        subprocess.run([str(a) for a in args], cwd=directory, env=environment,
                       stdout=stream, stderr=subprocess.STDOUT, check=True)


def source(root, name):
    item = LOCK["sources"][name]
    downloads = root / "archives"
    downloads.mkdir(parents=True, exist_ok=True)
    archive = downloads / (name + ".tar.gz")
    if not archive.exists():
        temporary = archive.with_suffix(".download")
        with urllib.request.urlopen(item["url"], timeout=60) as response, temporary.open("wb") as output:
            shutil.copyfileobj(response, output)
        if digest(temporary) != item["sha256"]:
            raise ValueError(name + ": source checksum mismatch")
        temporary.replace(archive)
    if digest(archive) != item["sha256"]:
        raise ValueError(name + ": source archive changed")
    sources = root / "sources" / name
    sources.mkdir(parents=True, exist_ok=True)
    path = sources / item["directory"]
    if not path.exists():
        with tarfile.open(archive) as contents:
            contents.extractall(sources, filter="data")
    expected = {}
    with tarfile.open(archive) as contents:
        for entry in contents:
            if entry.isfile():
                expected[entry.name] = hashlib.sha256(contents.extractfile(entry).read()).hexdigest()
    actual = {str(p.relative_to(sources)): digest(p) for p in sources.rglob("*")
              if p.is_file() and not p.is_symlink()}
    if actual != expected:
        raise ValueError(name + ": extracted source differs from locked archive")
    return path


def build(root, name):
    original = source(root, name)
    sdk = capture("xcrun", "--sdk", "macosx", "--show-sdk-path")
    compiler = capture("xcrun", "--find", "clang")
    flags = "-arch arm64 -mmacosx-version-min=26.0 -isysroot " + sdk
    environment = {k: v for k, v in os.environ.items()
                   if k not in {"CC", "CXX", "CFLAGS", "CXXFLAGS", "CPPFLAGS", "LDFLAGS", "SDKROOT", "AR", "RANLIB", "PKG_CONFIG_PATH"}}
    environment.update(CC=compiler, CXX=capture("xcrun", "--find", "clang++"),
                       CFLAGS=flags, CXXFLAGS=flags, LDFLAGS=flags,
                       AR=capture("xcrun", "--find", "ar"), RANLIB=capture("xcrun", "--find", "ranlib"))
    inputs = {"source": LOCK["sources"][name], "builderSHA256": digest(Path(__file__)),
              "lockSHA256": digest(LOCK_PATH), "toolchain": capture("xcodebuild", "-version"),
              "sdkVersion": capture("xcrun", "--sdk", "macosx", "--show-sdk-version"),
              "compiler": capture(compiler, "--version"), "flags": flags}
    prefix = root / "prefixes" / name
    stamp = root / (name + "-provenance.json")
    if stamp.exists():
        record = json.loads(stamp.read_text())
        if record["inputs"] == inputs and all((prefix / p).is_file() and digest(prefix / p) == checksum
                                              for p, checksum in record["files"].items()):
            print(name + ": verified existing source build", flush=True)
            return
    work = root / "build" / name
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)
    if prefix.exists():
        shutil.rmtree(prefix)
    prefix.mkdir(parents=True)
    logs = root / "logs"
    logs.mkdir(exist_ok=True)
    print(name + ": building from verified source", flush=True)
    if name == "openssl":
        configure = ["/usr/bin/perl", original / "Configure", "darwin64-arm64-cc", "shared",
                     "no-tests", "no-module", "no-engine", "--prefix=" + str(prefix)]
        run(configure, work, environment, logs / (name + "-configure.log"))
        run(["/usr/bin/make", "-j4"], work, environment, logs / (name + "-build.log"))
        run(["/usr/bin/make", "install_sw"], work, environment, logs / (name + "-install.log"))
    elif name == "icu":
        run([original / "source/configure", "--prefix=" + str(prefix), "--disable-tests",
             "--disable-samples"], work, environment, logs / (name + "-configure.log"))
        run(["/usr/bin/make", "-j4"], work, environment, logs / (name + "-build.log"))
        run(["/usr/bin/make", "install"], work, environment, logs / (name + "-install.log"))
    else:
        configure = ["cmake", "-S", original, "-B", work,
                     "-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_INSTALL_PREFIX=" + str(prefix),
                     "-DCMAKE_C_COMPILER=" + compiler, "-DCMAKE_OSX_ARCHITECTURES=arm64",
                     "-DCMAKE_OSX_DEPLOYMENT_TARGET=26.0", "-DCMAKE_OSX_SYSROOT=" + sdk,
                     "-DBUILD_SHARED_LIBS=ON"]
        if name == "miniupnpc":
            configure += ["-DUPNPC_BUILD_TESTS=OFF", "-DUPNPC_BUILD_SAMPLE=OFF", "-DUPNPC_BUILD_STATIC=ON"]
        else:
            configure += ["-DOPUS_BUILD_TESTING=OFF", "-DOPUS_BUILD_PROGRAMS=OFF"]
        run(configure, work, environment, logs / (name + "-configure.log"))
        run(["cmake", "--build", work, "-j4"], work, environment, logs / (name + "-build.log"))
        run(["cmake", "--install", work], work, environment, logs / (name + "-install.log"))
    notices = prefix / "share/maccompanion-source-notices"
    notices.mkdir(parents=True, exist_ok=True)
    shutil.copy2(original / LOCK["sources"][name]["license"], notices / "LICENSE.txt")
    # Hash actual file contents, including installed dylib aliases.
    record = {"inputs": inputs, "files": {str(p.relative_to(prefix)): digest(p)
              for p in sorted(prefix.rglob("*")) if p.is_file()},
              "sourceBuilt": True, "releaseAdmitted": False}
    stamp.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    shutil.rmtree(work)
    print(name + ": source build complete", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--dependency", choices=[*LOCK["sources"], "all"], default="all")
    args = parser.parse_args()
    root = args.root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    for name in LOCK["sources"] if args.dependency == "all" else [args.dependency]:
        build(root, name)
