#!/usr/bin/env python3

from __future__ import annotations

import plistlib
import re
import sys
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[1]
PROJECT_SPEC = REPOSITORY / "project.yml"
PROJECT_FILE = REPOSITORY / "MacCompanion.xcodeproj" / "project.pbxproj"
MAC_TARGET_DIRECTORY = REPOSITORY / "Apps" / "MacCompanionMac"
MAC_INFO_PLIST = MAC_TARGET_DIRECTORY / "Info.plist"
MAC_APPLICATION_PLATFORM_DIRECTORY = (
    REPOSITORY
    / "Packages"
    / "MacCompanionKit"
    / "Sources"
    / "CompanionMacApplicationPlatform"
)
LOGIN_COMPOSITION = (
    REPOSITORY
    / "Apps"
    / "MacCompanionMac"
    / "MacCompanionLoginRoleComposition.swift"
)
AGENT_TARGET_DIRECTORY = REPOSITORY / "Apps" / "MacCompanionAgent"
AGENT_INFO_PLIST = AGENT_TARGET_DIRECTORY / "Info.plist"
AGENT_ENTITLEMENTS = (
    AGENT_TARGET_DIRECTORY / "MacCompanionAgent.entitlements"
)
AGENT_APPLICATION_PLATFORM = (
    REPOSITORY
    / "Packages"
    / "MacCompanionKit"
    / "Sources"
    / "CompanionAgentApplicationPlatform"
    / "MacCompanionAgentInertSystemPreparationV1.swift"
)
AGENT_PREPARATION_FACADE = (
    REPOSITORY
    / "Packages"
    / "MacCompanionKit"
    / "Sources"
    / "CompanionAgentProductPlatform"
    / "MacAgentApplicationPreparationFacadeV1.swift"
)
AGENT_PRODUCT_BOOTSTRAP = (
    REPOSITORY
    / "Packages"
    / "MacCompanionKit"
    / "Sources"
    / "CompanionAgentProductPlatform"
    / "MacAgentProductBootstrapV1.swift"
)
AGENT_ENABLED_RUNTIME = (
    REPOSITORY
    / "Packages"
    / "MacCompanionKit"
    / "Sources"
    / "CompanionAgentProductPlatform"
    / "MacAgentEnabledProductRuntimeV1.swift"
)
LAUNCH_AGENT = (
    REPOSITORY
    / "Apps"
    / "MacCompanionMac"
    / "LaunchAgents"
    / "media.jenny.maccompanion.agent.plist"
)

AGENT_IDENTIFIER = "media.jenny.maccompanion.agent"
EXPECTED_LAUNCH_AGENT = {
    "BundleProgram": (
        "Contents/Helpers/MacCompanionAgent.app/Contents/MacOS/"
        "MacCompanionAgent"
    ),
    "KeepAlive": True,
    "Label": AGENT_IDENTIFIER,
    "MachServices": {AGENT_IDENTIFIER: True},
    "RunAtLoad": True,
}
EXPECTED_AGENT_INFO_PLIST = {
    "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
    "CFBundleDisplayName": "Mac Companion Agent",
    "CFBundleExecutable": "$(EXECUTABLE_NAME)",
    "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleName": "$(PRODUCT_NAME)",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "$(MARKETING_VERSION)",
    "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
    "LSBackgroundOnly": True,
    "NSHumanReadableCopyright": "Copyright 2026 Jenny Media LLC",
}
EXPECTED_AGENT_ENTITLEMENTS = {
    "keychain-access-groups": [
        "$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)"
    ]
}
EXPECTED_MAC_INFO_PLIST = {
    "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
    "CFBundleDisplayName": "Mac Companion",
    "CFBundleExecutable": "$(EXECUTABLE_NAME)",
    "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleName": "$(PRODUCT_NAME)",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "$(MARKETING_VERSION)",
    "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
    "LSApplicationCategoryType": "public.app-category.utilities",
    "LSUIElement": True,
    "MacCompanionUpdateAuthorityProfile": (
        "$(MACCOMPANION_UPDATE_AUTHORITY_PROFILE)"
    ),
    "MacCompanionUpdateChannel": "$(MACCOMPANION_UPDATE_CHANNEL)",
    "MacCompanionUpdateFeedURL": "$(MACCOMPANION_UPDATE_FEED_URL)",
    "MacCompanionUpdateUserInitiatedCheckProfile": (
        "$(MACCOMPANION_UPDATE_USER_INITIATED_CHECK_PROFILE)"
    ),
    "NSBonjourServices": ["_maccompanion._tcp"],
    "NSHumanReadableCopyright": "Copyright 2026 Jenny Media LLC",
    "NSLocalNetworkUsageDescription": (
        "Let your paired devices find and connect directly to this Mac on your "
        "local network. Mac Companion does not use a vendor relay."
    ),
    "SUAllowsAutomaticUpdates": False,
    "SUAutomaticallyUpdate": False,
    "SUEnableAutomaticChecks": False,
    "SUEnableSystemProfiling": False,
    "SUPublicEDKey": "$(MACCOMPANION_SPARKLE_PUBLIC_ED_KEY)",
    "SURequireSignedFeed": True,
    "SUSendProfileInfo": False,
    "SUVerifyUpdateBeforeExtraction": True,
}


def read_text(path: Path, failures: list[str]) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as error:
        failures.append(
            f"unreadable:{path.relative_to(REPOSITORY)}:{type(error).__name__}"
        )
        return ""


def read_swift_target(directory: Path, failures: list[str]) -> str:
    sources = sorted(directory.rglob("*.swift"))
    if not sources:
        failures.append(f"noSwiftSources:{directory.relative_to(REPOSITORY)}")
        return ""
    return "\n".join(read_text(source, failures) for source in sources)


def require_count(
    content: str,
    needle: str,
    count: int,
    label: str,
    failures: list[str],
) -> None:
    actual = content.count(needle)
    if actual != count:
        failures.append(f"{label}:expected={count}:actual={actual}")


def yaml_target_block(content: str, target: str) -> str:
    match = re.search(
        rf"^  {re.escape(target)}:\n(?P<body>.*?)(?=^  \S|\Z)",
        content,
        re.MULTILINE | re.DOTALL,
    )
    return match.group("body") if match else ""


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


def pbx_product_names_by_identifier(content: str) -> dict[str, str]:
    names: dict[str, str] = {}
    for identifier, body in pbx_objects(content).items():
        if "isa = XCSwiftPackageProductDependency;" not in body:
            continue
        match = re.search(r"productName = ([^;]+);", body)
        if match:
            names[identifier] = match.group(1).strip().strip('"')
    return names


def generated_target_product_lists(
    content: str,
    target_name: str,
) -> tuple[list[str], list[str]]:
    objects = pbx_objects(content)
    product_names = pbx_product_names_by_identifier(content)
    target = generated_native_target_block(content, target_name)

    dependency_match = re.search(
        r"packageProductDependencies = \((?P<dependencies>.*?)\);",
        target,
        re.DOTALL,
    )
    dependency_ids = re.findall(
        r"\b[0-9A-F]{24}\b",
        dependency_match.group("dependencies") if dependency_match else "",
    )
    dependencies = [
        product_names.get(identifier, f"unresolved:{identifier}")
        for identifier in dependency_ids
    ]

    build_phases_match = re.search(
        r"buildPhases = \((?P<phases>.*?)\);",
        target,
        re.DOTALL,
    )
    build_phase_ids = re.findall(
        r"\b[0-9A-F]{24}\b",
        build_phases_match.group("phases") if build_phases_match else "",
    )
    framework_phase_ids = [
        identifier for identifier in build_phase_ids
        if "isa = PBXFrameworksBuildPhase;" in objects.get(identifier, "")
    ]
    framework_products: list[str] = []
    if len(framework_phase_ids) != 1:
        framework_products.append(
            f"frameworkPhaseCount:{len(framework_phase_ids)}"
        )
    else:
        phase = objects[framework_phase_ids[0]]
        files_match = re.search(
            r"files = \((?P<files>.*?)\);",
            phase,
            re.DOTALL,
        )
        build_file_ids = re.findall(
            r"\b[0-9A-F]{24}\b",
            files_match.group("files") if files_match else "",
        )
        for build_file_id in build_file_ids:
            build_file = objects.get(build_file_id, "")
            product_ref = re.search(
                r"productRef = ([0-9A-F]{24})\b",
                build_file,
            )
            if not product_ref:
                framework_products.append(
                    f"unresolvedBuildFile:{build_file_id}"
                )
                continue
            identifier = product_ref.group(1)
            framework_products.append(
                product_names.get(identifier, f"unresolved:{identifier}")
            )
    return dependencies, framework_products


def require_exact_agent_products(
    content: str,
    generated: bool,
    failures: list[str],
) -> None:
    expected = ["CompanionAgentApplicationPlatform"]
    if generated:
        dependencies, frameworks = generated_target_product_lists(
            content,
            "MacCompanionAgent",
        )
        for label, actual in (
            ("generatedAgentDependencyProducts", dependencies),
            ("generatedAgentFrameworkProducts", frameworks),
        ):
            if actual != expected:
                failures.append(
                    f"{label}:expected={','.join(expected)}:"
                    f"actual={','.join(actual)}"
                )
        return
    else:
        block = yaml_target_block(content, "MacCompanionAgent")
        actual = re.findall(
            r"^\s+product:\s+([^\s#]+)\s*$",
            block,
            re.MULTILINE,
        )
        label = "projectSpecAgentDependencyProducts"
    if actual != expected:
        failures.append(
            f"{label}:expected={','.join(expected)}:"
            f"actual={','.join(actual)}"
        )


def require_exact_mac_products(
    content: str,
    generated: bool,
    failures: list[str],
) -> None:
    expected = [
        "CompanionAgent",
        "CompanionAgentPlatform",
        "CompanionLocalXPCPlatform",
        "CompanionLifecycle",
        "CompanionMacApp",
        "CompanionMacApplicationPlatform",
        "CompanionMacUI",
        "Sparkle",
    ]
    if generated:
        dependencies, frameworks = generated_target_product_lists(
            content,
            "MacCompanion",
        )
        for label, actual in (
            ("generatedMacDependencyProducts", dependencies),
            ("generatedMacFrameworkProducts", frameworks),
        ):
            if actual != expected:
                failures.append(
                    f"{label}:expected={','.join(expected)}:"
                    f"actual={','.join(actual)}"
                )
        return
    block = yaml_target_block(content, "MacCompanion")
    actual = re.findall(
        r"^\s+product:\s+([^\s#]+)\s*$",
        block,
        re.MULTILINE,
    )
    if actual != expected:
        failures.append(
            "projectSpecMacDependencyProducts:"
            f"expected={','.join(expected)}:actual={','.join(actual)}"
        )


def validate_project_spec(content: str, failures: list[str]) -> None:
    required = {
        "agentTarget": (
            "  MacCompanionAgent:\n"
            "    type: application\n"
            "    platform: macOS"
        ),
        "agentInfo": "      path: Apps/MacCompanionAgent/Info.plist",
        "agentSource": "      - path: Apps/MacCompanionAgent",
        "agentApplicationPlatform": (
            "      - package: MacCompanionKit\n"
            "        product: CompanionAgentApplicationPlatform"
        ),
        "agentEmbed": (
            "      - target: MacCompanionAgent\n"
            "        embed: true\n"
            "        link: false\n"
            "        codeSign: true\n"
            "        copy:\n"
            "          destination: wrapper\n"
            "          subpath: Contents/Helpers"
        ),
        "lifecycleProducts": (
            "      - package: MacCompanionKit\n"
            "        product: CompanionAgent\n"
            "      - package: MacCompanionKit\n"
            "        product: CompanionAgentPlatform"
        ),
        "launchAgentSource": (
            "      - path: Apps/MacCompanionMac/LaunchAgents/"
            "media.jenny.maccompanion.agent.plist"
        ),
        "launchAgentDestination": (
            "            subpath: Contents/Library/LaunchAgents"
        ),
        "agentIdentifier": (
            f"        PRODUCT_BUNDLE_IDENTIFIER: {AGENT_IDENTIFIER}"
        ),
        "agentEntitlements": (
            "        CODE_SIGN_ENTITLEMENTS: "
            "Apps/MacCompanionAgent/MacCompanionAgent.entitlements"
        ),
        "agentSkipInstall": "        SKIP_INSTALL: YES",
    }
    for label, needle in required.items():
        require_count(content, needle, 1, label, failures)
    require_exact_agent_products(content, generated=False, failures=failures)
    require_exact_mac_products(content, generated=False, failures=failures)
    require_count(
        content,
        "        product: CompanionLocalXPCPlatform",
        1,
        "localXPCProducts",
        failures,
    )
    require_count(
        content, "        ENABLE_APP_SANDBOX: NO", 2, "noSandboxTargets", failures
    )
    require_count(
        content, "        CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO", 2,
        "noBaseEntitlementsTargets", failures
    )
    for forbidden in (
        "DEVELOPMENT_TEAM:",
        "PROVISIONING_PROFILE",
    ):
        if forbidden in content:
            failures.append(f"trackedSigningAuthority:{forbidden.rstrip(':')}")
    for match in re.finditer(
        r'^\s*CODE_SIGN_IDENTITY:\s*(.*?)\s*$',
        content,
        re.MULTILINE,
    ):
        if match.group(1) != '""':
            failures.append("trackedSigningAuthority:CODE_SIGN_IDENTITY")
    if "product: CompanionAgentProductPlatform" in content:
        failures.append("projectSpecLinksAgentProductPlatform")


def validate_generated_project(content: str, failures: list[str]) -> None:
    require_count(
        content,
        "CompanionAgentApplicationPlatform",
        6,
        "generatedAgentApplicationPlatform",
        failures,
    )
    require_exact_agent_products(content, generated=True, failures=failures)
    require_exact_mac_products(content, generated=True, failures=failures)
    agent_target = generated_native_target_block(content, "MacCompanionAgent")
    require_count(
        agent_target,
        'productType = "com.apple.product-type.application";',
        1,
        "agentApplicationProduct",
        failures,
    )
    require_count(
        content,
        "ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, );",
        1,
        "embedCodeSign",
        failures,
    )
    require_count(
        content,
        "dstPath = Contents/Helpers;",
        1,
        "agentEmbedDestination",
        failures,
    )
    require_count(
        content,
        f"PRODUCT_BUNDLE_IDENTIFIER = {AGENT_IDENTIFIER};",
        2,
        "generatedAgentIdentifier",
        failures,
    )
    require_count(
        content,
        "CODE_SIGN_ENTITLEMENTS = "
        "Apps/MacCompanionAgent/MacCompanionAgent.entitlements;",
        2,
        "generatedAgentEntitlements",
        failures,
    )
    require_count(
        content,
        "MacCompanionAgent.app in Embed Dependencies",
        2,
        "generatedAgentEmbed",
        failures,
    )
    if re.search(r"\b(?:DEVELOPMENT_TEAM|PROVISIONING_PROFILE) =", content):
        failures.append("generatedProjectContainsSigningAuthority")
    if "CompanionAgentProductPlatform" in content:
        failures.append("generatedProjectLinksAgentProductPlatform")


def validate_launch_agent(failures: list[str]) -> None:
    try:
        with LAUNCH_AGENT.open("rb") as handle:
            value = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException, ValueError) as error:
        failures.append(f"launchAgentUnreadable:{type(error).__name__}")
        return
    if value != EXPECTED_LAUNCH_AGENT:
        failures.append("launchAgentSchemaOrValueMismatch")


def validate_mac_info_plist(failures: list[str]) -> None:
    try:
        with MAC_INFO_PLIST.open("rb") as handle:
            value = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException, ValueError) as error:
        failures.append(f"macInfoPlistUnreadable:{type(error).__name__}")
        return
    if value != EXPECTED_MAC_INFO_PLIST:
        failures.append("macInfoPlistSchemaOrValueMismatch")


def validate_agent_bundle_metadata(failures: list[str]) -> None:
    for path, expected, label in (
        (AGENT_INFO_PLIST, EXPECTED_AGENT_INFO_PLIST, "agentInfoPlist"),
        (AGENT_ENTITLEMENTS, EXPECTED_AGENT_ENTITLEMENTS, "agentEntitlements"),
    ):
        try:
            with path.open("rb") as handle:
                value = plistlib.load(handle)
        except (OSError, plistlib.InvalidFileException, ValueError) as error:
            failures.append(f"{label}Unreadable:{type(error).__name__}")
            continue
        if value != expected:
            failures.append(f"{label}SchemaOrValueMismatch")


def validate_inert_update_adapter(
    mac_application: str,
    failures: list[str],
) -> None:
    for needle in (
        "final class MacCompanionSparkleAdapterV0",
        "final class MacCompanionSparkleUserDriverV0",
        "SPUUserDriver",
        "MacUpdateReleaseAuthorityV0(",
        "SPUStandardUserDriver(",
        "SPUUpdater(",
        "updater.sendsSystemProfile = false",
        "updater.automaticallyChecksForUpdates = false",
        "updater.automaticallyDownloadsUpdates = false",
        "updater.httpHeaders = nil",
        "updater.checkForUpdateInformation()",
        "updater.checkForUpdates()",
        "MacUpdateUserInitiatedCheckAuthorityV0",
        "updateCheck == expectedUpdateCheck",
        "MacCompanionUpdateUserInitiatedCheckProfile",
        "func feedParameters(",
        "func allowedSystemProfileKeys(",
        "shouldProceedWithUpdate item: SUAppcastItem",
        "MacUpdateFeedCandidateV0(",
        "currentBuild: currentBuild",
        "itemChannel: item.channel",
        "informationOnly: item.isInformationOnlyUpdate",
        "installationType: item.installationType",
        "deltaCount: item.deltaUpdates?.count ?? 0",
        "private var probePermit = false",
        "willExtractUpdate item: SUAppcastItem",
        "didExtractUpdate item: SUAppcastItem",
        "correlation.installerDidStart(",
        "func showReady(",
        "readyToInstallHandler(reply)",
        "MacUpdatePreparedInstallerReplyOwnerV0",
        "preparedInstaller.cancel()",
        "case .install:",
        "reply(.install)",
        "reply(.skip)",
        "await correlation.cancel()",
        "case notConfigured",
        "updates.start()",
        "MacCompanionUpdateFooter(adapter: updates)",
        "final class MacCompanionUpdateRuntimeCompositionV0",
        "let updateRuntime: MacCompanionUpdateRuntimeCompositionV0?",
        "candidateBuild: admission.candidateBuild",
        "controlState: indicator.updateControlState",
        "func applicationShouldTerminate(",
        "return .terminateLater",
        "await updates.prepareForApplicationTermination()",
        "NSApp.reply(toApplicationShouldTerminate: true)",
        "updates.installRuntimeComposition(updateRuntime)",
        ".reachedReadyToInstall()",
        ".makeInstallationApplication(",
        "func applicationDidResignActive(",
        "updates.applicationForegroundDidChange(false)",
        "Button(\"Install and Restart\")",
        "Button(\"Not Now\")",
        "await installationApplication",
        ".applicationTerminationRequested()",
        "readinessTask?.cancel()",
        "await readinessTask.value",
    ):
        if needle not in mac_application:
            failures.append(f"macUpdateAdapterMissing:{needle}")
    for forbidden in (
        ".checkForUpdatesInBackground()",
        ".setFeedURL(",
        "URLSession",
        "updater.sendsSystemProfile = true",
        "updater.automaticallyChecksForUpdates = true",
        "updater.automaticallyDownloadsUpdates = true",
        "takePendingValidationCorrelation",
        ".startPreparedUpdate()",
    ):
        if forbidden in mac_application:
            failures.append(f"macUpdateAdapterUnexpectedAuthority:{forbidden}")
    if mac_application.count("reply(.install)") != 1:
        failures.append(
            "macUpdateAdapterUnexpectedAuthority:reply(.install)"
        )
    if not re.search(
        r"case \.install:\s+reply\(\.install\)\s+"
        r"case \.skip:\s+reply\(\.skip\)",
        mac_application,
    ):
        failures.append("macUpdatePreparedReplyMappingMismatch")
    if mac_application.count("updater.checkForUpdates()") != 1:
        failures.append(
            "macUpdateAdapterUnexpectedAuthority:updater.checkForUpdates()"
        )
    if not re.search(
        r"if userInitiatedCheckAuthority == nil \{\s*"
        r"updater\.checkForUpdateInformation\(\)\s*"
        r"\} else \{\s*updater\.checkForUpdates\(\)\s*\}",
        mac_application,
    ):
        failures.append("macUpdateUserCheckAuthorityMappingMismatch")


def validate_narrow_agent_source(content: str, failures: list[str]) -> None:
    code = "\n".join(
        line.split("//", 1)[0] for line in content.splitlines()
    )
    for needle in (
        "import CompanionAgentApplicationPlatform",
        "@main",
        "import Darwin",
        "enum MacCompanionAgentMain",
        "static func main() async",
        "let outcome: MacCompanionAgentLocalServiceStartupOutcomeV1",
        "MacCompanionAgentLocalServiceStartupV1.start()",
        "case .retryAfterFirstUnlock:",
        "case .running(let owner):",
        "owner.waitForRestartRequest()",
        "owner.finish()",
    ):
        require_count(code, needle, 1, f"agentSource:{needle}", failures)
    for needle in (
        "import Dispatch",
        "dispatchMain()",
        "withExtendedLifetime",
        "Task {",
        "SMAppService",
        "NWListener",
        ".register(",
        "UserDefaults",
        "import CompanionLocalXPCPlatform",
        "MacLocalXPCServerV1",
        ".authenticationOnly",
        ".disabledRemoteAccessBootstrap",
        ".menuLifecycleReadinessAndStatus",
        ".menuLifecycleReadinessStatusAndPresentation",
        "AgentPrimaryServicesV1",
        "Keychain",
        "SQLite",
        ".menuLifecycleReadiness",
        "MacLocalXPCStatusReaderV1",
        "MacLocalXPCAgentProductV1",
        "MacAgentReleaseStorageV1",
        "CompanionAgentProductPlatform",
        "MacAgentProductBootstrapV1",
        "MacAgentPreparedProductV1",
        "statusReader:",
        "startLocalAuthorization",
        "startAndComposeNetworkPairingProduct",
        "startNetworkListener",
        "prepareNetworkListener",
        "MacAgentApplicationPreparationFacadeV1",
        "MacCompanionAgentInertSystemPreparationV1.prepare()",
        "import CompanionAgentNetworkPlatform",
        "import CompanionAgentPlatform",
        "prepareAndStartAuthentication",
        "startAuthentication:",
        "makeAuthenticationOnly:",
    ):
        if needle in code:
            failures.append(f"agentSourceUnexpectedAuthority:{needle}")


def validate_single_owner_agent_service_selection(
    application_platform: str,
    preparation_facade: str,
    product_bootstrap: str,
    enabled_runtime: str,
    failures: list[str],
) -> None:
    for needle in (
        "MacCompanionAgentLocalServiceStartupV1",
        "MacCompanionAgentLocalServiceOwnerV1",
        "MacCompanionAgentAuthenticationOnlyRuntimeV1",
        "MacCompanionAgentDisabledBootstrapRuntimeV1",
        "case .enabledProduct:",
        "case .disabledRemoteAccessBootstrap:",
        "case .deferred(.firstUnlockRequired):",
        "disabledRemoteAccessBootstrapIntentStore()",
        "makeAuthenticationOnly()",
        "makeDisabledBootstrap(intentStore, restartRequest)",
    ):
        if needle not in application_platform:
            failures.append(f"agentApplicationSelectionMissing:{needle}")
    for forbidden in (
        "menuLifecycleReadinessStatusAndPresentation",
        "afterAgentBootstrapWithMenuPresentation",
        "MacLocalXPCAuthenticatedMenuSurfacesV1",
    ):
        if forbidden in application_platform:
            failures.append(f"agentApplicationSelectionTooBroad:{forbidden}")
    require_count(
        preparation_facade,
        ".prepareInert(",
        1,
        "agentPreparationFullFactory",
        failures,
    )
    if ".prepareStatusOnlyInert(" in preparation_facade:
        failures.append("agentPreparationRetainsStatusOnlyFactory")
    for needle in (
        "public static let listenerPort: UInt16 = 59_653",
        "MacAgentEnabledProductRuntimeV1",
        "startAndComposeNetworkPairingProduct(",
        "startNetworkListener(",
        "SystemAgentLocalPairingTimeSourceV1()",
        "initialPairingPolicyRevision",
        "await product.finish()",
    ):
        if needle not in enabled_runtime:
            failures.append(f"agentEnabledRuntimeMissing:{needle}")
    compose = enabled_runtime.find("try await product.composeForEnabledRuntime(")
    listener = enabled_runtime.find(
        "try await product.startListenerForEnabledRuntime("
    )
    if compose < 0 or listener < 0 or compose >= listener:
        failures.append("agentEnabledRuntimeOrder")


def uncommented_swift(content: str) -> str:
    return "\n".join(line.split("//", 1)[0] for line in content.splitlines())


def validate_login_role_composition(
    composition: str,
    application: str,
    failures: list[str],
) -> None:
    composition_code = uncommented_swift(composition)
    application_code = uncommented_swift(application)
    required = {
        "agentPlistIdentity": (
            'static let agentPlistName = '
            '"media.jenny.maccompanion.agent.plist"'
        ),
        "agentService": "agentService: SMAppService = .agent(",
        "agentPlistBinding": (
            "plistName: MacCompanionLoginRoleComposition.agentPlistName"
        ),
        "menuService": "menuAppService: SMAppService = .mainApp",
        "loginExecutor": "executor = AgentLoginRoleEffectExecutorV1(",
        "applicationRetention": (
            "let loginRoles = MacCompanionLoginRoleComposition()"
        ),
        "setupAgentOwnership": "agent: loginRoles.agent",
        "setupMenuOwnership": "menuApp: loginRoles.menuApp",
        "registrationInspection": (
            "agentRegistration: loginRoles.agentRaw"
        ),
    }
    for label, needle in required.items():
        haystack = (
            application_code
            if label in {
                "applicationRetention", "setupAgentOwnership",
                "setupMenuOwnership", "registrationInspection",
            }
            else composition_code
        )
        require_count(haystack, needle, 1, label, failures)
    require_count(
        composition_code,
        "AgentLoginRoleConvergingServiceV1(",
        2,
        "convergingLoginRoles",
        failures,
    )
    require_count(
        composition_code,
        "SMAppServiceRawLoginRoleV1(service:",
        2,
        "rawLoginRoles",
        failures,
    )
    for label, needle in {
        "menuApplicationPlatformImport": (
            "import CompanionMacApplicationPlatform"
        ),
        "packageOwnedApplicationDelegate": (
            "@NSApplicationDelegateAdaptor("
        ),
        "applicationDelegateType": (
            "MacCompanionApplicationDelegate.self"
        ),
        "standardAdministrationWindow": (
            'Window(\n            "Mac Companion",\n'
            "            id: MacCompanionSceneV1.mainWindowID"
        ),
        "persistentStatusItem": "MenuBarExtra {",
        "statusItemWindowReopen": (
            "openWindow(id: MacCompanionSceneV1.mainWindowID)"
        ),
        "applicationDelegateProduct": (
            "application: applicationDelegate.product"
        ),
        "setupApplication": (
            "let setup = MacRemoteAccessSetupApplicationV1("
        ),
        "productApplication": (
            "product = MacCompanionProductApplicationV1("
        ),
        "explicitSetupBegin": (
            "await application.setup.begin()"
        ),
        "explicitSetupConfirmation": (
            "await application.setup.confirm()"
        ),
        "explicitSetupDecline": (
            "await application.setup.decline()"
        ),
        "dashboardTypedSource": (
            "private var source: MacAgentDashboardSourceV0 { "
            "application.source }"
        ),
        "dashboardRetryForwarding": (
            "_ = await application.retryStatus()"
        ),
    }.items():
        expected_count = {
            "menuApplicationPlatformImport": 3,
            "applicationDelegateProduct": 2,
        }.get(label, 1)
        require_count(
            application_code,
            needle,
            expected_count,
            label,
            failures,
        )
    for needle in (
        "MacLocalXPCDashboardProductV1(",
        "MacAgentDashboardApplicationOwnerV0(",
        "MacAgentReleaseStorageV1",
        "CompanionAgentProductPlatform",
        "MacAgentProductBootstrapV1",
        "MacAgentPreparedProductV1",
        "MacCompanionDashboardApplicationV1()",
        "Task.sleep",
        "application.start()",
        "dashboard.start()",
    ):
        if needle in application_code:
            failures.append(f"menuSourceUnexpectedAuthority:{needle}")
    for needle in (".register(", ".unregister(", "setEnabled("):
        if needle in composition_code or needle in application_code:
            failures.append(f"implicitLoginMutation:{needle}")


def validate_menu_application_lifecycle_owner(
    platform_source: str,
    failures: list[str],
) -> None:
    marker = "public final class MacCompanionProductApplicationV1 {"
    start = platform_source.find(marker)
    delegate = platform_source[start:] if start >= 0 else ""
    for needle in (
        marker,
        "public private(set) var route: MacCompanionProductRouteV1",
        "public private(set) var dashboard:",
        "public let setup: MacRemoteAccessSetupApplicationV1",
        "setup.installStateObserver",
        "public func start() async",
        "switch await agentRegistration.status()",
        "case .notRegistered:",
        "case .enabled:",
        "try await candidate.start()",
        "public func finish() async",
        "await setup.finish()",
        "await dashboard?.finish()",
    ):
        if needle not in delegate:
            failures.append(f"menuLifecycleOwnerMissing:{needle}")
    require_count(
        delegate,
        "try await candidate.start()",
        1,
        "menuLifecycleOwnerSingleStart",
        failures,
    )
    for forbidden in (
        "MacLocalXPCDashboardProductV1(",
        "MacLocalXPCClientV1(",
        "menuLifecycleReadinessStatusAndPresentation",
        "MacLocalXPCMenuPresentationReceiverSurfacesV1",
    ):
        if forbidden in delegate:
            failures.append(f"menuLifecycleOwnerUnexpectedAuthority:{forbidden}")


def validate_product_inertness_self_tests(
    agent_source: str,
    login_composition: str,
    mac_application: str,
    failures: list[str],
) -> None:
    injected = "\nlet _ = try MacAgentReleaseStorageV1.systemDefault()\n"

    agent_failures: list[str] = []
    validate_narrow_agent_source(agent_source + injected, agent_failures)
    if "agentSourceUnexpectedAuthority:MacAgentReleaseStorageV1" not in agent_failures:
        failures.append("agentStorageActivationFixtureAccepted")

    menu_failures: list[str] = []
    validate_login_role_composition(
        login_composition,
        mac_application + injected,
        menu_failures,
    )
    if "menuSourceUnexpectedAuthority:MacAgentReleaseStorageV1" not in menu_failures:
        failures.append("menuStorageActivationFixtureAccepted")

    product_injected = (
        "\nimport CompanionAgentProductPlatform\n"
        "let _ = MacAgentProductBootstrapV1.self\n"
    )
    agent_failures = []
    validate_narrow_agent_source(
        agent_source + product_injected,
        agent_failures,
    )
    if (
        "agentSourceUnexpectedAuthority:MacAgentProductBootstrapV1"
        not in agent_failures
    ):
        failures.append("agentProductActivationFixtureAccepted")

    menu_failures = []
    validate_login_role_composition(
        login_composition,
        mac_application + product_injected,
        menu_failures,
    )
    if (
        "menuSourceUnexpectedAuthority:MacAgentProductBootstrapV1"
        not in menu_failures
    ):
        failures.append("menuProductActivationFixtureAccepted")

    menu_start_failures: list[str] = []
    validate_login_role_composition(
        login_composition,
        mac_application
        + "\nfunc injectedActivation() async throws { "
        + "try await application.start() }\n",
        menu_start_failures,
    )
    if (
        "menuSourceUnexpectedAuthority:application.start()"
        not in menu_start_failures
    ):
        failures.append("menuTransportActivationFixtureAccepted")

    for label, injection, expected in (
        (
            "rawLocalXPCImport",
            "\nimport CompanionLocalXPCPlatform\n",
            "agentSourceUnexpectedAuthority:import CompanionLocalXPCPlatform",
        ),
        (
            "rawAuthenticationProfile",
            "\nlet _ = MacLocalXPCServerV1(profile: .authenticationOnly) { _ in }\n",
            "agentSourceUnexpectedAuthority:MacLocalXPCServerV1",
        ),
        (
            "rawStatusProfile",
            "\nlet _ = MacLocalXPCServerProfileV1.menuLifecycleReadinessAndStatus\n",
            "agentSourceUnexpectedAuthority:.menuLifecycleReadinessAndStatus",
        ),
        (
            "presentationProfile",
            "\nlet _ = MacLocalXPCServerProfileV1.menuLifecycleReadinessStatusAndPresentation\n",
            "agentSourceUnexpectedAuthority:.menuLifecycleReadinessStatusAndPresentation",
        ),
        (
            "secondServiceStart",
            "\nlet _ = try await MacCompanionAgentLocalServiceStartupV1.start()\n",
            "agentSource:MacCompanionAgentLocalServiceStartupV1.start()",
        ),
    ):
        injected_failures: list[str] = []
        validate_narrow_agent_source(
            agent_source + injection,
            injected_failures,
        )
        if not any(
            failure == expected or failure.startswith(expected + ":")
            for failure in injected_failures
        ):
            failures.append(f"agent{label}FixtureAccepted")


def validate_single_owner_agent_service_selection_self_tests(
    application_platform: str,
    preparation_facade: str,
    product_bootstrap: str,
    enabled_runtime: str,
    failures: list[str],
) -> None:
    status_only_preparation = preparation_facade.replace(
        ".prepareInert(",
        ".prepareStatusOnlyInert(",
        1,
    )
    injected_failures: list[str] = []
    validate_single_owner_agent_service_selection(
        application_platform,
        status_only_preparation,
        product_bootstrap,
        enabled_runtime,
        injected_failures,
    )
    if "agentPreparationFullFactory:expected=1:actual=0" not in injected_failures:
        failures.append("agentStatusOnlyPreparationFixtureAccepted")

    injected_failures = []
    validate_single_owner_agent_service_selection(
        application_platform
        + "\nlet _: MacLocalXPCAuthenticatedMenuSurfacesV1? = nil\n",
        preparation_facade,
        product_bootstrap,
        enabled_runtime,
        injected_failures,
    )
    if not any(
        failure.startswith("agentApplicationSelectionTooBroad:")
        for failure in injected_failures
    ):
        failures.append("agentPresentationSurfaceFixtureAccepted")

    reordered_runtime = enabled_runtime.replace(
        "try await product.composeForEnabledRuntime(",
        "try await product.startListenerForEnabledRuntime(",
        1,
    )
    injected_failures = []
    validate_single_owner_agent_service_selection(
        application_platform,
        preparation_facade,
        product_bootstrap,
        reordered_runtime,
        injected_failures,
    )
    if "agentEnabledRuntimeOrder" not in injected_failures:
        failures.append("agentEnabledRuntimeOrderFixtureAccepted")


def validate_product_link_inertness_self_tests(
    project_spec: str,
    generated_project: str,
    failures: list[str],
) -> None:
    spec_failures: list[str] = []
    validate_project_spec(
        project_spec
        + "\n      - package: MacCompanionKit\n"
        + "        product: CompanionAgentProductPlatform\n",
        spec_failures,
    )
    if "projectSpecLinksAgentProductPlatform" not in spec_failures:
        failures.append("projectProductLinkFixtureAccepted")

    generated_failures: list[str] = []
    validate_generated_project(
        generated_project + "\nCompanionAgentProductPlatform\n",
        generated_failures,
    )
    if "generatedProjectLinksAgentProductPlatform" not in generated_failures:
        failures.append("generatedProductLinkFixtureAccepted")

    for product in (
        "CompanionAgentPlatform",
        "CompanionAgentNetworkPlatform",
        "CompanionMacUI",
        "ArbitraryAuthority",
        "CompanionLocalXPCPlatform",
    ):
        spec_mutation = project_spec.replace(
            "        product: CompanionAgentApplicationPlatform\n",
            "        product: CompanionAgentApplicationPlatform\n"
            "      - package: MacCompanionKit\n"
            f"        product: {product}\n",
            1,
        )
        spec_failures = []
        validate_project_spec(spec_mutation, spec_failures)
        if not any(
            failure.startswith("projectSpecAgentDependencyProducts:")
            for failure in spec_failures
        ):
            failures.append(f"projectExtraAgentProductFixtureAccepted:{product}")

        marker = "packageProductDependencies = ("
        agent_start = generated_project.find("name = MacCompanionAgent;")
        dependency_start = generated_project.find(marker, agent_start)
        generated_mutation = generated_project
        if dependency_start >= 0:
            insertion = dependency_start + len(marker)
            generated_mutation = (
                generated_project[:insertion]
                + f"\n\t\t\t\tDEADBEEFDEADBEEFDEADBEEF /* {product} */,"
                + generated_project[insertion:]
            )
        generated_failures = []
        validate_generated_project(generated_mutation, generated_failures)
        if not any(
            failure.startswith("generatedAgentDependencyProducts:")
            for failure in generated_failures
        ):
            failures.append(
                f"generatedExtraAgentProductFixtureAccepted:{product}"
            )

    relocated_spec = project_spec.replace(
        "      - package: MacCompanionKit\n"
        "        product: CompanionAgentApplicationPlatform\n",
        "",
        1,
    )
    relocated_failures: list[str] = []
    validate_project_spec(relocated_spec, relocated_failures)
    if not any(
        failure.startswith("projectSpecAgentDependencyProducts:")
        for failure in relocated_failures
    ):
        failures.append("projectRelocatedAgentWrapperFixtureAccepted")

    product_names = pbx_product_names_by_identifier(generated_project)
    application_ids = [
        identifier for identifier, name in product_names.items()
        if name == "CompanionAgentApplicationPlatform"
    ]
    wrong_ids = [
        identifier for identifier, name in product_names.items()
        if name == "CompanionAgentPlatform"
    ]
    semantic_mutation = generated_project
    if len(application_ids) == 1 and wrong_ids:
        application_id = application_ids[0]
        wrong_id = wrong_ids[0]
        agent_block = generated_native_target_block(
            semantic_mutation,
            "MacCompanionAgent",
        )
        dependency_match = re.search(
            r"packageProductDependencies = \((?P<dependencies>.*?)\);",
            agent_block,
            re.DOTALL,
        )
        if dependency_match:
            dependencies = dependency_match.group("dependencies")
            changed = dependencies.replace(application_id, wrong_id, 1)
            semantic_mutation = semantic_mutation.replace(
                dependencies,
                changed,
                1,
            )
        semantic_mutation = semantic_mutation.replace(
            f"productRef = {application_id}",
            f"productRef = {wrong_id}",
            1,
        )
    semantic_failures: list[str] = []
    validate_generated_project(semantic_mutation, semantic_failures)
    for label in (
        "generatedAgentDependencyProducts:",
        "generatedAgentFrameworkProducts:",
    ):
        if not any(failure.startswith(label) for failure in semantic_failures):
            failures.append(
                f"generatedCommentPreservingSubstitutionAccepted:{label}"
            )

    missing_mac_wrapper = project_spec.replace(
        "      - package: MacCompanionKit\n"
        "        product: CompanionMacApplicationPlatform\n",
        "",
        1,
    )
    missing_mac_failures: list[str] = []
    validate_project_spec(missing_mac_wrapper, missing_mac_failures)
    if not any(
        failure.startswith("projectSpecMacDependencyProducts:")
        for failure in missing_mac_failures
    ):
        failures.append("projectMissingMacApplicationWrapperFixtureAccepted")

    mac_wrapper_ids = [
        identifier for identifier, name in product_names.items()
        if name == "CompanionMacApplicationPlatform"
    ]
    mac_ui_ids = [
        identifier for identifier, name in product_names.items()
        if name == "CompanionMacUI"
    ]
    mac_semantic_mutation = generated_project
    if len(mac_wrapper_ids) == 1 and len(mac_ui_ids) == 1:
        wrapper_id = mac_wrapper_ids[0]
        wrong_id = mac_ui_ids[0]
        mac_block = generated_native_target_block(
            mac_semantic_mutation,
            "MacCompanion",
        )
        dependency_match = re.search(
            r"packageProductDependencies = \((?P<dependencies>.*?)\);",
            mac_block,
            re.DOTALL,
        )
        if dependency_match:
            dependencies = dependency_match.group("dependencies")
            changed = dependencies.replace(wrapper_id, wrong_id, 1)
            mac_semantic_mutation = mac_semantic_mutation.replace(
                dependencies,
                changed,
                1,
            )
        mac_semantic_mutation = mac_semantic_mutation.replace(
            f"productRef = {wrapper_id}",
            f"productRef = {wrong_id}",
            1,
        )
    mac_semantic_failures: list[str] = []
    validate_generated_project(
        mac_semantic_mutation,
        mac_semantic_failures,
    )
    for label in (
        "generatedMacDependencyProducts:",
        "generatedMacFrameworkProducts:",
    ):
        if not any(
            failure.startswith(label) for failure in mac_semantic_failures
        ):
            failures.append(
                f"generatedMacWrapperSubstitutionAccepted:{label}"
            )


def main() -> int:
    failures: list[str] = []
    project_spec = read_text(PROJECT_SPEC, failures)
    generated_project = read_text(PROJECT_FILE, failures)
    agent_source = read_swift_target(AGENT_TARGET_DIRECTORY, failures)
    agent_application_platform = read_text(
        AGENT_APPLICATION_PLATFORM,
        failures,
    )
    agent_preparation_facade = read_text(AGENT_PREPARATION_FACADE, failures)
    agent_product_bootstrap = read_text(AGENT_PRODUCT_BOOTSTRAP, failures)
    agent_enabled_runtime = read_text(AGENT_ENABLED_RUNTIME, failures)
    mac_application = read_swift_target(MAC_TARGET_DIRECTORY, failures)
    mac_application_platform = read_swift_target(
        MAC_APPLICATION_PLATFORM_DIRECTORY,
        failures,
    )
    login_composition = read_text(LOGIN_COMPOSITION, failures)
    validate_project_spec(project_spec, failures)
    validate_generated_project(generated_project, failures)
    validate_mac_info_plist(failures)
    validate_agent_bundle_metadata(failures)
    validate_inert_update_adapter(mac_application, failures)
    update_reply_failures: list[str] = []
    validate_inert_update_adapter(
        mac_application.replace("reply(.skip)", "reply(.install)", 1),
        update_reply_failures,
    )
    if (
        "macUpdateAdapterUnexpectedAuthority:reply(.install)"
        not in update_reply_failures
    ):
        failures.append("macUpdateUnconditionalInstallFixtureAccepted")
    prepared_reply_failures: list[str] = []
    validate_inert_update_adapter(
        mac_application.replace(
            "case .install:\n                reply(.install)",
            "case .install:\n                reply(.skip)",
            1,
        ),
        prepared_reply_failures,
    )
    if "macUpdatePreparedReplyMappingMismatch" not in prepared_reply_failures:
        failures.append("macUpdatePreparedReplySubstitutionFixtureAccepted")
    validate_launch_agent(failures)
    validate_narrow_agent_source(agent_source, failures)
    validate_single_owner_agent_service_selection(
        agent_application_platform,
        agent_preparation_facade,
        agent_product_bootstrap,
        agent_enabled_runtime,
        failures,
    )
    validate_login_role_composition(
        login_composition,
        mac_application,
        failures,
    )
    validate_menu_application_lifecycle_owner(
        mac_application_platform,
        failures,
    )
    validate_product_inertness_self_tests(
        agent_source,
        login_composition,
        mac_application,
        failures,
    )
    validate_single_owner_agent_service_selection_self_tests(
        agent_application_platform,
        agent_preparation_facade,
        agent_product_bootstrap,
        agent_enabled_runtime,
        failures,
    )
    validate_product_link_inertness_self_tests(
        project_spec,
        generated_project,
        failures,
    )
    if failures:
        for failure in failures:
            print(f"permanent Apple target: {failure}", file=sys.stderr)
        return 1
    print(
        "Validated permanent Mac/Agent topology, identities, signing flags, "
        "requirement-bound local handshake, LaunchAgent contract, and "
        "single-owner enabled Agent network activation and package-owned "
        "menu application launch lifecycle, and inert privacy-closed Sparkle "
        "adapter."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
