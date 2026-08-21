# Bundle-independent diagnostic CLI v0.1 evidence

Date: 2026-08-21

Environment: pure Swift package construction and tests with Xcode 27 beta. This
is not a signed executable, authenticated XPC peer, installed bundle resource,
stable-toolchain result, or distribution claim.

## Boundary completed

The normative `spec/local-cli/v0/README.md` profile reduces the older CLI wish
list to the methods the authenticated v0.1 local-IPC matrix actually permits:

- `status [--json]` plans protocol negotiation followed by
  `readAgentStatus`;
- `diagnostics export [--json]` plans protocol negotiation followed by
  `exportDiagnostics`; and
- help and version are local and plan no IPC.

Unknown, incomplete, duplicated, reordered, and extra arguments fail through a
closed parse-error enum that retains no rejected input. The profile fixes
success and eight failure statuses and requires fixed messages that never
append provider, framework, XPC, filesystem, signing, or decoded peer detail.
Export writes only to standard output; the profile grants no file authority.

The pure `CompanionCLI` target implements that parser, exact local-method plan,
failure mapping, and renderer. It revalidates the typed status or export before
producing any bytes. Human output contains only fixed labels, closed enums,
bounded counts, sequence values, and Unix-millisecond timestamps. JSON output
is compact, sorted-key, newline-terminated UTF-8 and round-trips to the exact
validated value. Empty route and warning sets render explicitly as `none`.

There is deliberately no executable main, XPC or socket transport, filesystem
writer, signing-identity claim, Agent bootstrap, remote protocol call, provider
access, or administrative command. The permanent `maccompanionctl` remains
gated on final identity plus physical audit-token and designated-requirement
proof.

## Verification

`spec/fixtures/cli-v0.1.json` is indexed by the sole fixture manifest and owns
nine valid commands, ten invalid cases, exact request plans, help/version/status
and export text, and all eight failure mappings. It reuses the existing
authoritative sanitized diagnostic-export fixture instead of creating a second
data corpus.

Seven focused tests prove:

- every valid command produces the exact fixture plan and every planned method
  is admitted for an already-authenticated `diagnosticCLI` caller;
- every invalid argument case produces its exact content-free parse error;
- help, version, status, and export text match the fixture byte-for-byte;
- JSON is compact, sorted, newline terminated, validated, and round-trippable;
- a typed export that fails the sensitive-data omission invariant produces no
  text or JSON;
- failure statuses are unique and fixed messages contain no newline; and
- empty closed lists render honestly as `none`.

The complete hardened gate validates 63 indexed protocol/product fixtures, 760
repository files plus 34 historical blob paths and 14 repository-material
fixtures, four Swift package manifests and 12 dependency-policy fixtures, three
privacy manifests with 12 fixtures and six required-reason API source records,
10 source-SBOM fixtures, 16 release-evidence fixtures, and 1,030 Swift tests.
All macOS/iOS package cross-compiles and all three no-prompt/no-network probes
pass. Only the expected read-only user SwiftPM cache warnings appear.

## Remaining gates

- Freeze final CLI bundle placement, identifier, signing requirement, and Agent
  XPC service identity.
- Prove audit-token extraction, designated-requirement acceptance and
  wrong-signer rejection on the stable release toolchain.
- Prove version mismatch, Agent absence/restart, connection invalidation,
  output backpressure/broken pipe, installed-resource invocation, and sanitized
  export on clean physical users.
- Expand commands only through a separately specified authenticated local IPC
  method, policy, privacy review, and authoritative fixtures.
