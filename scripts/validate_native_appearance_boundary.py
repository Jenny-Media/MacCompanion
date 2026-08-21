#!/usr/bin/env python3

from __future__ import annotations

import re
import sys
from pathlib import Path, PurePosixPath


REPOSITORY = Path(__file__).resolve().parents[1]
SOURCES = REPOSITORY / "Packages" / "MacCompanionKit" / "Sources"

# These spellings are implementation mechanisms, not documentation terms. The
# supported design does not mutate undocumented global preferences or restart
# system UI processes to change appearance.
UNDOCUMENTED_GLOBAL_MUTATION = re.compile(
    r"AppleInterfaceStyle(?:SwitchesAutomatically)?"
    r"|AppleInterfaceThemeChangedNotification"
    r"|defaults\s+write\s+(?:-g|NSGlobalDomain)"
    r"|killall\s+(?:-HUP\s+)?Dock"
)

# If a future product decision admits Automation-backed light/dark control, it
# must live in an explicitly reviewed, user-facing adapter. It must not be
# smuggled into the network Agent, host authority, or native-provider target.
APPLE_EVENT_AUTHORITY = re.compile(
    r"\b(?:NSAppleScript|NSAppleEventDescriptor|AEDeterminePermissionToAutomateTarget"
    r"|AESendMessage|ScriptingBridge)\b"
)
AUTHORITY_FORBIDDEN_TARGETS = {
    "CompanionAgent",
    "CompanionAgentNetworkPlatform",
    "CompanionAgentPlatform",
    "CompanionHost",
    "CompanionHostSession",
    "CompanionHostWire",
    "CompanionNativeProviders",
}


def inspect(path_text: str, content: str) -> list[str]:
    path = PurePosixPath(path_text)
    failures: list[str] = []
    if UNDOCUMENTED_GLOBAL_MUTATION.search(content):
        failures.append("undocumentedGlobalAppearanceMutation")
    parts = path.parts
    if len(parts) >= 2 and parts[0] in AUTHORITY_FORBIDDEN_TARGETS:
        if APPLE_EVENT_AUTHORITY.search(content):
            failures.append("appleEventsInNonUIAuthorityTarget")
    return sorted(failures)


def validate_self_tests() -> list[str]:
    cases = (
        (
            "valid-appkit-local-appearance",
            "CompanionMacUI/Appearance.swift",
            "NSApp.appearance = NSAppearance(named: .darkAqua)",
            [],
        ),
        (
            "invalid-global-default",
            "CompanionMacUI/Appearance.swift",
            'let command = "defaults write -g AppleInterfaceStyle Dark"',
            ["undocumentedGlobalAppearanceMutation"],
        ),
        (
            "invalid-agent-apple-event",
            "CompanionAgent/SystemAppearance.swift",
            "let event = NSAppleEventDescriptor()",
            ["appleEventsInNonUIAuthorityTarget"],
        ),
        (
            "future-ui-adapter-requires-separate-review-but-is-not-agent-owned",
            "CompanionMenuAutomation/SystemAppearance.swift",
            "let event = NSAppleEventDescriptor()",
            [],
        ),
    )
    failures: list[str] = []
    for case_id, path, content, expected in cases:
        actual = inspect(path, content)
        if actual != expected:
            failures.append(f"selfTest:{case_id}:expected={expected}:actual={actual}")
    return failures


def main() -> int:
    failures = validate_self_tests()
    inspected = 0
    if not SOURCES.is_dir():
        failures.append("missingSources")
    else:
        for path in sorted(SOURCES.rglob("*.swift")):
            inspected += 1
            relative = path.relative_to(SOURCES).as_posix()
            try:
                content = path.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError) as error:
                failures.append(f"unreadable:{relative}:{type(error).__name__}")
                continue
            for code in inspect(relative, content):
                failures.append(f"source:{relative}:{code}")
    if failures:
        for failure in failures:
            print(f"native appearance boundary: {failure}", file=sys.stderr)
        return 1
    print(
        "Validated native appearance boundary with 4 policy self-tests "
        f"across {inspected} Swift source files."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
