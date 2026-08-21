# Local pairing-session composition evidence

Date: 2026-08-20

## Claim

The bundle-independent Agent now owns the complete local creation and dismissal
lifecycle for one visible Mac pairing QR. The menu-app command carries no host
identity, route, time, pairing ID, or secret. `AgentLocalPairingSessionHandlerV0`
reads those facts from injected Agent-owned sources, creates the boot-scoped
authority session, constructs one canonical bounded QR receipt, and permits
only exact active-command replay.

Dismissal succeeds only after `PairingSessionAuthority` consumes the exact
session and retains an `alreadyConsumed` tombstone. Cancellation is denied once
durable pairing commit begins. Expired or remotely consumed sessions are
cleared without a false dismissal receipt, while a QR construction failure is
compensated by consuming the newly created session before failure returns.
The handler rejects a second mutation during an awaited authority call.

The v0.1 local role matrix exposes create and dismiss only from the authenticated
menu-app role to the Agent. Four strict IPC codec tests require exact fields,
version, canonical QR binding, exact five-minute lifetime, and safe times.
Nine handler tests cover QR identity/route binding, exact replay, one-visible
presentation, dismissal replay and tombstone, wrong-ID preservation, remote
consumption, expiry replacement, oversized-QR compensation, invalid Agent
sources, actor reentrancy, and terminal loss during a suspended create. Two pairing-authority tests cover local cancellation and the
durable-commit race.

## Verification

Focused SwiftPM execution passed all 35 `CompanionIPC` tests, 10
`CompanionPairing` tests, and 9 local pairing-handler tests. Listener-context
construction and composition add three more focused tests. The hardened
unsigned repository gate passed 794 Swift tests across the package, 60 indexed
protocol/product fixtures, and 610 current repository files. The subsequent
Mac presentation reducer raises current hardened coverage to 799 Swift tests
and 613 repository files while preserving this handler-focused result.

## Boundary

This evidence is package construction, not an authenticated XPC or signed UI
claim. The final Agent must source the fingerprint from the exact listener
identity and endpoints from its current listener/discovery owner, then expose
the handler only through a designated-requirement-verified menu-app connection.
The final menu presentation must drop the QR on dismissal, connection loss,
expiry, logout, or Agent loss and must not log, copy, diagnose, or crash-report
the encoded secret. Physical camera scan and end-to-end pinned-TLS pairing
remain release evidence.
