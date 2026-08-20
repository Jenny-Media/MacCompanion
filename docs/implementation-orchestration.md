# Mac Companion Implementation Orchestration

Status: coding-readiness plan. This document defines how implementation should be partitioned, ordered, reviewed, and verified. It does not contain or authorize product code.

## 1. Delivery principle

Build Mac Companion as a sequence of end-to-end evidence slices, not as separate piles of UI, networking, and security code. Every slice must establish one user-visible outcome across the real process boundary and include its failure, revocation, update, and test behavior.

The critical path is:

```text
release-shaped bundle
  -> agent lifecycle and authenticated local IPC
  -> durable host identity and host-state model
  -> discovery and pairing
  -> Observe status and revocation
  -> locally granted Adaptive Control
  -> App Focus, Window Focus, and Smart Zoom with deterministic fallback
  -> private-route three-path beta with one semantic action
  -> MacTools differentiation
```

Adaptive Control is the flagship product capability, while Observe and Act remain independently useful without a stream. Control feasibility work starts alongside the Observe path, but it does not bypass identity, grants, authorization epochs, visibility, or lifecycle gates.

### Protocol-first boundary

The first production artifacts after the release-shaped scaffold are normative `spec/v0` documents, valid and invalid fixtures, pure state machines, and cross-target tests for identity, pairing, sessions, grants, authorization epochs, revocation, framing, bounds, errors, and one `status.snapshot`. Platform capture/input/window/focus experiments run in parallel because their results shape the Interactive Control extensions.

Do not implement a broad provider protocol, optimize media framing, or build app UI against informal structs before the kernel fixtures exist. The first socket-backed convergence is deliberately narrow: pair, authenticate, request one current status snapshot, disconnect, and revoke. Interactive Control and Remote Surfaces then reuse that exact identity and fencing model.

## 2. Repository shape

Use one repository, one checked-in Xcode project/workspace, and one release version. Do not begin with separate repositories or independently versioned services.

Proposed layout:

```text
MacCompanion/
  LICENSE
  NOTICE
  TRADEMARKS.md
  SECURITY.md
  CONTRIBUTING.md
  CODE_OF_CONDUCT.md
  GOVERNANCE.md
  MacCompanion.xcworkspace
  MacCompanion.xcodeproj
  Apps/
    MacCompanionMac/          # menu bar, settings, TCC owner, interactive executor
    MacCompanioniOS/          # iPhone and iPad client
  Services/
    MacCompanionAgent/        # LaunchAgent, listener, policy, persistence, audit
  Tools/
    maccompanionctl/          # local bounded diagnostics
  Packages/
    MacCompanionKit/          # shared Swift package with explicit targets below
  Tests/
    Integration/              # multi-process and network harness definitions
    System/                   # physical-device scenarios and evidence manifests
  Experiments/                # Stage 0 harness targets; never shipped by accident
  spec/
    capability-protocol/v0/   # normative, implementation-independent RFCs
    interactive-control/v0/
    adaptive-surfaces/v0/
    schemas/
    fixtures/                 # single authoritative valid and invalid corpus
    conformance/
  docs/
    adr/
    threat-model/
  scripts/                    # reproducible build, verify, package, notarize wrappers
  .github/
    CODEOWNERS
    ISSUE_TEMPLATE/
    workflows/
  AGENTS.md
  README.md
```

The repository name may remain `MacCompanion`; user-facing spacing belongs in product metadata. The checked-in project is authoritative initially. Do not introduce a project generator, monorepo orchestrator, server stack, or code-generation pipeline until repeated manual drift proves one is needed.

### Open-source posture

Use one public monorepo while the protocol and both endpoints evolve together. The normative `spec/` tree is independent of Swift and Apple frameworks; the Swift package is one implementation. Split the protocol into another repository only when external implementers need an independent release cadence.

Source availability does not confer Jenny Media signing identity, official update access, bundle identifiers, trademarks, or managed entitlements. Community forks use their own product identity, update feed, signing team, and Apple capability requests. Official release configuration and update URLs are injected separately and never become a usable trust anchor in an unofficial build.

Before making the repository public, select an OSI license and contribution policy, reserve product trademarks separately, publish private vulnerability-reporting instructions, configure CODEOWNERS and protected branches, and enable secret scanning and push protection. Developer certificates, provisioning profiles, Sparkle private keys, notarization credentials, App Store keys, pairing material, and real diagnostic data never enter the repository.

MPL 2.0 is the working license candidate because it keeps modifications to covered files available while permitting separately authored files in a larger work. Prefer one repository-wide code license initially; do not add an Apache-licensed protocol subtree until independent implementers create a real interoperability reason for the added policy. Use a Developer Certificate of Origin by default. Adopt a Contributor License Agreement only if Jenny Media LLC makes a deliberate dual-licensing or relicensing decision before accepting contributions. Final license, App Store compatibility, and trademark policy require written legal review before the repository becomes public.

## 3. Target and module boundaries

The first Swift package contains narrow targets rather than a single universal utility module:

| Target | Platforms | Owns | Must not own |
| --- | --- | --- | --- |
| `CompanionDomain` | macOS, iOS | IDs, bounded values, host/session/operation state machines, errors | Network, storage, UI, Apple permission APIs |
| `CompanionWire` | macOS, iOS | Versioned envelopes, canonicalization, size bounds, fixtures | Trust decisions, sockets, UI |
| `CompanionSecurity` | macOS, iOS | Digests, challenge construction, key abstractions, authorization-epoch rules | Keychain UI, network routes, providers |
| `CompanionTransport` | macOS, iOS | TLS connection roles, framing, backpressure, reconnect policy | Grants, semantic authorization, screen capture |
| `CompanionPersistence` | macOS | SQLite transactions, migrations, quotas, durable repositories | UI and provider execution |
| `CompanionHost` | macOS | Policy, operation admission, status, audit, provider registry | Remote sockets and TCC presentation |
| `CompanionIPC` | macOS | Typed local messages, role restrictions, peer verification | Durable grants, media encoding |
| `CompanionInteractiveShared` | macOS, iOS | Session model, media headers, display descriptors, input schemas | Capture, decode, input injection |
| `CompanionRemoteSurfaces` | macOS, iOS | Surface/focus/text-session models, privacy profiles, transitions, fallbacks, fixtures | AX objects, capture filters, app activation, UI |
| `CompanionInteractiveHost` | macOS | Capture/encode/input adapters behind executor interfaces | Device identity, network listener, durable grants |
| `CompanionInteractiveClient` | iOS | Decode, render timing, touch/keyboard mapping | Host-state authority, remote grant changes |
| `CompanionTestSupport` | test targets only | Fake clocks, randomness, stores, transports, providers, fixtures | Production linking |

Platform app targets are composition roots. They create concrete Apple-framework adapters and presentation state, but business rules remain in the owning module.

The LaunchAgent links transport, persistence, host policy, security, wire, and IPC modules. The Mac menu app links IPC and Interactive Host but not the remote transport or authorization database. The iOS app links transport, security, wire, domain, and Interactive Client. Build settings and dependency tests should enforce these negative boundaries.

## 4. Technology baseline

- Swift 6.3 language mode with complete concurrency checking for new code
- SwiftUI for Mac settings/menu presentation and iPhone/iPad product UI
- Observation or explicit actors for app state; no cross-process truth stored in view models
- Network.framework with TLS 1.3 for the Stage 0 transport baseline
- CryptoKit and Security framework for supported cryptographic and Keychain operations
- SQLite through a small repository boundary for agent-owned durable state; SwiftData is not the security record authority
- NSXPCConnection/Mach service as the local IPC candidate, accepted only after the Stage 0 peer-identity spike
- ScreenCaptureKit display/application/window filters and VideoToolbox encoding, AppKit activation, Accessibility observation, and Core Graphics events in the persistent menu app
- OSLog with privacy annotations and a host-owned redaction allowlist
- XCTest and Swift Testing where each is strongest; one fixture corpus is consumed by both Mac and iOS targets
- Sparkle 2 as the only planned non-Apple runtime dependency in the first release

Any additional production dependency needs an ADR covering necessity, maintenance, license, signing/notarization behavior, privacy, update surface, and replacement cost. Security and wire behavior may not be hidden inside an unreviewed convenience package.

## 5. Concurrency and ownership rules

- Each mutable subsystem has one actor or serialized executor as its authority.
- The agent's session actor owns connection state; the authorization actor owns grants and epochs; the operation actor owns durable transitions; the interactive session actor owns the cross-process lease; and its surface authority owns surface, coordinate, focus, and fallback revisions.
- Database transactions remain below actor boundaries and never suspend while a write transaction is open.
- ScreenCaptureKit callbacks immediately hand bounded samples to the encoder pipeline; they do not call policy or persistence.
- Video is latency-first. Backpressure drops stale frames rather than growing tasks, buffers, or actor mailboxes.
- Input admission is reliable and ordered. Pointer motion may coalesce; button, key, epoch, lock, and coordinate-revision transitions may not.
- Window and Accessibility objects remain menu-app-local and map to ephemeral tokens. No actor caches an AX element or window identity beyond its surface revision.
- UI state is a projection of authoritative snapshots and events. It cannot mutate grants or host state locally and then hope the agent agrees.
- Cancellation is explicit at every process boundary. Disconnect and process death are tested as ordinary state transitions.

Concurrency design is part of the feature review. A detached task, unchecked sendability annotation, or global mutable singleton requires a focused justification.

## 6. Workstreams and merge order

### Workstream A — release and lifecycle foundation

1. Confirm Team ID, bundle prefix, target IDs, and entitlement request.
2. Initialize version control, ownership rules, ADR template, and CI.
3. Create the release-shaped containing app, embedded LaunchAgent, iOS app, CLI, and package targets.
4. Prove Developer ID archive, hardened runtime, notarization, DMG, clean install, login-item registration, and complete uninstall.
5. Prove authenticated local IPC and fail-closed menu-app/agent version negotiation.

No Apple-target product feature merges before the same structure can produce a release-shaped internal artifact. Normative specifications, pure cross-platform packages, fixtures, conformance tests, and disposable experiments may merge earlier when they do not freeze unresolved bundle identity, signing, TCC, or security semantics.

### Workstream B — identity, storage, and Observe vertical slice

1. Implement domain states and golden wire fixtures without sockets.
2. Implement transactional SQLite migrations, host identity, grants, authorization epochs, audit quotas, and fault injection.
3. Implement conservative console-user, lock, sleep, wake, and reachability state.
4. Implement Bonjour route discovery as untrusted metadata.
5. Implement pinned TLS, QR pairing, client identity, recovery, revocation, and replay handling.
6. Deliver one bounded `status.snapshot` from a physical Mac to a physical iPhone.
7. Add presence, freshness, reconnect, active revocation, and seven-day soak evidence.

This workstream produces the Stage 1 Observe and lifecycle alpha. Its earlier merge order reflects shared infrastructure dependencies, not greater product importance than Control.

### Workstream C — Adaptive Control feasibility and vertical slice

This begins as Stage 0 experiments and does not enter the shipped targets until its ADRs pass:

1. Verify managed-entitlement and TCC attribution using the final process identities.
2. Measure ScreenCaptureKit to VideoToolbox H.264 on supported Macs.
3. Verify Accessibility trust, bounded input injection, key/button release, and display transforms.
4. Prove display/application/window filter switching, app activation, related-window detection, modal fallback, and clean-keyframe transitions.
5. Prove focus observation, bounds, stale-element behavior, AX timeout recovery, and secure-field redaction across native, browser, Electron, and custom-drawn apps.
6. Record exact behavior through lock, display sleep, user switch, logout, permission revocation, and menu-app crash.
7. Freeze control, surface, focus, text-session, and binary media fixtures.
8. Add agent-issued authenticated IPC leases and authorization/surface/coordinate/focus fencing.
9. Deliver one granted, locally visible LAN session with Desktop, App Focus, Window Focus, Smart Zoom, surface-adaptive input profiles, and no audit content leakage.
10. Run latency, switch/fallback, bandwidth, energy, memory, thermal, and one-hour failure tests.

This workstream produces Stage 2 only after Workstream B's identity and revocation foundations are used unchanged.

### Workstream D — no-relay three-path beta

1. Add saved private endpoints without changing host identity.
2. Create guided Tailscale and provider-neutral diagnostics without bundling VPN credentials or a relay.
3. Add one evidence-backed desired-state action through the same policy, approval, persistence, and audit path.
4. Adapt Interactive Control within the frozen route-independent authorization model.
5. Admit Smart Input only if its independent focus, secure-field, Unicode, keyboard-layout, input-method, and diagnostics gate passes.
6. Run the dogfood and TestFlight repeat-use gates, including Control tasks and nonvisual Observe or Act tasks; no participant must use all three paths.

### Workstream E — differentiation after MVP

1. Freeze a narrow MacTools bridge contract.
2. Add default-deny remote exposure to reviewed actions.
3. Prove provider disappearance, upgrade, generation, cancellation, and malicious-content handling.
4. Evaluate one confidence-rated semantic overlay or provider-native surface only after the market-MVP gate.
5. Generalize a provider SDK only from the working integration.

Shell, arbitrary files, clipboard, audio, multiple displays, headless service, pre-login control, and AI-driven input remain separate post-MVP workstreams.

## 7. First issue sequence

The first implementation backlog should be created in this dependency order:

| Order | Issue | Evidence required to close |
| --- | --- | --- |
| 1 | Confirm Apple identifiers and submit managed entitlement | Account record and request ID; no secret material in repository |
| 2 | Record ADR-001 process and trust boundary | Target graph, negative dependencies, crash behavior |
| 3 | Scaffold workspace and strict build settings | Mac, agent, iOS, CLI, package, and test targets build in CI |
| 4 | Produce release-shaped signed internal Mac artifact | Expanded entitlements, signature, notarization dry run or accepted artifact |
| 5 | Prove `SMAppService` lifecycle | Login, lock, crash, disable, logout, update, uninstall matrix |
| 6 | Select and prove authenticated local IPC | Peer identity, role authorization, invalid-client tests |
| 7 | Freeze domain state machines and error taxonomy | Cross-target fixtures and illegal-transition tests |
| 8 | Implement durable security-store skeleton | Migration, disk-full, corruption, rollback, epoch tests |
| 9 | Prove host session-state observer | Physical-Mac lock, switch, logout, sleep evidence |
| 10 | Prove Local Network and Bonjour recovery | Grant, denial, later recovery on physical iPhone |
| 11 | Freeze pairing and authenticated-session RFC | Golden and negative transcript fixtures |
| 12 | Deliver local pinned `status.snapshot` | One physical Mac/iPhone end-to-end test |
| 13 | Add viewing presence and active revocation | Indicator truth and sub-second local revocation evidence |
| 14 | Screen capture and encoder experiment | Permission attribution, format, latency, resource report |
| 15 | Input and display-transform experiment | Bounded input, stale revision, stuck-key tests |
| 16 | Locked-session experiment | Exact public-API result and product-contract ADR |
| 17 | App/window/focus experiment | App and Window Focus, filter switching, modal fallback, AX timeout, secure-field, privacy report |
| 18 | Freeze Interactive Control and Remote Surface framing | JSON/binary fixtures, revisions, fallback, fuzz bounds, keyframe recovery |
| 19 | Deliver granted Adaptive Control | Desktop, App Focus, Window Focus, Smart Zoom, interaction profiles, grant, presence, indicator, suspend, audit privacy |
| 20 | Package Stage 1/2 internal alpha | Clean install, update, uninstall, physical matrix |
| 21 | Add private-route diagnostics and one action | No-relay Tailscale evidence and durable-operation tests |

Issues 14–17 can run while 7–13 proceed because they are isolated platform probes. Issue 19 cannot merge by copying experimental shortcuts; it must consume the production identity, grant, epoch, surface, IPC, and audit boundaries established earlier.

## 8. Change and review protocol

- `main` remains releasable and protected. Use short-lived branches and small vertical pull requests.
- One pull request owns a state-machine or wire change. Cross-cutting follow-ups rebase on that authority rather than editing parallel definitions.
- Changes to identity, pairing, approval, epochs, grants, IPC roles, media credentials, Remote Surface privacy or revisions, secure-field handling, updater trust, TCC ownership, or audit redaction require a threat-model note and a security-focused reviewer.
- Changes to a versioned schema update fixtures first, document compatibility, and include negative tests.
- A platform workaround that changes the product promise requires an ADR before implementation.
- Experimental targets cannot be linked into a release configuration. Promotion from `Experiments` is a rewrite against approved interfaces, not a folder move.
- Generated files, credentials, provisioning profiles, notary material, pairing QR payloads, and real audit databases never enter version control.

For parallel work, assign one owner to each module and artifact. Avoid two branches changing the same protocol or state-machine file. Read-only audit agents can review architecture, security, distribution, and product behavior independently; their findings are reconciled by the owning implementation branch before merge.

## 9. Testing pyramid and physical matrix

### Per-change automated checks

- Build every target with warnings treated as errors in project-owned code.
- Unit-test all legal and illegal state transitions.
- Run canonical wire and binary fixtures on Mac and iOS.
- Run malformed length, Unicode, numeric-bound, replay, authorization-epoch, and migration tests.
- Run surface-token substitution, stale surface/coordinate/focus revision, modal fallback, AX timeout, secure-field redaction, and text-session termination fixtures.
- Run deterministic tests with fake time, randomness, network, storage, session, and provider boundaries.
- Verify module dependency and release-configuration exclusions.
- Scan logs and test artifacts for fixture secrets and prohibited content fields.

### Integration checks

- LaunchAgent and menu app start, authenticate, negotiate, crash, recover, update, disable, and uninstall.
- Pairing races, duplicate requests, lost replies, reconnect, revocation, and storage faults.
- Interactive session start, frame gap, format change, lock, display change, permission loss, IPC loss, channel loss, and input reset.
- Desktop/App Focus/Window Focus/Smart Zoom transitions, interaction-profile overrides, application/window destruction, modal-window fallback, focus races, secure fields, and manual-zoom fallback.
- Old/new component compatibility and database migration.

### Physical-device checks

At minimum maintain:

- One Apple silicon desktop Mac and one Apple silicon portable Mac on the oldest supported macOS 26 release
- One supported Mac on the newest macOS 26 update
- One test Mac on the current macOS 27 beta before major release milestones
- One older supported iPhone, one current iPhone, and one iPad on the supported iOS/iPadOS line
- LAN cases for Wi-Fi, Ethernet, interface change, Local Network denial, and degraded bandwidth
- User-managed Tailscale cases only after the LAN identity path passes
- AppKit, SwiftUI, browser, Electron, custom-drawn, multi-window, full-screen, ordinary-text, and secure-text compatibility cases

ScreenCaptureKit, TCC, Accessibility, lock, sleep, Secure Enclave, Local Network, thermal, and updater conclusions cannot be accepted from Simulator-only evidence.

### Long-running and release checks

- Seven-day idle/monitoring soak
- One-hour Interactive Control session under input, display, app/window, modal, and focus changes
- Repeated suspend/resume, menu-app crash, agent crash, network loss, and permission revoke loops
- Clean install and uninstall on a user account with no development tools
- Upgrade from the oldest supported stable version through every schema boundary
- Notarized artifact launched after quarantine download, not from Xcode's build folder

## 10. Observability without a vendor service

The first product has no centralized telemetry. Engineering evidence comes from:

- Bounded local metrics with no screen or input content
- User-triggered diagnostic export with preview and consent
- Test-run evidence manifests that record OS, hardware class, versions, scenario, and pass/fail
- Optional consented beta diaries and short surveys
- Deterministic operation and audit records within their documented quotas

Diagnostic export applies the same host-owned allowlist as audit. It excludes host keys, pairing secrets, private addresses unless explicitly needed and previewed, video, screenshots, app/window titles and content, Accessibility labels and values, focus and text metadata, semantic trees, typed text, key events, pointer positions, clipboard data, and file contents.

## 11. Coding Definition of Ready

A work item is ready for implementation only when it has:

- A named user outcome and owning stage
- An authoritative state owner and process boundary
- Inputs, outputs, limits, freshness, cancellation, and terminal behavior
- Required grant, user presence, entitlement, TCC permission, and allowed host states
- Failure, revocation, crash, update, and rollback behavior
- Privacy and audit classification for every field
- Protocol/schema version impact and fixture plan
- Surface kind, confidence, coordinate/focus revisions, privacy allowlist, and visible fallback when adaptive presentation is involved
- Physical-device evidence required
- Explicit non-goals and dependencies

Stage 0 coding begins in independent lanes. Accepted specifications, pure Swift packages, conformance tests, CI, and disposable platform harnesses do not wait for a bundle prefix or managed-entitlement request. Final Apple target identities, designated requirements, Keychain groups, `SMAppService` labels, and release-shaped signing wait for the company prefix; the entitlement request follows creation of the final Mac App ID. Entitlement approval, locked-session success, formal interviews, and completed market validation are not required for identity-neutral work or the Observe foundation.

## 12. Definition of Done

A slice is done only when:

- The user-visible success and unavailable states work end to end.
- Policy is checked both on request and immediately before execution.
- Revocation actively fences existing sessions and queued work.
- Illegal, stale, duplicate, oversized, and malformed input fails closed.
- Crash and update paths preserve no stronger claim than durable evidence supports.
- Logs, audit, diagnostics, and support artifacts satisfy the allowlist.
- Unit, fixture, integration, physical-device, and release-shaped checks required by its risk pass.
- Documentation, threat cases, permission matrix, compatibility record, and user explanation match the implementation.
- No experiment-only entitlement, signing identity, bypass, or test secret is present in the release product.

Feature code existing on one developer Mac is not completion; the release-shaped, clean-user lifecycle is part of every security-sensitive feature.

## 13. Remaining pre-code decisions

The company-controlled reverse-DNS bundle prefix blocks only permanent Apple-target scaffolding. Stable Xcode and signing identity custody separately block signed release evidence, while entitlement approval blocks external Persistent Content Capture builds. None blocks the identity-neutral repository, specification, package, fixture, CI, or disposable-experiment lanes. The following are Stage 0 implementation decisions with bounded owners and do not require product clarification before experiments begin:

- Exact authenticated local IPC peer-verification mechanism
- Exact TLS certificate and channel-binding construction
- Exact canonical control framing and binary header offsets
- Measured video adaptation thresholds
- Whether public APIs support the genuine lock surface
- Smart Input compatibility and whether any profile beyond keystroke-only can be supported safely
- Final audit quota and retention numbers

Each has a spike, acceptance evidence, fallback, and ADR location. None may silently broaden access or introduce a vendor relay.
