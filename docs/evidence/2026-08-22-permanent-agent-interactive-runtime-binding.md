# Permanent Agent Interactive runtime binding checkpoint

Date: 2026-08-22

## Result

The permanent enabled-Agent composition now installs one stable fail-closed
Interactive runtime authority in the primary dispatcher before local XPC is
constructed. The dispatcher therefore has no temporary runtime to replace and
no second shortcut path. Until an authenticated and menu-ready generation is
available, Interactive installation is unavailable.

The exact ready generation binds that stable authority to one concrete
`AgentInteractiveRuntimeOwnerV1`, wrapped by the automatic lease-renewal owner.
The concrete owner reuses the preparation-owned security store, the same
visible-admission authority published by that menu generation, and the narrow
menu runtime route. Product shutdown retains and finishes the stable authority
before local XPC teardown.

## Exact transport ownership

The authenticated menu surface now exposes a narrow Interactive runtime facet
from the same cached opaque endpoint used for its pairing and recovery facets.
It does not expose the server, session, caller-selected generation, endpoint
token, arbitrary message kind, or raw payload.

Every Desktop-preparation, install, renewal, and revoke request carries the
endpoint's exact transport generation and private issuance token into the
server queue. Admission repeats the listener-run, retained-peer, current
generation, readiness, profile, authorization, and private-token checks before
any send. Retaining an old endpoint cannot redirect work to the current menu
generation. A malformed bound reply cancels only its exact generation, while a
retired endpoint rejects locally and cannot retire a replacement.

Menu-generation loss serially invalidates the matching runtime authority before
the remaining presentation surface. An active lease is terminated as
`menuAppUnavailable`; a later generation can bind only after that teardown.
Explicit product finish makes the stable authority terminal and prevents any
future binding.

## Verification

- The indexed Interactive lease fixture records the exact-generation and
  private-token rule, and all 67 authoritative fixtures validate.
- Three stable-authority tests prove unavailable-before-bind behavior, strict
  generation high-water, teardown-before-replacement, exact termination, and
  terminal finish.
- Local-XPC tests prove pure generation/token admission and exact forwarding by
  the opaque endpoint; a retired endpoint performs no second send.
- Product lifetime coverage proves the Interactive authority reaches terminal
  state before the local-XPC finish barrier completes.
- The focused Agent, LocalXPC-platform, and Agent-product suites pass under
  Xcode 27 beta.
- The complete repository gate passes 1,431 MacCompanionKit Swift tests, all
  macOS/iOS cross-builds, and eight platform-probe tests.
- `git diff --check` passes.

## Non-claims and next work

This checkpoint constructs the permanent Agent runtime owner but does not
claim a live Control session. The menu runtime still uses inert indicator,
capture, frame-blanking, input-release, and input-posting adapters; no screen
pixels, encoded media, or physical input were produced. The next independent
slice is the concrete visible indicator and lease-expiry scheduler, followed by
capture/media/frame and input adapters. Signed two-process and physical-device
evidence remain separate gates.
