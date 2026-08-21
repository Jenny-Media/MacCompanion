# Local audit-history composition evidence

Date: 2026-08-20

Environment: Xcode 27 beta toolchain; bundle-independent Swift package tests

## Scope

The local IPC method matrix grants `readAuditHistory` only from an authenticated
menu-app role to the Agent. The request and response models enforce v0.1,
safe-integer cursors and bounds, a 100-row maximum, exact correlation,
newest-first ordering, exclusive continuation, closed fields, global-row
privacy, and explicit prune/drop metadata. Unknown decoded fields fail closed.

`LocalAuditHistoryHandlerV0` hardcodes `.localAdministration` scope and maps the
bounded store page into that DTO. The Mac history projection now consumes the
DTO and continues to resolve device labels only from the locally confirmed-name
dictionary, with a fixed fallback for unknown devices.

## Result

Three IPC model tests, the exhaustive role-matrix test, two Agent mapping and
pagination/gap tests, and the three existing Mac projection tests pass. The
public validation gate passed with 54 authoritative fixtures and 618 Swift
tests, both UI compile gates, and three no-prompt/no-network probes.

## Boundary not claimed

No XPC connection, audit-token extraction, designated-requirement check, signed
menu app, app navigation, rendered snapshot, localization, accessibility pass,
or stable-toolchain release target was exercised. Final-identity peer
authentication remains mandatory before this handler is reachable.
