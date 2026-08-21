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
  -> Desktop video plus mouse and keyboard
  -> App Focus, Window Focus, and Smart Zoom with deterministic fallback
  -> private-route three-path beta with native setAudioMuted
  -> MacTools differentiation
```

Adaptive Control is the flagship product capability, while Observe and Act remain independently useful without a stream. Control feasibility work starts alongside the Observe path, but it does not bypass identity, grants, authorization epochs, visibility, or lifecycle gates.

Whenever it is unblocked, the shortest signed, physical, runnable product slice takes precedence over additional construction-only infrastructure. Adaptive surfaces remain Stage 2 exit requirements, but they do not delay the first safe Desktop Control build.

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
    MacCompanionAgent/        # embedded LaunchAgent executable and process root
    MacCompanioniOS/          # iPhone and iPad client
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
    local-ipc/v0/
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

The repository name remains `MacCompanion`; user-facing spacing belongs in product metadata. `project.yml` is the non-secret XcodeGen source and the generated `MacCompanion.xcodeproj` is checked in for normal Xcode use. Project regeneration must be deterministic and both files must pass the permanent-target topology validator. Do not introduce a separate monorepo orchestrator, server stack, or protocol code-generation pipeline until repeated drift proves one is needed.

### Open-source posture

Use one public monorepo while the protocol and both endpoints evolve together. The normative `spec/` tree is independent of Swift and Apple frameworks; the Swift package is one implementation. Split the protocol into another repository only when external implementers need an independent release cadence.

Source availability does not confer Jenny Media signing identity, official update access, bundle identifiers, trademarks, or managed entitlements. Community forks use their own product identity, update feed, signing team, and Apple capability requests. Official release configuration and update URLs are injected separately and never become a usable trust anchor in an unofficial build.

The repository is already public, so the intended pre-publication controls are
now immediate remediation gates: select an OSI license and contribution policy,
reserve product trademarks separately, publish private vulnerability-reporting
instructions, publish the local `CODEOWNERS`, configure protected branches, and
enable secret scanning and push protection. Until the license and contribution
terms are approved, the checked-in contribution hold says that external work is
not accepted. Developer certificates, provisioning profiles, Sparkle private
keys, notarization credentials, App Store keys, pairing material, and real
diagnostic data never enter the repository.

Every third-party GitHub Action is pinned to an immutable full commit SHA and
reviewed before update; container actions are pinned by SHA-256 digest. Public
validation jobs disable persisted checkout credentials unless a reviewed step
has a narrow authenticated need. The repository gate rejects movable action
tags before compilation.

Apache-2.0 is the selected repository-wide license, paired with a separate Mac Companion/Jenny Media trademark policy, subject to written legal review. Use a Developer Certificate of Origin by default. Adopt a Contributor License Agreement only if Jenny Media LLC makes a deliberate dual-licensing or relicensing decision before accepting contributions. GitHub private vulnerability reporting is the initial security channel. Because the repository is already public, further pushes and external contributions remain paused until the license, trademark, contribution, and security policies, full-history review, and provider-side branch/secret/push protections are complete.

## 3. Target and module boundaries

The first Swift package contains narrow targets rather than a single universal utility module:

| Target | Platforms | Owns | Must not own |
| --- | --- | --- | --- |
| `CompanionDomain` | macOS, iOS | IDs, bounded values, host/session/operation state machines, errors | Network, storage, UI, Apple permission APIs |
| `CompanionWire` | macOS, iOS | Versioned envelopes, canonicalization, size bounds, fixtures | Trust decisions, sockets, UI |
| `CompanionSecurity` | macOS, iOS | Digests, challenge construction, key abstractions, authorization-epoch rules, and strict canonical host-certificate DER/profile/self-signature/current-validity inspection | Keychain UI, Security trust handles, network routes, providers |
| `CompanionAuthentication` | macOS | Opaque connection challenges, proof verification, current-device/epoch revalidation, authenticated principal | TLS sockets, UI, grants, or session presentation |
| `CompanionOperations` | macOS | Restricted-JCS/schema/registry admission, exact operation binding, transactional durable admission, and provider-neutral execution orchestration | UI, remote sockets, TCC APIs, or provider-owned trust decisions |
| `CompanionNativeProviders` | macOS | Reviewed Apple-framework desired-state adapters and their exact capability descriptors; current implementations are verified default-output mute plus a candidate-only four-hour-capped IOPM user-idle system-sleep assertion with explicit start-until/stop and system timeout | Grants, policy, remote sockets, arbitrary scripts, provider discovery, display forcing, undocumented global-appearance mutation, Apple Events, unbounded assertions, or advertising candidates before their promotion gates |
| `CompanionDiscovery` | macOS, iOS | Closed DNS-SD profile, canonical endpoint candidates, bounded untrusted TXT hints | Host identity, trust, sockets, Local Network permission UI |
| `CompanionLifecycle` | macOS | Explicit enable/disable intent, console-session/process state, recovery effects, Observe/Control availability | `SMAppService`, launchd, GUI recovery mechanism, or code identity |
| `CompanionObservation` | macOS, iOS | Conservative receipt-time freshness, monotonic expiry, live/stale/unreachable presentation state | Network connection ownership, UI, persistence, host sampling |
| `CompanionPresentation` | macOS, iOS | Platform-neutral connection/freshness snapshots, explicit-accept client QR pairing trust/SAS/durable-publication presentation, exact-command Mac create/dismiss pairing presentation with lost-response retry and immediate invalidation, one-review Mac SAS/local-name decision presentation with exact retry and withdrawal, locally named exact-effect grant review, one-session Interactive warning/stop state, correlated local device-name editing, Interactive Mac/route/control/lock/surface presentation, and typed recovery causes | QR camera/render implementation, localized copy, SwiftUI, sockets, XPC, key custody, persistence, grant authority, or lifecycle authority |
| `CompanionClient` | macOS, iOS | QR-secret/pinned-TLS client pairing, transcript/SAS and paired-identity publication, opaque session/approval key-custody interfaces, atomic client-record publication authority, strict canonical record encoding, bounded fsync/rename file persistence and restart recovery, pinned application handshake, all-or-nothing granted-capability catalog assembly, and schema-verified operation-result presentation | Security framework implementation, final container/Data Protection selection, sockets, grants, provider execution, arbitrary provider text, or SwiftUI |
| `CompanionClientApp` | macOS, iOS | Application-global QR pairing composition across exact connection/deadline propagation, prepared identity, transcript/SAS presentation, revision-fenced cancellation, sanitized failure, and durable-before-paired publication with noncancelable atomic-commit convergence | Platform sockets, QR camera, SwiftUI, Keychain implementation, final container policy, background lifecycle, or physical-device claims |
| `CompanionClientUI` | iOS | Value-driven pairing and connected-host SwiftUI surfaces, closed UI projections, and a stateless one-shot QR scanner surface whose UIKit controller owns camera lifecycle; preserves unverified/verified identity, durable-saving, view/control/lock, and Remote-Control-optional distinctions | App navigation, live pairing/network authority, final usage-description wiring, localization completion, final app target, signed camera permission recovery, or physical accessibility evidence |
| `CompanionMacApp` | macOS | Bundle-independent menu-app pairing composition: authenticated-local-client abstractions; exact create/dismiss and SAS/name-decision command retries; receipt correlation; clock-bounded expiry; exact review withdrawal; Agent-loss generation fencing; secret erasure; and delayed-response suppression | XPC construction or peer trust, Agent pairing authority, SwiftUI navigation, final app target, signed lifecycle evidence, or physical QR exchange |
| `CompanionMacUI` | macOS | Value-driven exact-effect capability review, one-session Interactive warning/stop, locally confirmed device-name surfaces, deterministic Core Image pairing-QR rendering, a reducer-driven QR sheet that prevents implicit close from masquerading as cancellation, and a SAS/local-name approval sheet that locks in-flight decisions and exposes only exact retry | XPC, pairing-session authority, durable authority mutation, capture/input ownership, final app target, localization completion, or physical accessibility evidence |
| `CompanionClientPlatform` | macOS, iOS | Security.framework P-256 key creation/lookup/deletion, role-specific this-device-only access profiles, Secure Enclave selection, LocalAuthentication approval context, public-key revalidation, and DER-to-raw message signature conversion behind opaque custody references | Physical access-control evidence, final access group/container policy, UI ownership, sockets, grants, or private-key export |
| `CompanionTransport` | macOS, iOS | TLS connection roles, framing, backpressure, reconnect policy, immutable-pin dial-round racing with authenticated-winner/late-route cleanup and authenticated command transport, and one reconnect owner for foreground/reachability/candidate/backoff transitions plus connected-route cleanup | Sockets, live trust extraction, grants, semantic authorization, screen capture |
| `CompanionPersistence` | macOS | SQLite transactions, migrations, quotas, durable repositories | UI and provider execution |
| `CompanionPairing` | macOS | Boot-scoped five-minute/five-proof pairing authority, transcript verification, validated key fingerprints, local-decision/name binding, and atomic name/device/consumption adapter | QR presentation, transport routing, or approval UI |
| `CompanionHost` | macOS | Host policy, status sampling, audit coordination, and native provider composition | Remote sockets and TCC presentation |
| `CompanionHostWire` | macOS | Versioned mapping from authenticated principals and host-owned snapshots to validated wire responses | Sampling, transport, persistence, authorization decisions |
| `CompanionHostSession` | macOS | Owns one host-side TLS-bound application session, authentication sequence, replay window, durable-principal revalidation, and status/Act/Interactive session-and-surface routing with host-owned command context | Listener construction, socket I/O, certificate custody, UI, or native authority |
| `CompanionNetworkPlatform` | macOS | Strict TLS 1.3/no-resumption host listener parameter construction from an exact custodied `SecIdentity`; sealed one-shot listener lifecycle owner; exact accepted-connection readiness and negotiated-metadata evaluation; one-use, exact-first-frame `auth.hello`/`pairing.begin` classification without over-read; classified-primary proof-gated activation; and serialized primary/pairing Network.framework pumps with byte-independent deadlines, silent pairing completion, and injectable no-network frame I/O | Physical listener/handshake evidence, interface policy, semantic authorization, or UI |
| `CompanionAgentNetworkPlatform` | macOS | Sole Agent ownership of the sealed listener lifecycle; a role-safe service constructor and generation-fenced ingress handoff with independent primary/pairing owners, proof-before-primary-replacement, and non-displacing visible pairing; exact Agent pairing-wire/pump binding; content-free network/route publication; atomic same-TLS-configuration/same-port listener-plus-pairing-context construction; and listener-plus-Bonjour-fenced pairing availability with active-QR invalidation on advertisement or listener loss | Host identity creation, additional private-route approval policy, pairing secret authority, authenticated XPC review publication, UI, or physical network evidence |
| `CompanionClientNetworkPlatform` | macOS, iOS | Client Network.framework byte-pump adapter, one-shot TLS-attempt context binding one closed route/pin/callback/exact connection, strict `SecTrust` single-leaf extraction, durable-session-key-bound reconnect composition with system nonce/message-ID generation, concrete authenticated reconnect attempts, and a no-relay pairing factory that races bounded QR routes with one pin, retains one verified winner, frames serialized traffic, and enforces one immutable byte-independent deadline | Live socket/permission/radio/background evidence, private-key custody, semantic authorization, or UI |
| `CompanionHostPersistence` | macOS | Adapters that commit host-owned sequence state through persistence repositories | Sampling, wire encoding, database schema ownership |
| `CompanionIPC` | macOS | Typed local messages, role restrictions, bounded sanitized diagnostics, complete transcript/key-fingerprint-bound pairing review and approval-name/decline-null decisions, an already-authorized exact-review presentation endpoint capability, correlated device-name and exact grant-decision administration, completed-authority Interactive stop, and Interactive install/renew/revoke/surface-replacement leases and receipts; platform adapter supplies authenticated peer identity | Durable authority mutation, media encoding, caller-self-asserted roles |
| `CompanionAgent` | macOS | Bundle-independent local administration orchestration: Agent-fact-owned one-visible pairing QR creation/dismissal with exact replay, compensating tombstones, and network-loss invalidation; exact SAS/key-fingerprint/policy-fenced local pairing review, atomic locally named pairing decision, bounded receipt replay, a connection-scoped exact-review delivery/withdrawal service issued by the local root, and a TLS-binding/host-identity-bound pairing wire owner that requires trusted-local acknowledgement before pending, withdraws every terminal review, closes unavailable review state early, and defers expiry across in-flight durable decisions; registry-generation/full-descriptor-bound one-time grant reviews, noninterleaving registry replacement, atomic SQLite grant-expansion adapter, exact dispatcher shutdown, ordered runtime safety-proof composition, authenticated initial-Desktop, target-inventory, and replacement surface sequencing, opaque-target resolution, Agent-issued install/replacement acknowledgement coordination, and bounded idempotency | XPC peer identity, capture/input effects, final-identity catalog binding, or independent provider-registry mutation outside this sole Agent serialization boundary |
| `CompanionAgentPlatform` | macOS | Thin Apple-framework adapters supplied with exact containing-app-owned platform objects; current scope is closed `SMAppService` status projection, registration, completion-awaited unregistration, durable desired-state storage/startup repair, a lifecycle-revision/per-role-epoch-fenced process observation owner, a sealed post-`AgentPrimaryServicesV1` self-ready root that issues serialized exact-generation menu connection capabilities only after platform authentication, and fixed three-attempt idempotent menu-start recovery fenced by exact revision/epoch/replacement state | Bundle identifiers, plist labels, service construction, raw process/IPC authentication, inventing readiness from registration/PID/status, XPC identity, unbounded or semantic-effect retry, or user-facing error text |
| `CompanionInteractiveShared` | macOS, iOS | Session authority, surface/focus models, privacy profiles, revision and input fences, transitions, fallbacks, and shared fixtures | Capture, decode, AX objects, input injection, app activation, UI |
| `CompanionInteractiveWire` | macOS, iOS | Exact Interactive Control binary media/input framing plus separate closed primary-channel initial-Desktop and replacement exchanges, strict cross-device relative-validity descriptors, focus fences, and shared per-direction sequences | TLS sockets, authorization decisions, candidate inventory, H.264 parsing, capture, input injection |
| `CompanionInteractiveHost` | macOS | Closed Interactive request/approval and initial/replacement surface-control dispatcher, atomic final-runtime admission contract, authenticated active-session/durable-admission rechecks, session/epoch/surface/expiry/input-stream composition, and capture/encode/input adapters behind executor interfaces | Device identity, network listener, durable grant storage, menu-app IPC, opaque-target resolution, or OS cryptographic randomness |
| `CompanionInteractiveClient` | iOS | Exact primary-bound Interactive Control request/approval/acceptance, fresh-presence approval signing, pinned-TLS role-channel mutual proof, first-Desktop clean-media activation with atomic live media/input authority and sequence handoff into reset-before-replacement coordination, cross-device descriptor materialization, pre-decoder media fence/sequence/configuration/keyframe admission, media-derived exact acknowledgement, host-reply-gated input reactivation, and reliable descriptor-bound input production | Approval-key custody, H.264 decoding, UIKit gestures, sockets, host-state authority, or remote grant changes |
| `CompanionInteractiveRuntime` | macOS | Single-owner visible-menu-app install/renew/revoke/surface-replacement authority, serialized async platform effects, lease expiry and Agent-IPC invalidation, idempotent receipts/actions, transition-ordered discontinuity/configuration/clean-keyframe admission, input suppression through exact Agent acknowledgement, current-lease input posting, digest-bound gap-free bounded media enqueue, and resumable fail-closed safety cleanup | XPC peer trust, TCC authority, capture/encoding/input implementation, AppKit UI, durable grants, or remote sockets |
| `CompanionHostPlatform` | macOS | Security.framework Interactive material generation; compile-tested prompt-free host identity custody, exact certificate signing and `SecIdentity` composition; conservative SQLite plus revision-fenced visible-menu-app admission joins; no-enumeration ScreenCaptureKit profile/filter construction; concrete compile-only `SCStream` session plus complete-frame normalizer and single-owner bounded event handoff; injectable and concrete VideoToolbox H.264 configuration/session composition; bounded CoreMedia parameter-set/access-unit/sample normalization; one-in-flight/one-latest-waiting latency-first encoder ownership with awaited publication backpressure; configuration/keyframe/discontinuity/end media-record publication through the lease-validating runtime with sequence-preserving surface transitions | Final signed Keychain/Secure Enclave evidence, authenticated menu-app XPC transport, concrete transition-route/capture composition, live capture/encode/input execution, or UI |
| `CompanionTestSupport` | test targets only | Fake clocks, randomness, stores, transports, providers, fixtures | Production linking |

Platform app targets are composition roots. They create concrete Apple-framework adapters and presentation state, but business rules remain in the owning module.

The pairing release path is narrower than the general platform-app rule. It
must use `AgentNetworkPairingProductCompositionFactoryV0`, which consumes one
sealed TLS listener configuration plus one complete startup-reconciled
`AgentPrimaryServicesV1` and binds listener/context, host ID, primary authority,
local status/route publishers, required-audit security store, pairing
authority, QR session handler, local decision handler, and already-authorized
review service. Split constructors are package-only test seams. See the
[pairing product composition evidence](evidence/2026-08-20-pairing-product-composition.md).

Interactive Control has the same release-root restriction for its durable
security facts. Public Agent bootstrap accepts only visible-menu observation,
OS-random material generation, runtime execution, and optional surface
execution seams. The root constructs durable admission from its exact private
security store and installs its required Interactive audit writer; raw primary
sessions, raw dispatchers, and alternate complete-dispatcher bootstrap are
package-only. The platform runtime still owes signed authenticated-XPC and
same-authority final-revalidation evidence. See the
[Interactive product composition evidence](evidence/2026-08-20-interactive-product-composition.md).

The bundle-independent first-runtime boundary preserves the exact
signature-bound approval effects and admitted menu generation/revision through
one-use lease/command preparation. It advances the session and releases the
role authorities only after an exact current receipt; ambiguity requires
teardown. The signed XPC bridge still owns atomic final revalidation and
installation. See the [initial runtime preparation evidence](evidence/2026-08-20-initial-runtime-preparation.md).

Observe status is also sealed at the release Agent root. Public bootstrap
accepts only a system sampler, clock, initial generation, and freshness bound;
it constructs the status authority with the exact root host ID and the same
private SQLite security store used by the other security authorities. Lazy
construction preserves fail-closed bootstrap ordering without consuming a
durable status revision when an earlier root gate fails. Raw status-provider
injection remains package/test-only. See the
[root-bound host-status evidence](evidence/2026-08-20-root-bound-host-status.md).

The release root also owns host identity. It reads one ready singleton from the
private security store instead of accepting a caller-authored host UUID, and
the public pairing/listener factory compares both the TLS configuration's SPKI
fingerprint and certificate DER to that exact record before consuming the
one-use listener. Missing, recovery-fenced, or cross-wired identity opens no
ingress. See the
[durable host-identity root evidence](evidence/2026-08-20-durable-host-identity-root.md).

Before that root can open, the host-identity startup coordinator persists a
schema-v7 candidate host UUID and exact Keychain application tag before key
creation. It resumes that same tag after a crash, atomically consumes the
candidate only with ready identity plus event, reconstructs valid listener
identity without rotation, replaces invalid certificates only around the same
fingerprint, and returns explicit first-unlock, key-loss, and recovery-fenced
states. See the
[host-identity startup evidence](evidence/2026-08-20-host-identity-startup-coordinator.md).

Locally confirmed destructive recovery is also composed below the final XPC
seam. The required-audit root issues a local review/admission service over its
exact private store and recovery coordinator. It atomically checks the reviewed
host identity before fencing, resumes a recovery-UUID-tagged new key, deletes
the old key while the fenced row still retains that tag, and only then
atomically publishes the rotated identity, event, and replay receipt. The
same fence transaction retains the exact bounded reviewed command intent, so a
restarted Agent can reconstruct only that command and a restarted menu app can
adopt it through a distinct authenticated resume delivery without reconfirming
or issuing new identifiers. The revision-fenced Mac owner displays all fixed
destructive effects and retains an exact failed command without gaining
recovery authority. A connection-scoped delivery actor serializes fresh review,
durable resume, and exact resolution against an already-authorized menu
surface, with endpoint-loss withdrawal and generation-fenced reentrancy; it
does not authenticate the final XPC peer. See the
[confirmed host-identity recovery evidence](evidence/2026-08-20-host-identity-confirmed-recovery.md)
and [local recovery confirmation evidence](evidence/2026-08-21-local-host-identity-recovery-composition.md).

The Agent Network-platform public startup factory consumes that result using
the same required-audit root and one wall-time sample. Non-ready identity states
return before provider or network construction. Ready identity then flows
through sealed TLS creation, provider/reconciliation/root bootstrap, and the
existing exact-certificate pairing/listener factory; no public release path can
substitute a prebuilt TLS configuration or primary root. See the
[unified Agent network startup evidence](evidence/2026-08-20-agent-network-product-startup.md).

The client reconnect release path similarly accepts key custody rather than a
prebuilt signer. It selects the exact session-key reference from the immutable
durable paired-host record, constructs the session-only signer internally,
uses system-generated nonces/message IDs, and fixes the strict pinned-leaf
evaluator. Raw primary-session, route-attempt, signer, randomness, and trust-
evaluator injection are package/test seams. See the
[client reconnect security evidence](evidence/2026-08-20-client-reconnect-security-composition.md).

Above that runtime, the client Network-platform product factory reads one exact
durable paired host and route revision, reconciles storage, constructs the
session-key-bound reconnect controller, and returns a pessimistic background/
unreachable application binding. The Client-platform UIKit factory owns the
default Boolean-only reachability/application bridge while exposing the same
lifecycle for local route settings. Pairing remains independently constructible
for first launch. See the
[configured-route Network product evidence](evidence/2026-08-20-client-configured-route-network-product.md).

Client pairing has a parallel public product factory in the Network-platform
module. It constructs the application owner, strict pinned-leaf route racer,
system clocks, and system randomness as one graph; the iOS target supplies
only client ID, custody, atomic persistence, queues, and presentation delivery.
Generic connection, clock, randomness, trust-evaluator, and route-attempter
injection are not public release paths. See the
[client pairing product evidence](evidence/2026-08-20-client-pairing-product-composition.md).

The LaunchAgent links transport, persistence, host policy, security, wire, and IPC modules. The Mac menu app links `CompanionMacApp`, IPC, Interactive Runtime, and platform adapters but not the remote transport or authorization database. The iOS app links `CompanionClientApp`, transport, security, wire, domain, and Interactive Client. Build settings and dependency tests should enforce these negative boundaries.

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

1. Use the privately confirmed Team ID and registered `media.jenny.maccompanion` App ID; keep the standalone Agent's build-proven code identity distinct, register remaining bundle IDs only when their permanent targets require them, resolve Apple's prerelease App Store URL/Apple ID path, and submit the prepared entitlement request.
2. Initialize version control, ownership rules, ADR template, and CI.
3. Keep the checked-in containing app and embedded inert Agent topology regression-bound; next add authenticated local IPC/lifecycle composition, then the iOS app and CLI as their identifiers and signed boundaries become ready.
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
| 13 | Add viewing presence and active revocation | [Bundle-independent durable local revoke convergence](evidence/2026-08-21-local-device-revocation-convergence.md), indicator truth, authenticated XPC, and sub-second physical revocation evidence |
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

Stage 0 coding proceeds in independent lanes. Accepted specifications, pure Swift packages, conformance tests, CI, permanent non-entitled target composition, and disposable platform harnesses do not wait for the managed-entitlement request. The Team ID is confirmed privately, the containing-app App ID is registered, and the separately signed Agent identity and LaunchAgent topology are build-proven; remaining iOS/XPC App IDs, authenticated designated requirements, Keychain groups, live `SMAppService` registration, and release-shaped stable-toolchain signing still require proof. The prepared entitlement request is blocked by Apple's required App Store URL and numeric Apple ID for the unreleased product, not by the Mac App ID. Entitlement approval, locked-session success, formal interviews, and completed market validation are not required for independent work or the Observe foundation.

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

## 13. Remaining implementation decisions

The company-controlled reverse-DNS prefix is resolved as `media.jenny`; the Team ID is confirmed privately and `media.jenny.maccompanion` is registered. The checked-in permanent containing-app target now embeds the separately signed but inert Agent and proves local Apple Development and Developer ID signing, hardened runtime, distinct exact identities, universal construction, LaunchAgent layout, and privacy ownership on Xcode 27 beta without tracking a team, credential, profile, or managed entitlement. Stable macOS 26/Xcode 26.6, authenticated lifecycle execution, and controlled release custody still gate final signed release evidence, while entitlement approval blocks only external Persistent Content Capture builds. The entitlement form is prepared but requires an App Store URL and numeric Apple ID; that truthful prerelease/direct-distribution path remains external. None of these blocks specifications, packages, fixtures, CI, Xcode 27 beta development, authenticated Mac/Agent composition, remaining permanent targets, or disposable experiments. The following are bounded implementation decisions and do not require more product clarification:

- Exact authenticated local IPC peer-verification mechanism
- Signed/physical X.509 and Keychain execution plus authenticated local recovery confirmation under the frozen lifecycle profile
- Live Network.framework SPKI extraction and pinned-leaf verification under the frozen role-admission profile
- Measured video adaptation thresholds
- Whether public APIs support the genuine lock surface
- Smart Input compatibility and whether any profile beyond keystroke-only can be supported safely
- Final audit quota and retention numbers

Each has a spike, acceptance evidence, fallback, and ADR location. None may silently broaden access or introduce a vendor relay.
