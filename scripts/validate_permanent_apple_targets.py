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
LOGIN_COMPOSITION = (
    REPOSITORY
    / "Apps"
    / "MacCompanionMac"
    / "MacCompanionLoginRoleComposition.swift"
)
AGENT_TARGET_DIRECTORY = REPOSITORY / "Apps" / "MacCompanionAgent"
LAUNCH_AGENT = (
    REPOSITORY
    / "Apps"
    / "MacCompanionMac"
    / "LaunchAgents"
    / "media.jenny.maccompanion.agent.plist"
)

AGENT_IDENTIFIER = "media.jenny.maccompanion.agent"
EXPECTED_LAUNCH_AGENT = {
    "BundleProgram": "Contents/MacOS/MacCompanionAgent",
    "KeepAlive": True,
    "Label": AGENT_IDENTIFIER,
    "MachServices": {AGENT_IDENTIFIER: True},
    "RunAtLoad": True,
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


def generated_agent_product_lists(content: str) -> tuple[list[str], list[str]]:
    objects = pbx_objects(content)
    product_names = pbx_product_names_by_identifier(content)
    target = generated_native_target_block(content, "MacCompanionAgent")

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
    expected = [
        "CompanionAgentApplicationPlatform",
        "CompanionLocalXPCPlatform",
    ]
    if generated:
        dependencies, frameworks = generated_agent_product_lists(content)
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


def validate_project_spec(content: str, failures: list[str]) -> None:
    required = {
        "agentTarget": "  MacCompanionAgent:\n    type: tool\n    platform: macOS",
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
            "          destination: executables"
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
        "agentSigningIdentifier": (
            '        OTHER_CODE_SIGN_FLAGS: "-i $(PRODUCT_BUNDLE_IDENTIFIER)"'
        ),
        "agentSkipInstall": "        SKIP_INSTALL: YES",
    }
    for label, needle in required.items():
        require_count(content, needle, 1, label, failures)
    require_exact_agent_products(content, generated=False, failures=failures)
    require_count(
        content,
        "        product: CompanionLocalXPCPlatform",
        2,
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
        "CODE_SIGN_IDENTITY:",
        "PROVISIONING_PROFILE",
        "CODE_SIGN_ENTITLEMENTS:",
    ):
        if forbidden in content:
            failures.append(f"trackedSigningAuthority:{forbidden.rstrip(':')}")
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
    require_count(
        content,
        'productType = "com.apple.product-type.tool";',
        1,
        "agentToolProduct",
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
        "dstPath = Contents/Library/LaunchAgents;",
        1,
        "launchAgentDestination",
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
        'OTHER_CODE_SIGN_FLAGS = "-i $(PRODUCT_BUNDLE_IDENTIFIER)";',
        2,
        "generatedAgentSigningIdentifier",
        failures,
    )
    require_count(
        content,
        "MacCompanionAgent in Embed Dependencies",
        2,
        "generatedAgentEmbed",
        failures,
    )
    if re.search(
        r"\b(?:DEVELOPMENT_TEAM|PROVISIONING_PROFILE|CODE_SIGN_ENTITLEMENTS) =",
        content,
    ):
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


def validate_narrow_agent_source(content: str, failures: list[str]) -> None:
    code = "\n".join(
        line.split("//", 1)[0] for line in content.splitlines()
    )
    for needle in (
        "import CompanionAgentApplicationPlatform",
        "import Dispatch",
        "@main",
        "import CompanionLocalXPCPlatform",
        "import Darwin",
        "enum MacCompanionAgentMain",
        "static func main() async",
        "let retention: MacCompanionAgentInertStartupRetentionV1",
        "MacCompanionAgentInertStartupCoordinatorV1",
        ".prepareAndStartAuthentication",
        "guard case .retryAfterFirstUnlock = retention",
        "dispatchMain()",
        "let localXPC = MacLocalXPCServerV1",
        "profile: .authenticationOnly",
        "try localXPC.start()",
        "withExtendedLifetime((retention, localXPC))",
    ):
        require_count(code, needle, 1, f"agentSource:{needle}", failures)
    for needle in (
        "SMAppService",
        "NWListener",
        ".register(",
        "UserDefaults",
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
    ):
        if needle in code:
            failures.append(f"agentSourceUnexpectedAuthority:{needle}")


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
            "private let loginRoles = MacCompanionLoginRoleComposition()"
        ),
    }
    for label, needle in required.items():
        haystack = (
            application_code
            if label == "applicationRetention"
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
    require_count(
        application_code,
        "@State private var source: MacAgentDashboardSourceV0 = .unavailable",
        1,
        "inertMenuDashboardSource",
        failures,
    )
    for needle in (
        "MacLocalXPCDashboardProductV1(",
        "MacAgentDashboardApplicationOwnerV0(",
        "MacAgentReleaseStorageV1",
        "CompanionAgentProductPlatform",
        "MacAgentProductBootstrapV1",
        "MacAgentPreparedProductV1",
    ):
        if needle in application_code:
            failures.append(f"menuSourceUnexpectedAuthority:{needle}")
    for needle in (".register(", ".unregister(", "setEnabled("):
        if needle in composition_code or needle in application_code:
            failures.append(f"implicitLoginMutation:{needle}")


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


def main() -> int:
    failures: list[str] = []
    project_spec = read_text(PROJECT_SPEC, failures)
    generated_project = read_text(PROJECT_FILE, failures)
    agent_source = read_swift_target(AGENT_TARGET_DIRECTORY, failures)
    mac_application = read_swift_target(MAC_TARGET_DIRECTORY, failures)
    login_composition = read_text(LOGIN_COMPOSITION, failures)
    validate_project_spec(project_spec, failures)
    validate_generated_project(generated_project, failures)
    validate_launch_agent(failures)
    validate_narrow_agent_source(agent_source, failures)
    validate_login_role_composition(
        login_composition,
        mac_application,
        failures,
    )
    validate_product_inertness_self_tests(
        agent_source,
        login_composition,
        mac_application,
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
        "narrow activation-inert application preparation."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
