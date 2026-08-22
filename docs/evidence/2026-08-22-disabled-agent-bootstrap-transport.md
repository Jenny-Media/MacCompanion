# Disabled-Agent bootstrap transport

Date: 2026-08-22

## Claim

Mac Companion now carries the protocol-frozen disabled-Agent enable exchange
through exact local-XPC envelopes and canonical bounded payload codecs. One
generation-bound transaction gate enforces the order `read offer` then `enable
remote access`; it grants no remote capability and performs no durable
mutation.

## Exact transport boundary

- The offer read request is the closed two-field
  `bootstrap.remote-access.read` dictionary.
- Its acknowledgement, the enable request, and the enable acknowledgement are
  closed three-field dictionaries with one nonempty `XPC_TYPE_DATA` payload.
- All payloads are capped at 4,096 bytes and must be canonical closed JSON.
  Empty, oversized, duplicate-member, noncanonical, unknown-field, invalid,
  cross-kind, wrong-version, alternate-scalar, and open XPC forms fail closed.
- There is no application-error reply shape. Any malformed reply or transport
  error is terminal for the still-current peer generation.

## Transaction fence

The bundle-independent gate binds one nonzero authenticated peer generation,
admits at most one offer read, and admits enablement only after that read
completes with a validated offer. The command must embed that exact offer.
Read and enable operations cannot overlap, and success admits no additional
bootstrap operation while the Agent awaits restart.

Monotonic operation identities fence timeout, cancellation, peer replacement,
and delayed completion. A stale callback cannot finish or invalidate a newer
generation. A receipt is accepted only when its command ID, offer ID, exact
successor revision, protocol version, and completion time validate against the
in-flight command; a malformed current receipt terminally clears the gate.

## Deterministic verification

Four codec tests cover canonical round trips for the offer, command, and
receipt plus duplicate, noncanonical, open, empty, and oversized rejection.
Four transaction tests cover authorization and ordering, overlap and replay
denial, offer substitution, timeout/replacement fencing, exact receipt binding,
and malformed-receipt terminalization. The platform C parser self-test covers
all four exact kinds, alternate payload types, additional keys, wrong versions,
and oversized data.

Focused verification on Xcode 27 beta passes:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
swift test --package-path Packages/MacCompanionKit --filter CompanionIPCTests

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
swift test --package-path Packages/MacCompanionKit \
  --filter CompanionLocalXPCPlatformTests
```

Results: all 67 IPC tests and all 82 local-XPC platform tests passed.

The complete repository gate also passes with 64 indexed protocol/product
fixtures, 943 repository files, 1,188 historical blob paths, 307 production
Swift source files, 1,361 package tests, every supported cross-build, and all 8
platform-probe tests.

## Non-claims and next gate

This checkpoint does not register an Agent, construct the durable offer owner,
mutate enabled intent, bind the methods into a production Agent handler or menu
client, restart either process, claim readiness, or open presentation or
network ingress. The next checkpoint must compose these exact envelopes and
transaction fences with the Agent-owned serialized durable mutation and the
foreground setup-registration lifecycle.
