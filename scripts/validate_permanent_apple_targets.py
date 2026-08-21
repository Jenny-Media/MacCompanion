#!/usr/bin/env python3

from __future__ import annotations

import plistlib
import re
import sys
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[1]
PROJECT_SPEC = REPOSITORY / "project.yml"
PROJECT_FILE = REPOSITORY / "MacCompanion.xcodeproj" / "project.pbxproj"
MAC_APPLICATION = (
    REPOSITORY
    / "Apps"
    / "MacCompanionMac"
    / "MacCompanionApplication.swift"
)
LOGIN_COMPOSITION = (
    REPOSITORY
    / "Apps"
    / "MacCompanionMac"
    / "MacCompanionLoginRoleComposition.swift"
)
AGENT_SOURCE = REPOSITORY / "Apps" / "MacCompanionAgent" / "MacCompanionAgentMain.swift"
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


def validate_project_spec(content: str, failures: list[str]) -> None:
    required = {
        "agentTarget": "  MacCompanionAgent:\n    type: tool\n    platform: macOS",
        "agentSource": "      - path: Apps/MacCompanionAgent",
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


def validate_generated_project(content: str, failures: list[str]) -> None:
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
        "import CompanionAgentNetworkPlatform",
        "import CompanionAgentPlatform",
        "import Dispatch",
        "@main",
        "import CompanionLocalXPCPlatform",
        "import Darwin",
        "enum MacCompanionAgentMain",
        "static func main()",
        "dispatchMain()",
        "let localXPC = MacLocalXPCServerV1",
        "profile: .authenticationOnly",
        "try localXPC.start()",
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
        "statusReader:",
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
    ):
        if needle in application_code:
            failures.append(f"menuSourceUnexpectedAuthority:{needle}")
    for needle in (".register(", ".unregister(", "setEnabled("):
        if needle in composition_code or needle in application_code:
            failures.append(f"implicitLoginMutation:{needle}")


def main() -> int:
    failures: list[str] = []
    project_spec = read_text(PROJECT_SPEC, failures)
    generated_project = read_text(PROJECT_FILE, failures)
    agent_source = read_text(AGENT_SOURCE, failures)
    mac_application = read_text(MAC_APPLICATION, failures)
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
    if failures:
        for failure in failures:
            print(f"permanent Apple target: {failure}", file=sys.stderr)
        return 1
    print(
        "Validated permanent Mac/Agent topology, identities, signing flags, "
        "requirement-bound local handshake, LaunchAgent contract, and "
        "explicit side-effect-free SMAppService composition."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
