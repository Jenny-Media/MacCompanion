#!/usr/bin/env python3
"""Signed, UUID-isolated native enrollment through real primary and local XPC.

Sources remain experimental. Generated dependency/host modules live outside Git;
this is not permanent app, Keychain, TCC, Simulator or physical installation.
"""
import argparse
import hashlib
import json
import os
import re
import plistlib
import signal
from pathlib import Path
import shutil
import subprocess
import sys
import time
from verify_agent_xpc import Probe, ROOT, source_fingerprint

sys.path.insert(0, str(ROOT / "Experiments/SunshineMoonlightIntegration"))
from reference_build import HERE, digest, native_source_inputs, verify_source

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--root", required=True, type=Path)
parser.add_argument("--native-host-package", type=Path,
                    help="Use a verified portable development host package")
parser.add_argument("--launch-menu-app", action="store_true",
                    help="Measure the signed menu role when launched as an isolated app")
parser.add_argument("--menu-signing-reference", type=Path,
                    help="Reuse the installed menu app's designated requirement in the disposable app")
args = parser.parse_args()
if args.launch_menu_app and not args.native_host_package:
    parser.error("--launch-menu-app requires --native-host-package")
if args.menu_signing_reference and not args.launch_menu_app:
    parser.error("--menu-signing-reference requires --launch-menu-app")
root = args.root.resolve()
from native_agent_probe_support import configure_native_probe
portable = args.native_host_package.resolve() if args.native_host_package else None
portable_manifest_sha = None
static_tls = Path("/opt/homebrew/opt/openssl@3/lib")
supervisor = root / "managed-host-supervisor"
if portable:
    from package_rebuilt_source_host import verify_selected as verify_package, openssl_binding
    portable_record = verify_package(portable)
    portable_manifest_sha = digest(portable / "host-package.json")
    supervisor = portable / "Sunshine.app/Contents/Helpers/companion-supervisor"
    binding = openssl_binding(portable_record)
    if binding is not None:
        static_tls = Path(binding["path"]).parent / "prefixes/openssl/lib"
probe, package, binary = configure_native_probe(root, portable)
if portable:
    binary = portable / "Sunshine.app/Contents/MacOS/Sunshine"
execution_hashes = {"host": digest(binary), "supervisor": digest(supervisor),
                    "staticTLS": {name: digest(static_tls / name) for name in ["libssl.a", "libcrypto.a"]}}
inputs_sha = native_source_inputs()[1]
source_sha = source_fingerprint()
runner_sha = digest(Path(__file__))
support_sha = digest(ROOT / "scripts/native_agent_probe_support.py")
failure = None
cleaned = False
capture_geometry = []
menu_app = None
reference_requirement = None
reference_requirement_sha = None
reference_executable_sha = None


def app_pids():
    if menu_app is None:
        return []
    executable = str(menu_app / "Contents/MacOS/menu")
    listing = subprocess.check_output(["/bin/ps", "-axo", "pid=,comm="], text=True)
    return [int(parts[0]) for line in listing.splitlines()
            if len(parts := line.strip().split(None, 1)) == 2 and parts[1] == executable]


def stop_menu_app():
    # Match only the uniquely owned bundle's actual executable, never its
    # permanent signing identifier or another installation's process name.
    for pid in app_pids():
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 3
    while app_pids():
        if time.monotonic() >= deadline:
            raise RuntimeError("Owned menu app remains alive; retain its state")
        time.sleep(.05)


try:
    if args.menu_signing_reference:
        reference = args.menu_signing_reference.resolve()
        subprocess.run(["codesign", "--verify", "--strict", reference], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        reference_requirement = subprocess.check_output(["codesign", "-d", "-r-", reference],
            text=True, stderr=subprocess.DEVNULL)
        if not reference_requirement.startswith('designated => identifier "media.jenny.maccompanion" and '):
            raise ValueError("Signing reference is not the existing Mac Companion identity")
        reference_info = plistlib.loads((reference / "Contents/Info.plist").read_bytes())
        reference_name = reference_info["CFBundleExecutable"]
        if reference_name in {"", ".", ".."} or Path(reference_name).name != reference_name:
            raise ValueError("Invalid reference executable")
        reference_binary = reference / "Contents/MacOS" / reference_name
        reference_executable_sha = digest(reference_binary)
        reference_requirement_sha = hashlib.sha256(reference_requirement.encode()).hexdigest()
    probe.prepare()
    if args.launch_menu_app:
        menu_app = probe.evidence / "Native Menu Attribution.app"
        macos = menu_app / "Contents/MacOS"
        macos.mkdir(parents=True)
        shutil.copy2(probe.evidence / "menu", macos / "menu")
        (menu_app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "media.jenny.maccompanion",
            "CFBundleExecutable": "menu", "CFBundlePackageType": "APPL",
            "CFBundleName": "Mac Companion Native Attribution Test",
            "CFBundleVersion": "1", "CFBundleShortVersionString": "0.1",
            "LSUIElement": True, "LSMinimumSystemVersion": "26.0",
        }))
        identity = os.environ.get("MACCOMPANION_XPC_PROBE_SIGNING_IDENTITY", "Developer ID Application")
        signing = ["codesign", "--force", "--sign", identity, "--timestamp=none", "--options", "runtime"]
        if reference_requirement:
            # Keep private signer details only in this disposable evidence tree.
            requirement_file = probe.evidence / "menu-designated-requirement.txt"
            requirement_file.write_text(reference_requirement)
            signing += ["--requirements", requirement_file]
        probe.command(signing + [menu_app], name="sign-menu-app")
        probe.command(["codesign", "--verify", "--strict", menu_app], name="verify-menu-app")
        if reference_requirement:
            actual_requirement = subprocess.check_output(["codesign", "-d", "-r-", menu_app],
                text=True, stderr=subprocess.DEVNULL)
            assert actual_requirement == reference_requirement, "Disposable menu requirement differs from installed app"
    probe.start_server()
    probe.case("native-durable-remote-access-enable", lambda: probe.client("normal", role="bootstrap", marker="enabled-receipt-verified"))
    probe.stop_server()
    probe.start_server("productionInteractive")
    probe.case("native-primary-listener-readiness", lambda: probe.client("presentation-wait-listener", marker="production-listener-readiness-verified"))
    probe.case("native-real-client-pairing", lambda: probe.client("presentation-pair", marker="real-pairing-approved-and-persisted"))
    def native():
        if menu_app:
            output = probe.evidence / "native-menu-app-output.log"
            command = ["/usr/bin/open", "-n", "-W", "-g", "--stdout", output, "--stderr", output]
            for key in ["MACCOMPANION_NATIVE_LAB_ROOT", "MACCOMPANION_NATIVE_LAB_OWNER_DIR",
                        "MACCOMPANION_NATIVE_LAB_HOST_BUNDLE", "OPENSSL_CONF", "OPENSSL_MODULES"]:
                if key in os.environ:
                    command += ["--env", key + "=" + os.environ[key]]
            command += ["-a", menu_app, "--args", "client", probe.test_id, "presentation-control-native"]
            probe.command(command, name="native-menu-app-launch", timeout=55)
            text = output.read_text()
            assert not app_pids(), "Native menu app survived its bounded test"
        else:
            text = probe.command([probe.evidence / "menu", "client", probe.test_id, "presentation-control-native"], name="native-control", timeout=55)
        for marker in ["signed-control-grant-decline-approve-verified", "real-primary-authentication-verified",
                       "native-bootstrap-decoded-and-acknowledged", "native-primary-and-local-xpc-enrollment-verified",
                       "native-enrolled-client-mtls-verified", "native-authenticated-https-launch-verified",
                       "production-signed-lease-renewal-verified", "native-enrollment-survives-lease-renewals",
                       "native-host-stop-cleanup-verified", "production-stop-preserves-observe-verified"]:
            probe.contains(text, marker)
        records = re.findall(r"^native-menu-capture-geometry-verified capture=(\d+)x(\d+) logical=(\d+)x(\d+) encoded=(\d+)x(\d+)$", text, re.MULTILINE)
        assert len(records) == 1, "Expected one current menu capture-mode measurement"
        w, h, logical_w, logical_h, encoded_w, encoded_h = map(int, records[0])
        assert 1 <= w <= 32768 and 1 <= h <= 32768
        assert 1 <= logical_w <= 4294967295 and 1 <= logical_h <= 4294967295
        assert 320 <= encoded_w <= 8192 and 240 <= encoded_h <= 8192
        capture_geometry.append(dict(capturePixelWidth=w, capturePixelHeight=h,
            logicalWidthPoints=logical_w, logicalHeightPoints=logical_h, encodedWidth=encoded_w, encodedHeight=encoded_h))
    probe.case("native-authenticated-enrollment-and-primary-stop", native)
    probe.stop_server()
    assert native_source_inputs()[1] == inputs_sha and source_fingerprint() == source_sha, "Source changed during native lane"
    assert digest(ROOT / "scripts/native_agent_probe_support.py") == support_sha, "Native probe support changed during lane"
    assert digest(Path(__file__)) == runner_sha, "Native runner changed during lane"
    assert execution_hashes == {"host": digest(binary), "supervisor": digest(supervisor),
        "staticTLS": {name: digest(static_tls / name) for name in ["libssl.a", "libcrypto.a"]}}, "Native execution inputs changed"
    if portable:
        verify_package(portable)
        assert digest(portable / "host-package.json") == portable_manifest_sha, "Host package changed during lane"
    if reference_requirement:
        assert digest(reference_binary) == reference_executable_sha, "Installed reference changed during lane"
        actual = subprocess.check_output(["codesign", "-d", "-r-", reference], text=True, stderr=subprocess.DEVNULL)
        assert actual == reference_requirement, "Installed reference requirement changed during lane"
        subprocess.run(["codesign", "--verify", "--strict", reference], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
except Exception as error:
    failure = f"{type(error).__name__}: {error}"
finally:
    try:
        stop_menu_app()
        probe.cleanup()
        cleaned = True
    except Exception as error:
        failure = f"{failure or ''} Cleanup: {error}"
report = {"profile": "maccompanion.authenticated-native-session-probe.v0.1", "passed": failure is None and cleaned,
          "cases": probe.cases, "cleanupVerified": cleaned, "failure": failure,
          "sourceInputSHA256": inputs_sha, "localXPCSourceSHA256": source_sha, "runnerSHA256": runner_sha,
          "nativeProbeSupportSHA256": support_sha,
          "hostBinarySHA256": execution_hashes["host"], "supervisorSHA256": execution_hashes["supervisor"],
          "staticOpenSSLSHA256": execution_hashes["staticTLS"], "generatedManifestSHA256": digest(package / "Package.swift"),
          "portableNativeHostPackageVerified": portable is not None and failure is None and cleaned,
          "portableNativeHostManifestSHA256": portable_manifest_sha,
          "menuLaunchedAsApp": args.launch_menu_app,
          "menuSigningRequirementSHA256": reference_requirement_sha,
          "installedReferenceExecutableSHA256": reference_executable_sha,
          "authenticatedLocalXPCFlow": failure is None, "authenticatedPrimaryFlow": failure is None,
          "nativeCaptureModeGeometryVerified": failure is None and len(capture_geometry) == 1,
          "nativeCaptureModeGeometry": capture_geometry,
          "actualNativeHTTPSLaunch": failure is None, "nativeSurvivesLeaseRenewals": failure is None,
          "nativeDecodedFrame": False, "phonePresentation": False, "releaseAdmitted": False,
          "limits": ["Software test custody and consent; isolated signed helpers and loopback primary/host",
                     "Generated bootstrap video decoded into a retained Mac pixel buffer; not a visible phone frame",
                     "Managed native enrollment, mTLS launch and renewal continuity; no native video decoder or input",
                     "No installed app, production Keychain, TCC change, Simulator or physical phone"]}
(probe.evidence / "native-report.json").write_text(json.dumps(report, indent=2) + "\n")
print(f"{'PASSED' if report['passed'] else 'FAILED'}: {probe.evidence / 'native-report.json'}", flush=True)
if not report["passed"]:
    print(failure, flush=True)
    raise SystemExit(1)
