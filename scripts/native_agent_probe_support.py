"""Disposable signed native helpers; no permanent target dependency admission."""
import json
import os
from pathlib import Path
import shutil
import sys
from verify_agent_xpc import Probe, ROOT
sys.path.insert(0, str(ROOT / "Experiments/SunshineMoonlightIntegration"))
from reference_build import HERE, digest, verify_source, native_source_inputs


def verify_development_host_package(path: Path):
    from package_rebuilt_source_host import verify_selected
    if (path / "production-supervisor.json").is_file():
        from package_production_native_host import verify as verify_production
        verify_production(path)
        return json.loads((path / "host-package.json").read_text())
    return verify_selected(path)


def configure_native_probe(root: Path, portable_host: Path | None = None):
    root = root.resolve()
    source = verify_source(root, "Sunshine")
    tls_prefix = Path("/opt/homebrew/opt/openssl@3")
    if portable_host is not None:
        from package_rebuilt_source_host import openssl_binding
        package_record = verify_development_host_package(portable_host)
        binary = portable_host / "Sunshine.app/Contents/MacOS/Sunshine"
        binding = openssl_binding(package_record)
        if binding is not None:
            from build_source_native_host import verified_files
            record_path = Path(binding["path"])
            assert digest(record_path) == binding["sha256"], "Native test TLS dependency record changed"
            tls_prefix = record_path.parent / "prefixes/openssl"
            verified_files(tls_prefix, json.loads(record_path.read_text()))
    else:
        binary = source / "cmake-build-maccompanion-reference/Sunshine.app/Contents/MacOS/Sunshine"
        assert digest(binary) == "c48a6824dea93f0157bc1bcbd3819201da671610895a2c5c7885173c9044582d", "Unexpected host artifact"
        assert (root / "managed-host-supervisor").is_file(), "Run the managed host probe first"
    os.environ.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    probe = Probe()
    package = probe.evidence / "native-package"
    package.mkdir()
    shutil.copytree(ROOT / "Experiments/LiveControlLab/Sources", package / "Sources")
    shutil.copytree(ROOT / "Experiments/LiveControlLab/Tests", package / "Tests")
    for name in ["ManagedSunshineEnrollmentBackend.swift", "SunshineProcessOwner.swift", "NativeLaunchResponseV0.swift"]:
        shutil.copyfile((ROOT / "Native/Client" if name == "NativeLaunchResponseV0.swift" else HERE) / name, package / "Sources/AgentXPCTest" / name)
    tls = package / "Sources/NativeTLS"
    tls.mkdir()
    for name in ["CompanionNativeTLS.h", "CompanionNativeTLS.m"]:
        shutil.copyfile(ROOT / "Native/Client" / name, tls / name)
    manifest = (ROOT / "Experiments/LiveControlLab/Package.swift").read_text()
    manifest = manifest.replace('.macOS(.v14)', '.macOS("26.0")')
    manifest = manifest.replace('path: "../../Packages/MacCompanionKit"', 'path: ' + json.dumps(str(ROOT / "Packages/MacCompanionKit")))
    manifest = manifest.replace('    targets: [', '''    targets: [.target(name: "NativeTLS", path: "Sources/NativeTLS", publicHeadersPath: ".",
            cSettings: [.unsafeFlags(["-fobjc-arc", ''' + json.dumps("-I" + str(tls_prefix / "include")) + '''])],
            linkerSettings: [.linkedFramework("Foundation"),
                .unsafeFlags([''' + json.dumps(str(tls_prefix / "lib/libssl.a")) + ", " + json.dumps(str(tls_prefix / "lib/libcrypto.a")) + '''])]),''', 1)
    manifest = manifest.replace('.executableTarget(name: "AgentXPCTest", dependencies: [', '.executableTarget(name: "AgentXPCTest", dependencies: ["NativeTLS",')
    manifest = manifest.replace('        ]),\n        .executableTarget(name: "LiveControlTestHost"', '        ], swiftSettings: [.define("MACCOMPANION_NATIVE_LAB")]),\n        .executableTarget(name: "LiveControlTestHost"')
    (package / "Package.swift").write_text(manifest)
    probe.package_path = package
    os.environ["MACCOMPANION_NATIVE_LAB_ROOT"] = str(root)
    os.environ["MACCOMPANION_NATIVE_LAB_OWNER_DIR"] = str(probe.state / "signed-native-owned")
    os.environ.pop("MACCOMPANION_NATIVE_LAB_HOST_BUNDLE", None)
    if portable_host is not None:
        bundle = portable_host.resolve() / "Sunshine.app"
        os.environ["MACCOMPANION_NATIVE_LAB_HOST_BUNDLE"] = str(bundle)
        os.environ["OPENSSL_CONF"] = str(bundle / "Contents/Resources/DependencyNotices/openssl.cnf")
        os.environ["OPENSSL_MODULES"] = str(bundle / "Contents/Helpers/no-external-modules")
    return probe, package, binary


def native_simulator_project(probe, root: Path):
    """Generate a Debug Simulator app around the normal workspace owners."""
    probe.command([sys.executable, HERE / "engine_build.py", "--root", root,
                   "--sdk", "iphonesimulator"], timeout=600, name="native-engine-build")
    project = probe.evidence / "native-simulator"
    project.mkdir()
    framework = root / "embedded-engine/DerivedData/Build/Products/Debug-iphonesimulator/CompanionMoonlightEngine.framework"
    harness = ROOT / "Experiments/ClientUIHarness/ClientUIHarness"
    products = sorted({name for path in harness.glob("*.swift")
                       for name in __import__("re").findall(r"^import (Companion\w+)$", path.read_text(), __import__("re").M)})
    specification = {
        "name": "NativeClientUIHarness",
        "options": {"deploymentTarget": {"iOS": "26.0"}},
        "packages": {"MacCompanionKit": {"path": str(ROOT / "Packages/MacCompanionKit")},
                     "LiveControlLab": {"path": str(ROOT / "Experiments/LiveControlLab")}},
        "settings": {"base": {"SWIFT_VERSION": "6.0", "CODE_SIGNING_ALLOWED": "NO"}},
        "targets": {
            "ClientUIHarness": {"type": "application", "platform": "iOS", "sources": [
                {"path": str(harness)}, *[{"path": str(ROOT / "Native/Client" / name)} for name in
                ["MoonlightNativeVideoDriverV0.swift", "MoonlightNativeLaunchAdapterV0.swift", "NativeLaunchResponseV0.swift"]]],
                "dependencies": [{"package": "MacCompanionKit", "product": name} for name in products] + [
                    {"package": "LiveControlLab", "product": "LiveControlLabSupport"},
                    {"framework": str(framework), "embed": True},
                    {"framework": str(root / "embedded-engine/Dependencies/OpenSSL.xcframework"), "embed": True}],
                "settings": {"base": {"PRODUCT_BUNDLE_IDENTIFIER": "dev.maccompanion.clientuiharness",
                    "GENERATE_INFOPLIST_FILE": "YES", "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
                    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
                    "INFOPLIST_KEY_NSLocalNetworkUsageDescription": "Connect to the isolated test Mac.",
                    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) DEBUG MACCOMPANION_NATIVE_LAB",
                    "TARGETED_DEVICE_FAMILY": "1,2"}}},
            "ClientUIHarnessUITests": {"type": "bundle.ui-testing", "platform": "iOS", "sources": [
                {"path": str(ROOT / "Experiments/ClientUIHarness/ClientUIHarnessUITests")}],
                "dependencies": [{"target": "ClientUIHarness"}],
                "settings": {"base": {"PRODUCT_BUNDLE_IDENTIFIER": "dev.maccompanion.clientuiharness.uitests",
                    "GENERATE_INFOPLIST_FILE": "YES", "TEST_TARGET_NAME": "ClientUIHarness"}}}},
        "schemes": {"ClientUIHarness": {"build": {"targets": {"ClientUIHarness": "all"}},
            "test": {"targets": ["ClientUIHarnessUITests"]}}}}
    manifest = project / "project.json"
    manifest.write_text(json.dumps(specification, indent=2) + "\n")
    probe.command(["xcodegen", "generate", "--spec", manifest, "--project", project], name="native-project")
    return project / "NativeClientUIHarness.xcodeproj", project / "DerivedData"
