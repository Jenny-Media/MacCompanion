# Authenticated menu presentation contract evidence

Date: 2026-08-21

## Result

The prerequisite contract for pairing-review and host-identity-recovery XPC
presentation is now closed before any session transport consumes it.
`LocalIPCAuthorizationPolicy` permits exactly five Agent-to-menu operations:
pairing publish and withdrawal, recovery-review publish, durable
recovery-resume publish, and recovery withdrawal. The existing authenticated
surface router proves all five methods before issuing a facet. Menu-to-Agent,
same-role, and diagnostic-CLI combinations remain denied by the exhaustive
role matrix.

The indexed normative fixture defines five exact XPC request kinds. The three
publish requests carry nonempty canonical JSON data bounded to 4,096 bytes;
the two withdrawals carry only a nonzero XPC UUID. Publish may return an exact
acknowledgement or the one closed `presentationRejected` value only after the
receiver proves it retained no presentation state. Withdrawal permits only an
exact acknowledgement; every other outcome is terminally ambiguous. No
message carries a process role, endpoint name, authentication flag, router
generation, private issuance token, diagnostic text, or raw authority.

`LocalMenuPresentationWireCodecV1` strictly validates JSON, rejects duplicate
members and noncanonical encodings, decodes only the expected closed typed
payload, and requires exact canonical re-encoding equality. Pairing review,
fresh recovery review, and durable recovery resume cannot substitute for one
another. `LocalPairingReviewV0` now also rejects every zero identifier and any
policy revision outside the v0.1 safe-integer wire domain. Fresh recovery
review still requires receiver-clock expiry admission; durable resume may
legitimately be delivered after the original confirmation window.

One fixture-to-code test binds the authoritative method set and 4,096-byte
limit directly to `LocalIPCMethod` and the codec, verifies that withdrawal has
only one reply, and pins the three payload type names. This prevents the
fixture from becoming a documentation-only copy of a drifting implementation.

## Verification

The focused `CompanionIPCTests` target passes 57 tests, including seven new
contract tests for all payload round trips, all six directed cross-kind
substitutions, open/duplicate/noncanonical/empty/oversized data, exact nonzero
withdrawal IDs, pairing identifier and revision bounds, and fixture/code
agreement. The 44-test local-XPC target, including all 20 router race tests,
also passes.

The complete unsigned repository gate passes across 902 repository files, 294
Swift source files, 1,250 unique package tests with zero duplicate names, all
8 platform-probe tests, 64 indexed protocol/product fixtures, 14 privacy source
records, every policy validator, and the supported iOS and macOS cross-builds.
A fresh unsigned Xcode 27 beta app-plus-embedded-Agent build also succeeds.

## Boundary and next gate

This slice adds no C XPC presentation parser or sender, menu incoming-message
receiver, exact-peer endpoint proxy, presentation-capable server profile,
prepared-product composition, permanent-target construction, runtime start,
signed exchange, or successful live presentation claim. The permanent Agent
remains authentication-only and the inert prepared product remains limited to
readiness and content-free status.

The next gate is to implement the five exact C envelopes and acknowledgements,
a current-ready-generation sender proxy that never owns a raw session, and a
menu receiver that copies payload bytes before suspension and acknowledges
only after typed presentation retention. Session cancellation and send
admission must remain serialized because an asynchronous send on a cancelled
XPC session is unsafe under the current platform contract.
