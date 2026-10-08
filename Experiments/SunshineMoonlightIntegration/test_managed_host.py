#!/usr/bin/env python3
"""Run the isolated proof-to-Sunshine startup and cleanup integration probe."""
import argparse
import json
import ipaddress
import shutil
from pathlib import Path
import subprocess
from reference_build import HERE, digest, native_source_inputs, verify_source

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--root", type=Path, required=True)
parser.add_argument("--peer-address", default="127.0.0.1", help="Local Mac IPv4 interface to test; non-loopback selects the trusted IPv4 listener")
args = parser.parse_args()
root = args.root.resolve()
peer = ipaddress.IPv4Address(args.peer_address)
if peer.is_unspecified or peer.is_multicast:
    raise ValueError("A concrete local IPv4 interface is required")
source = verify_source(root, "Sunshine")
binary = source / "cmake-build-maccompanion-reference/Sunshine.app/Contents/MacOS/Sunshine"
openssl = Path("/opt/homebrew/opt/openssl@3/bin/openssl").resolve()
inputs, fingerprint = native_source_inputs()
subprocess.run(["xcrun", "clang", "-std=c11", "-mmacosx-version-min=26.0", "-Wall", "-Wextra", "-Werror",
                str(HERE.parents[1] / "Native/Host/companion-supervisor.c"), "-o", str(root / "managed-host-supervisor")], check=True)
# Generate the disposable build manifest outside the repository. It is not a
# new admitted production package or a dependency-policy exception.
package = root / "managed-host-package"
package.mkdir(exist_ok=True)
template = (HERE / "ManagedHostProbePackage.swift.template").read_text()
(package / "Package.swift").write_text(template.replace("__MACCOMPANION_KIT_PATH__", json.dumps(str(HERE.parents[1] / "Packages/MacCompanionKit"))))
(package / "NativeTLS").mkdir(exist_ok=True)
for name in ["CompanionNativeTLS.h", "CompanionNativeTLS.m"]:
    shutil.copyfile((HERE.parents[1] / "Native/Client" if name in {"CompanionNativeTLS.h", "CompanionNativeTLS.m", "NativeLaunchResponseV0.swift"} else HERE) / name, package / "NativeTLS" / name)
for name in ["SunshineProcessOwner.swift", "ManagedSunshineEnrollmentBackend.swift", "ManagedHostProbeMain.swift", "NativeLaunchResponseV0.swift"]:
    shutil.copyfile((HERE.parents[1] / "Native/Client" if name in {"CompanionNativeTLS.h", "CompanionNativeTLS.m", "NativeLaunchResponseV0.swift"} else HERE) / name, package / name)
with (root / "managed-host-build.log").open("w") as output:
    subprocess.run(["swift", "build", "--package-path", str(package), "--scratch-path", str(root / "managed-host-build")],
                   stdout=output, stderr=subprocess.STDOUT, check=True)
executable = root / "managed-host-build/debug/ManagedHostProbe"
result = subprocess.run([str(executable), str(root), str(peer)], capture_output=True, text=True, timeout=45)
_, after = native_source_inputs()
if after != fingerprint:
    raise ValueError("Sources changed during the managed host probe")
report = {"profile": "maccompanion.managed-native-host-probe.v0.1", "passed": result.returncode == 0,
          "sourceInputsSHA256": fingerprint, "sourceInputs": inputs, "hostBinarySHA256": digest(binary),
          "opensslExecutableSHA256": digest(openssl), "probeExecutableSHA256": digest(executable),
          "managedRoutesDenied": result.returncode == 0, "plaintextAndWebUIAbsent": result.returncode == 0,
          "menuOwnedBackendFlow": True, "productionMenuRuntimeAdmission": True, "platformEffectsSubstituted": True,
          "unacknowledgedDesktopDenied": result.returncode == 0, "menuStopRetiresHost": result.returncode == 0, "actualNativeHTTPSLaunch": result.returncode == 0,
          "encryptedStreamRouteVerified": result.returncode == 0, "decodedFrame": False, "inProcessCanonicalLocalRecords": True, "authenticatedLocalXPCFlow": False,
          "unencryptedLaunchDenied": result.returncode == 0, "plaintextRTSPClosed": result.returncode == 0,
          "nonloopbackIPv4": not peer.is_loopback, "networkListenersRetired": result.returncode == 0,
          "authenticatedPrimaryFlow": False, "physicalPhone": False, "releaseAdmitted": False}
(root / "managed-host-probe-report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
if result.returncode != 0:
    # Do not print raw native diagnostics, certificates, or private paths.
    raise RuntimeError("Managed host probe failed; inspect local diagnostics")
print("Managed native host probe passed: certificate admission, sealed routes/listeners, port conflict, invalid proof, revocation and cleanup.")
