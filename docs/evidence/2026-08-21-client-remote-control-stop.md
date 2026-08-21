# Client Remote Control Stop Evidence

Date: 2026-08-21

Environment: bundle-independent primary-channel, Interactive runtime, role-pair,
application-state, and workspace construction with macOS/iOS package
cross-compilation on Xcode 27 beta. This is unsigned protocol and lifecycle
evidence. It is not physical input release, capture shutdown, renderer blanking,
stable-toolchain, signed-candidate, or release evidence.

## Boundary completed

The phone's explicit Stop action now has one closed, normative exchange:
`interactive.session.end` carries only the exact Interactive session ID and
authorization epoch, and the host returns the correlated
`interactive.session.ended` only after the safety boundary completes. Both
messages have strict canonical fixtures and exact-key wire bodies.

On the host, an authenticated end request must match the active device,
primary connection, session, and epoch. The dispatcher clears active admission
before awaiting any cleanup, closes the primary session surface authority, and
then asks the runtime to release input, stop capture, purge queued media, and
blank retained output. It publishes the terminal audit and receipt only after
that runtime call succeeds. A duplicate or stale request cannot invoke teardown
a second time.

On the client, enqueueing the exact end request immediately retires the local
input/media pair and disables the live product, but does not claim remote
success. Only the exact correlated receipt clears accepted Control authority in
the selected-primary state. A correlated remote error becomes a retryable
end-failed state while preserving the exact session/effects facts; unrelated,
early, stale-connection, and wrong-session events cannot advance the revision.

## Verification

Focused tests prove canonical reconstruction of both fixtures, admission-first
and exactly-once host teardown, the client request/receipt flow, immediate local
role retirement without duplicate close, rejection of an ended event that was
not preceded by the exact submitted end, and distinct workspace ending and
end-failed projections.

The complete unsigned gate validates 62 indexed protocol/product fixtures,
746 repository files plus 34 historical blob paths and 14 repository-material
fixtures, four Swift package manifests and 12 dependency-policy fixtures,
three privacy manifests with 12 fixtures and six required-reason API source
records, 10 source-SBOM fixtures, 16 release-evidence fixtures, and 1,017 Swift
tests. All macOS/iOS package cross-compiles and all three no-prompt/no-network
construction probes pass. Only the expected read-only user SwiftPM cache
warnings appear.

## Remaining gates

- Connect the typed Stop intent to the final signed iOS live-screen composition.
- Prove physical input release, capture stop, media purge, display blanking, and
  post-event verification across disconnect, background, lock, and race cases.
- Re-run on stable Xcode 26.6 and preserve signed release evidence separately.
