#!/usr/bin/env python3
"""Stage a signed normal Debug app with the exact admitted native resources.

Does not install, launch, register login services, or admit a release artifact.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess

from package_native_host import command, digest
from package_production_native_host import verify

APP_ID = "media.jenny.maccompanion"
CATALOG_SHA = "e6a46019ecbd18104400ef5a1891f05691029c1cb547bbcb44def70c7a67bb8f"


def signed_entitlements(bundle):
    result = subprocess.run(
        ["codesign", "--display", "--entitlements", "-", "--xml", str(bundle)],
        check=True, capture_output=True,
    )
    return plistlib.loads(result.stdout) if result.stdout else {}


def stage(app, package, output, identity):
    verify(package)
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if info["CFBundleIdentifier"] != APP_ID or output.exists():
        raise ValueError("Requires the normal app and a fresh output path")
    agent_relative_path = Path("Contents/Helpers/MacCompanionAgent.app")
    agent_entitlements = signed_entitlements(app / agent_relative_path)
    if not agent_entitlements.get("keychain-access-groups"):
        raise ValueError("The signed source Agent has no Keychain entitlement")
    record = json.loads((package / "host-package.json").read_text())
    catalog = {"profile": "maccompanion.bundled-native-host-development.v1", "releaseAdmitted": False,
               "files": {key: value["sha256"] for key, value in record["files"].items()}}
    data = json.dumps(catalog, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    if hashlib.sha256(data).hexdigest() != CATALOG_SHA:
        raise ValueError("Package is outside the compiled development authority")
    shutil.copytree(app, output, symlinks=True)
    host = output / "Contents/Helpers/Sunshine.app"
    shutil.copytree(package / "Sunshine.app", host, symlinks=True)
    (output / "Contents/Resources/NativeHostDevelopment.json").write_bytes(data)
    # Re-sign the copied normal graph only; the admitted host must retain the
    # exact bytes selected by its catalog. Existing installed apps are untouched.
    nested = [path for path in output.rglob("*") if path.suffix in {".app", ".framework", ".xpc"}
              and not path.is_relative_to(host)]
    for path in sorted(nested, key=lambda item: len(item.parts), reverse=True):
        command("codesign", "--force", "--sign", identity, "--timestamp=none",
                "--preserve-metadata=identifier,entitlements,requirements,flags,runtime", path)
    command("codesign", "--force", "--sign", identity, "--timestamp=none",
            "--preserve-metadata=identifier,entitlements,requirements,flags,runtime", output)
    command("codesign", "--verify", "--strict", "--deep", "-R", '=identifier "' + APP_ID + '" and anchor apple generic', output)
    if signed_entitlements(output / agent_relative_path) != agent_entitlements:
        raise ValueError("The staged Agent lost its signed entitlements")
    if (output / "Contents/Resources/NativeHostDevelopment.json").read_bytes() != data:
        raise ValueError("Catalog changed during signing")
    from package_native_host import files
    if files(host) != record["files"]:
        raise ValueError("Admitted host changed during staging")
    return {"profile": "maccompanion.normal-debug-native-host-stage.v1", "releaseAdmitted": False,
            "app": str(output), "catalogSHA256": CATALOG_SHA,
            "sourceHostManifestSHA256": digest(package / "host-package.json"),
            "builderSHA256": digest(Path(__file__)), "containingSignatureVerified": True,
            "installed": False, "launched": False}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--host-package", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--identity", default="Apple Development")
    args = parser.parse_args()
    print(json.dumps(stage(args.app.resolve(), args.host_package.resolve(), args.output.resolve(), args.identity), sort_keys=True))
