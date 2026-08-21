# Client Role Product Binding Evidence

Date: 2026-08-21

Environment: bundle-independent configured-route product construction,
injected role-pair owners, and macOS/iOS package cross-compiles on Xcode 27
beta. This is unsigned ownership, clean-media orchestration, and race evidence.
It is not physical decoding/display, posted-input, physical-device,
stable-toolchain, or release evidence.

## Product activation

`NetworkClientInteractiveRoleProductBindingV0` is now part of the configured
route application product and its UIKit wrapper. Product event fan-out is
ordered so the exact selected-primary application state retains an accepted
Control session before the role binding attempts construction. The binding can
therefore create a pair only from the current authenticated session, winning
endpoint, accepted offers, and authorization epoch.

An accepted Control event starts one all-or-none input/media pair. Request,
approval, rejection, exact primary termination, selected-primary replacement,
explicit binding close, or pair failure cancels the activation and retires the
owned sockets. Late completion is fenced by a private activation ID and cannot
resurrect a retired generation. A stale termination with another connection ID
has no authority.

The public product state is deliberately narrow: inactive, connecting, role
channels ready, initial-surface preparing, active, failed, or closed, with only
the Interactive session ID. “Role channels ready” proves mutual secondary
authentication only. It does not mean a clean Desktop frame exists, media is
displayed, or input is enabled. Exact connection/session-tagged progress enters
the primary application's monotonic revision stream, and only the rendered
clean-frame acknowledgement reply can project active Control and enable UIKit
gestures.

## Verification

Three new binding tests prove that ready is published only after pair success,
a fresh request closes an old ready pair, pair failure publishes no ready state,
and exact primary termination wins a suspended activation without late
resurrection. The tests also prove that connecting, ready, and failure progress
carry the exact primary connection and interactive-session IDs. The application
integration rejects skipped/backward/stale progress and the workspace projects
ready, preparing, active, and failed distinctly. Configured-route factory tests
remain green after the runtime connector and binding are added, and the UIKit
product cross-compiles with the same owner.

The hardened unsigned gate passes with 62 indexed protocol/product fixtures,
746 repository files plus 34 historical blob paths
and 14 repository-material fixtures, four Swift package manifests and 12
dependency-policy fixtures, three privacy manifests with 12 fixtures and six
required-reason API source records, 10 source-SBOM fixtures, 16 release-evidence
fixtures, and 1,017 Swift tests. All macOS/iOS package cross-compiles and all
three no-prompt/no-network construction probes pass. Only the expected
read-only user SwiftPM cache warnings appear.

## Remaining gates

- The ready media socket and exact rendered-frame-gated acknowledgement are
  now covered by the subsequent [initial Desktop activation evidence](2026-08-21-client-initial-desktop-activation.md).
- Prove live private-route TLS, media, input, backgrounding, replacement, and
  lock fallback on signed physical devices.
- Re-run on stable Xcode 26.6 and preserve signed release evidence separately.
