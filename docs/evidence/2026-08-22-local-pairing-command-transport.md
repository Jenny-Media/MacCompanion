# Local pairing command transport and permanent menu composition

Date: 2026-08-22

## Result

The permanent menu and Agent products now contain the first bidirectional
pairing slice. The menu may create and dismiss one visible pairing QR and may
resolve the exact currently presented local approval review. These operations
remain useful without opening Remote Control.

The Agent remains the sole pairing authority. Its stable local-XPC command
adapter is empty until the complete network pairing aggregate has been
composed, and teardown fences that adapter before listener and product
retirement. An authenticated route is not treated as business authority.

## Closed boundary

- The protocol admits exactly three canonical version-1 request/reply pairs:
  create session, dismiss session, and resolve pairing decision.
- The payload limit is 4,096 bytes. Kind substitution, unknown fields,
  noncanonical JSON, concurrent commands, stale generations, malformed replies,
  and deadline expiry fail closed.
- The Agent executes at most one command across all three families for each
  authenticated menu generation. Handled business failure returns only the
  exact typed error envelope; it exposes no error detail.
- Server and client deadlines are four and five seconds respectively. Timeout
  or cancellation after send retires the transport generation so ambiguous
  delivery is never silently retried as a new command.
- Receipt correlation is checked again at both transport endpoints before a
  result reaches the menu presentation owner.
- Host-identity recovery presentation remains connected, but confirmation is
  deliberately unavailable. Its destructive menu-to-Agent command requires a
  separate protocol and durable-recovery checkpoint.

## Permanent product behavior

The dashboard constructs the authenticated pairing-review and recovery
receivers before local-XPC activation. A weak command proxy breaks the menu
owner/product construction cycle without exposing the raw session. The menu
offers a dedicated **Pair New Device** action and one non-dismissable trusted
sheet; an incoming SAS/device-name approval review takes priority over the QR
sheet.

Agent or transport loss invalidates the QR, approval review, and recovery
presentation owners. The QR owner retains exact command identity across a
recoverable business failure, while transport ambiguity retires the generation.

## Verification

- `python3 scripts/validate_fixtures.py`: passed, 65 indexed fixtures.
- C exact-envelope implementation: `clang -fblocks -fsyntax-only` passed
  against the Xcode 27 beta macOS SDK.
- `CompanionLocalXPCPlatform` isolated Swift build: passed.
- `CompanionAgentPlatform` isolated Swift build: passed.
- `CompanionAgentProductPlatform` isolated Swift build: passed.
- `CompanionMacApplicationPlatform` isolated Swift build with the compiler's
  subprocess sandbox disabled: passed.
- Permanent menu executable sources were independently type-checked for the
  macOS 26 target with the built package modules: passed.
- Focused current-source tests passed: 3 command-codec tests, 1 transaction-gate
  test, 19 Agent/dashboard product tests, and 6 dashboard lifecycle tests.
- The complete current Swift Testing catalog passed all 1,397 tests.
- The Agent product and permanent dashboard application platform both passed
  separate x86_64 cross-builds in addition to the native arm64 builds.
- Repository material, source SBOM, permanent Apple-target topology, native
  appearance, fixture integrity, and `git diff --check` validators passed.

The ordinary all-in-one validator and Xcode project build were not rerun in this
checkpoint because the host sandbox blocks nested Swift macro/CoreSimulator
services and the external-execution approval quota is exhausted until
2026-08-26. The same source modules were compiled with the compiler's supported
`-disable-sandbox` option; a full unsigned/signed permanent-target build remains
the next completion gate before runtime activation.

No login item was registered, no Agent was activated, no listener was started,
and no durable machine state was changed by this checkpoint.
