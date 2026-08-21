# Audit-history UI construction evidence

Date: 2026-08-20

Environment: Xcode 27 beta toolchain; bundle-independent Swift package tests

## Scope

The shared presentation layer maps the closed v0 detailed-audit event and
outcome registries to host-owned titles, symbols, and outcome labels. It also
maps retention and rate-limit gaps to explicit incomplete-history messages.

The iOS projection accepts only a validated `audit.list.response`, preserves
its server-declared gaps and exclusive continuation cursor, and emits no raw
device, grant, operation, correlation, or error identifiers. The SwiftUI view
distinguishes a complete empty page from an empty page whose older history was
pruned or whose events were dropped.

The Mac projection accepts one bounded local-store page and resolves a device
label only from the caller's Agent-owned confirmed-name dictionary. Unknown
devices use fixed local copy and system-wide events expose no device label.
Both views are value-driven and emit only an explicit load-older intent.

## Result

Three client projection tests and three Mac projection tests pass. Both UI
targets compile under the package's iOS Simulator and macOS build gates. The
public validation gate passed with 54 authoritative fixtures and 610 Swift
tests, plus both UI compile gates and three no-prompt/no-network probes.

## Boundary not claimed

No app navigation, authenticated local administration connection, live audit
producer, rendered snapshot, localization, accessibility pass, physical device,
or stable-toolchain release target was exercised. The package surface proves
only bounded projection, privacy-preserving copy, gap visibility, pagination
intent, and compile compatibility.
