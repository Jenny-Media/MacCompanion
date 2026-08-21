# Local XPC content-free status binding evidence

Date: 2026-08-21

## Outcome

The production local XPC transport now has an explicit, still-inert
`menuLifecycleReadinessAndStatus` composition profile. After reciprocal signed
peer authentication and the separately acknowledged menu-readiness exchange,
it can bind the existing `readAgentStatus` capability to the exact current
connection generation. This is an Observe-path capability and does not start,
depend on, or authorize Remote Control.

The permanent LaunchAgent remains explicitly `authenticationOnly`. It does not
construct the complete Agent local-service root, inject a status reader, or
enable the new profile. The permanent-target validator rejects either the
readiness/status profile or a status-reader injection in that narrow source.

## Closed method and wire boundary

The server re-applies `LocalIPCAuthorizationPolicy` for authenticated
`menuApp` to `agent` `readAgentStatus` before starting a read. The only accepted
request is an exact XPC dictionary with string `kind` `status.read` and signed
int64 `version` `1`.

Success has exactly `kind`, `version`, and an `XPC_TYPE_DATA` `payload`; source
failure has exactly `code`, `kind`, and `version`, with the sole closed code
`sourceUnavailable`. Alternate version scalar types, missing or additional
members, wrong payload types, unknown errors, and payloads outside 1...4,096
bytes are malformed. A malformed exchange cancels the exact generation.

## Content-free typed payload

`LocalAgentStatusWireCodecV1` validates the snapshot, emits sorted canonical
JSON, enforces the 4,096-byte transport ceiling, and validates strict JSON plus
canonical form on receipt. It then decodes, validates, and requires exact
canonical re-encoding. That final equality check rejects unknown members that a
synthesized decoder might otherwise ignore.

The server reader and public client event carry only
`LocalAgentStatusSnapshot`; raw payload bytes do not cross either public Swift
capability boundary. The Agent-platform adapter accepts only the already
authorized `AgentLocalStatusReadingV1` facet issued by the complete local
service root and maps every source failure to the one closed transport error.

## Lifetime and bounded work

Each peer and client permits only one in-flight status read. Monotonic operation
IDs fence repeated reads, while the existing listener-run, peer, and client
session generations fence replacement and delayed callbacks. The server retains
the XPC request only for the active operation and releases it on success,
failure, timeout, replacement, cancellation, or shutdown.

The server cancels a generation when its trusted status source does not finish
within two seconds. The client independently cancels after three seconds. A
valid `sourceUnavailable` response leaves the current connection usable for a
later sequential recovery read.

## Verification

The production-used transaction gate is exercised for premature and concurrent
admission, successful completion, source-unavailable completion followed by a
sequential recovery read, timeout invalidation, replacement, and late completion.
The injected request lease proves retain and exact-once release across explicit
cancellation, ownership transfer, and deinitialization. Focused verification
passes 24 local-XPC transport tests, 4 canonical-codec tests, and 2 Agent-adapter
tests.

The full repository gate passes across 885 repository files, 288 Swift source
files, 1,192 unique MacCompanionKit tests, iOS cross-builds, and the 8 platform
probe tests. A separate unsigned Xcode 27 beta Debug build compiles and packages
the containing app plus embedded Agent. This is constructed and behaviorally
tested transport evidence; a live mutually signed XPC round trip remains an
explicit external proof obligation before permanent composition is claimed.
