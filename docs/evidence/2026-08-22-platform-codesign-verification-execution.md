# Fixed codesign verification execution and parsing

Date: 2026-08-22

## Claim

The protected collector can now execute only the exact deepest-first
verification plans produced by the prior reconstruction boundary. Before it
runs a plan, it independently rederives the complete plan set from the graph,
Team ID, reconstructed subjects, and pinned `/usr/bin/codesign` identity. A
changed object path, argument, order, tool, graph step, or plan field fails
before process creation.

Every invocation runs through the fixed-tool runner. Immediately before and
after each invocation, the collector reinspects the private-root ownership and
modes, every exact composition entry, in-root symlink topology, canonical
composition digest, subject root, and root-bound provenance digest/count. A
change fails the phase even if `codesign` exits zero.

Both raw streams are reopened with `O_NOFOLLOW`, restricted to their exact
invocation-derived names, mode, owner, one-link regular-file form, fixed output
bound, SHA-256, descriptor identity, and private-root-matched platform
provenance. A retained-output mutation or substitution cannot reach parsing.

For an exit-zero result the parser accepts only empty stdout and three exact
UTF-8, LF-terminated, subject-path-bound stderr lines: valid on disk,
satisfies its Designated Requirement, and explicit requirement satisfied.
Missing, reordered, additional, warning, CRLF, wrong-path, or otherwise
unrecognized output fails closed. Nonzero, timeout, signal, overflow, changed
tool, or fixed-runner rejection produces a typed failed result and never
interprets candidate-controlled failure text as a success fact.

## Adversarial validation

`scripts/validate_platform_codesign_verification.py` executes the real pinned
`/usr/bin/codesign` verification command over every synthetic unsigned Mac
subject. Every invocation predictably exits nonzero, retains empty stdout and
nonempty stderr, preserves the exact subject, and produces only
`status: failed` with `reason: nonzeroExit`.

The same validator proves the closed positive grammar without asserting a
real signature and covers 11 negative classes:

- retained raw-output mutation;
- nonempty stdout;
- an added warning, missing success line, or CRLF substitution;
- changed argv or an open invocation-result object;
- failure text that resembles arbitrary candidate detail;
- a rederived-plan mismatch;
- subject-byte mutation before invocation; and
- independently supplied composition-digest mutation.

The validator is part of `scripts/validate.sh`.

The complete validation entry point passes on Xcode 27 beta. It scans 972
current repository files and 1,275 historical blob paths, runs every indexed
fixture and release-evidence boundary, passes the 1,389-test Swift package
suite, builds every required cross-platform surface, and passes the eight
no-prompt/no-network platform-probe tests.

## Non-claims and next gate

No real signed fixture passes in public validation, so this evidence makes no
platform-verification success claim. It does not inspect per-architecture
CodeDirectories, signing identifiers, Team IDs, certificates, requirements,
timestamps, hardened runtime, or entitlements; compare the independently
pinned signing policy; run the recursive outer-bundle cross-check; correlate
notarization, stapling, Gatekeeper, or packaging equivalence; or publish the
canonical platform-signing record.

The next slice must add separate fixed per-architecture inspection commands
and bounded parsers, then compare every reported fact to the independent
policy. `signedCodePlatformVerificationRequired` and every artifact's
`platformAcceptanceEligible: false` state remain unchanged.
