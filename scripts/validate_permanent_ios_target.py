#!/usr/bin/env python3

from __future__ import annotations

import plistlib
import re
import sys
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[1]
PROJECT_SPEC = REPOSITORY / "project.yml"
PROJECT_FILE = REPOSITORY / "MacCompanion.xcodeproj" / "project.pbxproj"
INFO_PLIST = REPOSITORY / "Apps" / "MacCompanionIOS" / "Info.plist"
APP_SOURCE = (
    REPOSITORY
    / "Apps"
    / "MacCompanionIOS"
    / "MacCompanionIOSApplication.swift"
)
BOOTSTRAP_SOURCE = (
    REPOSITORY
    / "Packages"
    / "MacCompanionKit"
    / "Sources"
    / "CompanionClientPlatform"
    / "IOSClientReleaseBootstrapV1.swift"
)
APPLICATION_SOURCE = (
    REPOSITORY
    / "Packages"
    / "MacCompanionKit"
    / "Sources"
    / "CompanionClientPlatform"
    / "IOSClientReleaseApplicationV1.swift"
)
WORKSPACE_SOURCE = (
    REPOSITORY
    / "Packages"
    / "MacCompanionKit"
    / "Sources"
    / "CompanionClientUI"
    / "ClientPrimaryWorkspaceApplicationViewV1.swift"
)
ROUTE_VIEW_SOURCE = (
    REPOSITORY
    / "Packages"
    / "MacCompanionKit"
    / "Sources"
    / "CompanionClientUI"
    / "ClientRouteBootstrapApplicationViewV1.swift"
)

IOS_IDENTIFIER = "media.jenny.maccompanion.ios"
IOS_PRODUCTS = ["CompanionClientPlatform", "CompanionClientUI"]
PRIVACY_MANIFEST = (
    "spec/privacy-manifest/v0/targets/ios-app/PrivacyInfo.xcprivacy"
)


def read_text(path: Path, failures: list[str]) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as error:
        failures.append(
            f"unreadable:{path.relative_to(REPOSITORY)}:"
            f"{type(error).__name__}"
        )
        return ""


def yaml_target_block(content: str, target: str) -> str:
    match = re.search(
        rf"^  {re.escape(target)}:\n(?P<body>.*?)(?=^  \S|\Z)",
        content,
        re.MULTILINE | re.DOTALL,
    )
    return match.group("body") if match else ""


def pbx_objects(content: str) -> dict[str, str]:
    return {
        match.group("identifier"): match.group("body")
        for match in re.finditer(
            r"^\s*(?P<identifier>[0-9A-F]{24}) "
            r"/\*[^\n]*\*/ = \{(?P<body>.*?)\};",
            content,
            re.MULTILINE | re.DOTALL,
        )
    }


def generated_native_target_block(content: str, target: str) -> str:
    for match in re.finditer(
        r"isa = PBXNativeTarget;(?P<body>.*?)(?=\n\s*};)",
        content,
        re.DOTALL,
    ):
        body = match.group("body")
        if f"name = {target};" in body:
            return body
    return ""


def generated_products(content: str, target: str) -> tuple[list[str], list[str]]:
    objects = pbx_objects(content)
    product_names: dict[str, str] = {}
    for identifier, body in objects.items():
        if "isa = XCSwiftPackageProductDependency;" not in body:
            continue
        match = re.search(r"productName = ([^;]+);", body)
        if match:
            product_names[identifier] = match.group(1).strip().strip('"')

    target_block = generated_native_target_block(content, target)
    dependency_match = re.search(
        r"packageProductDependencies = \((?P<value>.*?)\);",
        target_block,
        re.DOTALL,
    )
    dependency_ids = re.findall(
        r"\b[0-9A-F]{24}\b",
        dependency_match.group("value") if dependency_match else "",
    )
    dependencies = [
        product_names.get(identifier, f"unresolved:{identifier}")
        for identifier in dependency_ids
    ]

    phase_match = re.search(
        r"buildPhases = \((?P<value>.*?)\);",
        target_block,
        re.DOTALL,
    )
    phase_ids = re.findall(
        r"\b[0-9A-F]{24}\b",
        phase_match.group("value") if phase_match else "",
    )
    framework_phases = [
        objects[identifier]
        for identifier in phase_ids
        if "isa = PBXFrameworksBuildPhase;" in objects.get(identifier, "")
    ]
    frameworks: list[str] = []
    if len(framework_phases) != 1:
        frameworks.append(f"frameworkPhaseCount:{len(framework_phases)}")
    else:
        files_match = re.search(
            r"files = \((?P<value>.*?)\);",
            framework_phases[0],
            re.DOTALL,
        )
        build_file_ids = re.findall(
            r"\b[0-9A-F]{24}\b",
            files_match.group("value") if files_match else "",
        )
        for build_file_id in build_file_ids:
            build_file = objects.get(build_file_id, "")
            product = re.search(r"productRef = ([0-9A-F]{24})\b", build_file)
            if not product:
                frameworks.append(f"unresolvedBuildFile:{build_file_id}")
                continue
            identifier = product.group(1)
            frameworks.append(
                product_names.get(identifier, f"unresolved:{identifier}")
            )
    return dependencies, frameworks


def require_exact_products(
    dependencies: list[str],
    frameworks: list[str],
    prefix: str,
    failures: list[str],
) -> None:
    expected = IOS_PRODUCTS
    for label, actual in (
        (f"{prefix}Dependencies", dependencies),
        (f"{prefix}Frameworks", frameworks),
    ):
        if actual != expected:
            failures.append(
                f"{label}:expected={','.join(expected)}:"
                f"actual={','.join(actual)}"
            )


def validate_project_spec(content: str, failures: list[str]) -> None:
    block = yaml_target_block(content, "MacCompanionIOS")
    required = (
        "    type: application\n    platform: iOS",
        "      - path: Apps/MacCompanionIOS",
        f"      - path: {PRIVACY_MANIFEST}\n        buildPhase: resources",
        "        GENERATE_INFOPLIST_FILE: NO",
        "        INFOPLIST_FILE: Apps/MacCompanionIOS/Info.plist",
        '        IPHONEOS_DEPLOYMENT_TARGET: "26.0"',
        f"        PRODUCT_BUNDLE_IDENTIFIER: {IOS_IDENTIFIER}",
        "        SUPPORTS_MACCATALYST: NO",
        "        SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD: NO",
        '        TARGETED_DEVICE_FAMILY: "1,2"',
    )
    for needle in required:
        if block.count(needle) != 1:
            failures.append(f"projectSpecMissingOrRepeated:{needle.strip()}")
    products = re.findall(
        r"^\s+product:\s+([^\s#]+)\s*$",
        block,
        re.MULTILINE,
    )
    require_exact_products(products, products, "projectSpec", failures)
    for forbidden in (
        "DEVELOPMENT_TEAM:",
        "PROVISIONING_PROFILE",
        "CODE_SIGN_ENTITLEMENTS:",
        "UIBackgroundModes",
    ):
        if forbidden in block:
            failures.append(f"projectSpecUnexpectedAuthority:{forbidden}")
    for match in re.finditer(
        r'^\s*CODE_SIGN_IDENTITY:\s*(.*?)\s*$',
        block,
        re.MULTILINE,
    ):
        if match.group(1) != '""':
            failures.append(
                "projectSpecUnexpectedAuthority:CODE_SIGN_IDENTITY"
            )


def validate_generated_project(content: str, failures: list[str]) -> None:
    target = generated_native_target_block(content, "MacCompanionIOS")
    if 'productType = "com.apple.product-type.application";' not in target:
        failures.append("generatedMissingIOSApplicationTarget")
    dependencies, frameworks = generated_products(content, "MacCompanionIOS")
    require_exact_products(
        dependencies, frameworks, "generatedProject", failures
    )
    if content.count(f"PRODUCT_BUNDLE_IDENTIFIER = {IOS_IDENTIFIER};") != 2:
        failures.append("generatedIOSIdentifierMismatch")
    if content.count("IPHONEOS_DEPLOYMENT_TARGET = 26.0;") != 4:
        failures.append("generatedIOSDeploymentMismatch")
    # The separately provisioned macOS Agent owns its one tracked
    # CODE_SIGN_ENTITLEMENTS path. Keep global private signing authority out of
    # the generated project while the iOS target block above remains closed.
    if re.search(r"\b(?:DEVELOPMENT_TEAM|PROVISIONING_PROFILE) =", content):
        failures.append("generatedProjectContainsSigningAuthority")


def validate_info_plist(data: bytes, failures: list[str]) -> None:
    try:
        value = plistlib.loads(data)
    except (plistlib.InvalidFileException, ValueError) as error:
        failures.append(f"infoPlistUnreadable:{type(error).__name__}")
        return
    expected = {
        "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
        "CFBundleDisplayName": "Mac Companion",
        "CFBundleExecutable": "$(EXECUTABLE_NAME)",
        "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": "$(PRODUCT_NAME)",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "$(MARKETING_VERSION)",
        "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
        "LSRequiresIPhoneOS": True,
        "NSBonjourServices": ["_maccompanion._tcp"],
        "NSCameraUsageDescription": (
            "Scan a temporary Mac Companion pairing code that you chose "
            "to display on your Mac."
        ),
        "NSLocalNetworkUsageDescription": (
            "Find and connect directly to your Mac on your local network. "
            "Mac Companion does not use a vendor relay."
        ),
        "UILaunchScreen": {},
        "UISupportedInterfaceOrientations": [
            "UIInterfaceOrientationPortrait",
            "UIInterfaceOrientationLandscapeLeft",
            "UIInterfaceOrientationLandscapeRight",
        ],
        "UISupportedInterfaceOrientations~ipad": [
            "UIInterfaceOrientationPortrait",
            "UIInterfaceOrientationPortraitUpsideDown",
            "UIInterfaceOrientationLandscapeLeft",
            "UIInterfaceOrientationLandscapeRight",
        ],
    }
    if value != expected:
        failures.append("infoPlistSchemaOrValueMismatch")
    for forbidden in (
        "UIBackgroundModes",
        "UIApplicationExitsOnSuspend",
        "NSAppTransportSecurity",
        "NSAllowsArbitraryLoads",
    ):
        if forbidden in value:
            failures.append(f"infoPlistUnexpectedAuthority:{forbidden}")


def validate_app_source(content: str, failures: list[str]) -> None:
    imports = re.findall(r"^import (\S+)$", content, re.MULTILINE)
    if imports != [
        "CompanionClientPlatform",
        "CompanionClientUI",
        "Foundation",
        "SwiftUI",
    ]:
        failures.append(f"appSourceImports:{','.join(imports)}")
    required = (
        "@main",
        "struct MacCompanionIOSApplication: App",
        "@State private var application = IOSClientReleaseApplicationV1()",
        ".task { await application.start() }",
        ".sheet(item: $sheet)",
        "ClientPairingScannerViewV0(",
        "ClientPairingViewV0(",
        "ClientRouteBootstrapApplicationViewV1(",
        "ClientPrimaryWorkspaceApplicationViewV1(",
        "case .routeSetupDeferred:",
        "case .workspace:",
        "await application.completeRouteSetup(choices)",
    )
    for needle in required:
        if content.count(needle) != 1:
            failures.append(f"appSourceMissingOrRepeated:{needle}")
    for forbidden in (
        "NWBrowser",
        "NWConnection",
        "URLSession",
        "AVCapture",
        "UIApplication.shared",
        "UserDefaults",
        "requestAccess",
        "openSettingsURLString",
        "hostID.uuidString",
        "pairing.hostID",
        "workspace.hostID",
    ):
        if forbidden in content:
            failures.append(f"appSourceUnexpectedAuthority:{forbidden}")


def validate_bootstrap_source(content: str, failures: list[str]) -> None:
    required = (
        "#if os(iOS)",
        "public actor IOSClientReleaseBootstrapV1",
        "guard records.count <= 1",
        "guard records.allSatisfy({ $0.clientID == storage.clientID })",
        "routeHostIDs.isEmpty || routeHostIDs == [record.hostID]",
        "case pairedRouteConfigurationRequired(hostID: UUID)",
        ".pairedRouteConfigurationRequired(",
        "try await storage.custody.registerPublishedIdentity(record)",
        "guard try await storage.routes.snapshot(",
        "guard routeHostIDs.isEmpty",
        "renamex_np(",
        "UInt32(RENAME_EXCL)",
        ".completeUntilFirstUserAuthentication",
        "values.isExcludedFromBackup = true",
        "? 0o700\n                : 0o600",
        "guard snapshotValue.phase != .closed else { return }",
        "package func preparedStorageForReleaseComposition()",
    )
    for needle in required:
        if needle not in content:
            failures.append(f"bootstrapMissing:{needle}")
    for forbidden in (
        "public struct IOSClientReleaseStorageV1",
        "public let pairedHosts",
        "public let routes",
        "public let custody",
        "NWBrowser",
        "NWConnection",
        "URLSession",
        "AVCapture",
    ):
        if forbidden in content:
            failures.append(f"bootstrapUnexpectedAuthority:{forbidden}")


def validate_application_source(content: str, failures: list[str]) -> None:
    required = (
        "@Observable",
        "public final class IOSClientReleaseApplicationV1",
        "NetworkClientPairingApplicationCompositionV0",
        "ClientConfiguredRouteBootstrapAuthorityV1(",
        "expectedRevision: nil",
        "UIKitClientConfiguredRouteNetworkProductFactoryV1.make(",
        "try await product.applicationOwner.start()",
        "await product.interactiveRoles.close()",
        "case let .pairedRouteConfigurationRequired(hostID):",
        "phase: beginImmediately ? .routeSetup : .routeSetupDeferred",
        "UInt16.random(in: 8_000 ... 12_000)",
        "publish(phase: .idle)",
    )
    for needle in required:
        if needle not in content:
            failures.append(f"applicationCompositionMissing:{needle}")
    for forbidden in (
        "UserDefaults",
        "URLSession",
        "public let storage",
        "public let custody",
        "public let routes",
        "hostID.uuidString",
        "snapshot = .idle",
    ):
        if forbidden in content:
            failures.append(
                f"applicationCompositionUnexpectedAuthority:{forbidden}"
            )


def validate_workspace_source(content: str, failures: list[str]) -> None:
    required = (
        "public struct ClientPrimaryWorkspaceApplicationViewV1: View",
        "ClientPrimaryWorkspaceViewV0(",
        ".sheet(item: $selectedAction)",
        "ClientApprovedActionDetailViewV1(",
        "model.beginOperation(",
        "model.cancelOperation()",
        "model.queryOperation()",
        "case .terminal, .remoteRejected:",
    )
    for needle in required:
        if needle not in content:
            failures.append(f"workspaceCompositionMissing:{needle}")
    if "beginInteractiveControl" in content:
        failures.append("workspaceCompositionDuplicatesControlAuthority")


def validate_route_view_source(content: str, failures: list[str]) -> None:
    required = (
        "public struct ClientRouteBootstrapApplicationViewV1: View",
        "@State private var selections:",
        "ClientRouteBootstrapChoiceViewV1(",
        "selections.removeValue(forKey: endpoint)",
        "onComplete: onComplete",
    )
    for needle in required:
        if needle not in content:
            failures.append(f"routeViewCompositionMissing:{needle}")


def validate_self_tests(
    project_spec: str,
    generated_project: str,
    info_data: bytes,
    app_source: str,
    bootstrap_source: str,
    application_source: str,
    workspace_source: str,
    route_view_source: str,
    failures: list[str],
) -> None:
    mutated = project_spec.replace(
        "        product: CompanionClientPlatform",
        "        product: CompanionClient",
        1,
    )
    injected: list[str] = []
    validate_project_spec(mutated, injected)
    if not any(item.startswith("projectSpecDependencies:") for item in injected):
        failures.append("projectDependencyMutationAccepted")

    try:
        plist_value = plistlib.loads(info_data)
        plist_value["UIBackgroundModes"] = ["fetch"]
        mutated_info = plistlib.dumps(plist_value)
    except (plistlib.InvalidFileException, ValueError):
        mutated_info = info_data
    injected = []
    validate_info_plist(mutated_info, injected)
    if "infoPlistUnexpectedAuthority:UIBackgroundModes" not in injected:
        failures.append("backgroundModeMutationAccepted")

    injected = []
    validate_app_source(app_source + "\nlet _ = NWBrowser.self\n", injected)
    if "appSourceUnexpectedAuthority:NWBrowser" not in injected:
        failures.append("rawNetworkMutationAccepted")

    injected = []
    validate_bootstrap_source(
        bootstrap_source.replace(
            "values.isExcludedFromBackup = true",
            "values.isExcludedFromBackup = false",
            1,
        ),
        injected,
    )
    if "bootstrapMissing:values.isExcludedFromBackup = true" not in injected:
        failures.append("backupProtectionMutationAccepted")

    injected = []
    validate_application_source(
        application_source.replace("expectedRevision: nil", "expectedRevision: 1", 1),
        injected,
    )
    if not any(
        item.startswith("applicationCompositionMissing:expectedRevision: nil")
        for item in injected
    ):
        failures.append("unfencedRoutePublicationMutationAccepted")

    injected = []
    validate_workspace_source(
        workspace_source.replace(".sheet(item: $selectedAction)", ".sheet(isPresented: .constant(true))", 1),
        injected,
    )
    if not any(
        item.startswith("workspaceCompositionMissing:.sheet(item:")
        for item in injected
    ):
        failures.append("workspaceSheetMutationAccepted")

    injected = []
    validate_route_view_source(
        route_view_source.replace(
            "selections.removeValue(forKey: endpoint)",
            "_ = endpoint",
            1,
        ),
        injected,
    )
    if not any(
        item.startswith("routeViewCompositionMissing:selections.removeValue")
        for item in injected
    ):
        failures.append("routeDeselectionMutationAccepted")

    dependencies, _ = generated_products(
        generated_project, "MacCompanionIOS"
    )
    if dependencies == IOS_PRODUCTS:
        product_ids = [
            identifier
            for identifier, body in pbx_objects(generated_project).items()
            if "isa = XCSwiftPackageProductDependency;" in body
            and "productName = CompanionClientPlatform;" in body
        ]
        if len(product_ids) == 1:
            target = generated_native_target_block(
                generated_project, "MacCompanionIOS"
            )
            changed = target.replace(product_ids[0], "DEADBEEFDEADBEEFDEADBEEF", 1)
            mutated_generated = generated_project.replace(target, changed, 1)
            injected = []
            validate_generated_project(mutated_generated, injected)
            if not any(
                item.startswith("generatedProjectDependencies:")
                for item in injected
            ):
                failures.append("generatedDependencyMutationAccepted")


def main() -> int:
    failures: list[str] = []
    project_spec = read_text(PROJECT_SPEC, failures)
    generated_project = read_text(PROJECT_FILE, failures)
    app_source = read_text(APP_SOURCE, failures)
    bootstrap_source = read_text(BOOTSTRAP_SOURCE, failures)
    application_source = read_text(APPLICATION_SOURCE, failures)
    workspace_source = read_text(WORKSPACE_SOURCE, failures)
    route_view_source = read_text(ROUTE_VIEW_SOURCE, failures)
    try:
        info_data = INFO_PLIST.read_bytes()
    except OSError as error:
        failures.append(f"infoPlistUnreadable:{type(error).__name__}")
        info_data = b""

    validate_project_spec(project_spec, failures)
    validate_generated_project(generated_project, failures)
    validate_info_plist(info_data, failures)
    validate_app_source(app_source, failures)
    validate_bootstrap_source(bootstrap_source, failures)
    validate_application_source(application_source, failures)
    validate_workspace_source(workspace_source, failures)
    validate_route_view_source(route_view_source, failures)
    validate_self_tests(
        project_spec,
        generated_project,
        info_data,
        app_source,
        bootstrap_source,
        application_source,
        workspace_source,
        route_view_source,
        failures,
    )
    if failures:
        for failure in failures:
            print(f"permanent iOS target: {failure}", file=sys.stderr)
        return 1
    print(
        "Validated permanent iOS identity, privacy and permission declarations, "
        "narrow package authority, recoverable pairing/route composition, "
        "Observe/Act/Control workspace binding, and generated target binding."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
