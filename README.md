# Mac Companion

Mac Companion is a native iPhone and iPad companion for checking, operating, and directly controlling a personal Mac through a standalone macOS agent.

The product is local-first and policy-driven, with three first-class paths: **Observe** current state, **Act** through bounded capabilities, and **Control** through an adaptive remote desktop. Control is the flagship capability, but it is not required for status checks or approved actions. Inside a control session, Mac Companion can move from the full desktop to a phone-readable application, window, or focused region while preserving the desktop as an escape hatch. It is not a general shell, arbitrary file browser, vendor relay, or hidden agent. The Mac remains the final authority, and active remote use is visible and audited.

> **Name decision:** **Mac Companion** is the implementation name and intended public product name, with the proposed App Store subtitle **Monitor and control your Mac**. The installed Mac component is **Mac Companion Agent**. Company-controlled bundle identifiers may be registered independently of the public name, while public launch still requires written trademark review and App Store name reservation.

## Product position

Mac Companion is a private control companion for personal Macs, especially always-on home Macs, multiple-Mac setups, and MacTools users. Its differentiators are:

- Per-device authorization and default-deny remote exposure
- Host-side policy and execution revalidation
- Clear paired, connected, viewing, and controlling states
- Understandable local audit history
- Direct local or user-managed private-network connectivity
- Three independently useful paths: Observe, Act, and Control
- First-class Interactive Control for live screen, mouse, and keyboard access
- Adaptive Remote Surfaces: App Focus, Window Focus, and Smart Zoom instead of forcing every visual task through a scaled desktop
- A provider model that can expose MacTools and other canonical capabilities without exposing arbitrary internals

## Core decisions

- Build an independent macOS service and native iOS client first.
- Treat the first local-only build as a technical alpha, not the market MVP.
- Validate the native no-relay MVP before adding a MacTools adapter; use MacTools as the first external integration before generalizing a public provider SDK.
- Use a per-user LaunchAgent for reliable service ownership after login, with the menu-bar app as its trusted UI and administration client.
- Explicitly treat logout or no logged-in user as offline in the first release; a boot-time daemon is a later packaging decision.
- Bundle a diagnostic CLI that uses the same local policy, executor, and audit path.
- Use Bonjour locally and a saved Tailscale or private-network endpoint remotely.
- Operate without a Mac Companion relay or network account; private-route setup remains user-managed.
- Keep host identity independent of network address so LAN and private-network endpoints can change without re-pairing.
- Keep iOS live monitoring foreground-oriented. A no-relay release does not promise background iPhone alerts or continuous sockets.
- Use desired-state, retry-safe actions instead of toggles where possible.
- Keep Observe, Act, and Control independently useful and independently authorized; do not require a video session for status or bounded actions.
- Include live screen, pointer, and keyboard control in the MVP validation path, but keep shell, arbitrary files, clipboard synchronization, and AI outside it.
- Include App Focus, Window Focus, and Smart Zoom in the Interactive Control MVP. Treat native Smart Input as a gated experiment and semantic/app-provided surfaces as post-MVP work.
- Require a logged-in macOS user. A locked session may remain observable and may expose the genuine macOS lock screen if public APIs permit; Mac Companion never bypasses authentication or reveals the desktop behind the lock.

## Documents

- [Product proposal](docs/product-proposal.md)
- [Architecture](docs/architecture.md)
- [Protocol outline](docs/protocol-outline.md)
- [Interactive Control specification](docs/interactive-control-spec.md)
- [Adaptive Remote Surfaces](docs/adaptive-remote-surfaces.md)
- [MVP plan](docs/mvp-plan.md)
- [Distribution plan](docs/distribution-plan.md)
- [External TestFlight review package](docs/testflight-review-package.md)
- [Implementation orchestration](docs/implementation-orchestration.md)
- [Execution and blocker ledger](docs/execution-status.md)
- [Permission and process matrix](docs/permission-matrix.md)
- [ADR-0001: process and trust boundary](docs/adr/0001-process-and-trust-boundary.md)
- [Stage 0 threat model](docs/threat-model/stage-0-trust-kernel.md)
- [Research and decisions](docs/research-and-decisions.md)

## Proposed products

- **Mac Companion for iPhone and iPad:** Pair with Macs, view fresh status, invoke approved actions without streaming the screen, or open Adaptive Remote Desktop to control the desktop, an app, a window, or a focused region.
- **Mac Companion Agent:** A per-user LaunchAgent that owns pairing, networking, identity, grants, policy, providers, audit history, and durable task state while that user remains logged in.
- **Mac Companion menu app:** Persistent local administration and activity UI. It owns ScreenCaptureKit and Accessibility-mediated input, and Interactive Control stops if this visible process is unavailable.
- **`maccompanionctl`:** Bundled diagnostic CLI that communicates only with the local service.
- **MacTools adapter:** First post-MVP external provider integration and the proving ground for the provider contract.

## Current status

The reconciled design baseline and bundle-independent trust kernel are present. `MacCompanionKit` now includes strict protocol/security/persistence authorities; host and QR-pinned client pairing; host and client application authentication; a single replay-, liveness-, and durable-principal-fenced host primary session; a paired-identity-fenced client primary handshake; separate compile-checked Network.framework host and client byte pumps behind independently verified TLS handoffs; host status; bounded Act admission/execution; privacy-limited granted-capability discovery; schema-verified client catalog/result models; the conservative native audio-mute candidate; transport/discovery/lifecycle/presentation models; and both host and client Interactive Control session, surface, media, input, approval, and channel authorities.

The macOS lifecycle path also includes a [two-role login-effect executor](docs/evidence/2026-08-20-login-role-effect-executor-construction.md) that registers Agent before menu, compensates partial enablement in reverse, attempts both disable unregistrations, converges idempotent and effect-then-error platform states through exact postconditions, and uses a label-free `SMAppService` adapter without treating registration as process readiness.

The [Agent sanitized diagnostic export service](docs/evidence/2026-08-21-agent-diagnostic-export-service.md)
backs both the diagnostic CLI and Mac dashboard with a boot-scoped newest-256
content-free event ring plus a fresh validated status snapshot. It exposes no
arbitrary detail, file writer, upload path, or substitute for durable audit
history. A [signed disposable XPC probe](docs/evidence/2026-08-21-signed-local-xpc-peer-identity-probe.md)
now proves reciprocal exact-identifier/same-team admission plus closed hello
shape and version rejection; production transport and teardown remain gated.

The [Mac dashboard action coordinator](docs/evidence/2026-08-21-mac-dashboard-action-coordinator.md)
uses one shared admission policy for SwiftUI and execution, serializes every
dashboard effect, preserves ambiguous outcomes, routes only typed local
destinations, and fences late completion after local-authority replacement.
Concrete lifecycle/status/diagnostic adapters remain final signed-target work.

The [dashboard lifecycle product composition](docs/evidence/2026-08-21-dashboard-lifecycle-product-composition.md)
now implements the lifecycle adapter with registration-before-enable
compare-and-commit, stale-state compensation, remote-safe disable ordering,
truthful process-start failure, and idempotent same-desired-state convergence.
The [durable lifecycle intent and restart reconciler](docs/evidence/2026-08-21-durable-lifecycle-intent-reconciliation.md)
now writes desired state first through a revision-fenced atomic store, defaults
missing storage to disabled, restores no stale readiness, and converges roles
plus live state before a final target may report ready. Final signed service
construction and physical lifecycle evidence remain.

The [generation-fenced process observation owner](docs/evidence/2026-08-21-process-observation-and-lifecycle-aba-fencing.md)
now keeps registration and launch requests distinct from readiness, rejects
stale ready/termination callbacks across per-role epochs, orders remote-safe
exit before exact recovery, and closes lifecycle compare-and-commit ABA with a
boot-scoped revision. Final signed process/IPC sources remain required.

The [lifecycle observation source composition](docs/evidence/2026-08-21-lifecycle-observation-source-composition.md)
now makes the completed Agent service graph the self-ready source and issues
one serialized menu-generation capability only after the final adapter has
authenticated that connection. No caller role, PID, registration status, or
service label can create readiness through this boundary.

The [bounded process recovery scheduler](docs/evidence/2026-08-21-bounded-process-recovery-scheduling.md)
adds exactly three revision/epoch-fenced menu-start retries after a failed or
ambiguous initial request. Replacement, lifecycle change, success, cancellation,
or exhaustion stops the loop; it never invents process readiness and cannot be
used for semantic remote operations.

The [bounded native keep-awake candidate](docs/evidence/2026-08-21-native-bounded-keep-awake-provider.md)
adds explicit start-until and idempotent stop actions backed by a public IOPM
user-idle system-sleep assertion with a four-hour maximum and system-enforced
timeout. It remains outside the advertised registry until its signed physical
behavior and dedicated time-picker UX pass.

The proposed three-state
[system-appearance action is a Stage 0 no-go](docs/evidence/2026-08-21-native-system-appearance-no-go.md):
AppKit can only set Mac Companion's own appearance, while System Events adds
Automation consent and still cannot represent the user's automatic/system
mode. Repository validation rejects undocumented global mutations and keeps
Apple Event authority out of the Agent and current native-provider target.

The [public CI boundary](docs/evidence/2026-08-20-public-ci-supply-chain-hardening.md) is unsigned and read-only, pins every remote action immutably, disables checkout credential persistence, and validates that policy before compilation. A [repository material scanner](docs/evidence/2026-08-20-repository-material-boundary.md) checks every publishable file and every reachable historical blob/path for forbidden credentials, signing configuration, private databases, and unscannable path/size escapes. The [Swift dependency policy](docs/evidence/2026-08-20-swift-dependency-policy.md) still inventories all four local manifests and three in-repository edges; its [v1 exact Sparkle admission](docs/evidence/2026-08-23-exact-sparkle-dependency-admission.md) separately permits only Sparkle 2.9.6 for the Mac containing app, binding the exact version, full revision, artifact/license digests, lockfile, consumer, privacy facts, and sanitizer. Twenty-four combined fixtures keep every other remote package, binary target, path escape, or executable build plugin closed. A [2026-08-23 read-only live audit](docs/evidence/2026-08-23-public-repository-live-audit.md) confirms that GitHub remains public with no detected license, branch protection, ruleset, or enabled secret-scanning/push-protection baseline while the clean local branch is 74 commits ahead and unpushed. Local `CODEOWNERS`, a contribution hold, and the exact-head publication checklist reduce ambiguity, but legal review and provider protections remain required before any push.

The [release evidence profile](docs/evidence/2026-08-20-release-evidence-manifest-construction.md) separately validates unsigned construction, signed candidates, and promotion-ready releases. Its unsigned generator captures exact source/toolchain facts and hashes the validation log; file verification detects later mutation or path escape. An unsigned build, placeholder checksum, failed physical scenario, or missing human approval cannot be represented as releasable evidence.

The [source dependency SBOM generator](docs/evidence/2026-08-20-source-dependency-sbom.md) emits deterministic SPDX 2.3 JSON only after the live closed dependency policy passes. It now records Mac Companion, MacCompanionKit, and exact Sparkle 2.9.6 with its audited revision and digests, while explicitly retaining that built-artifact composition and legal conclusions are not yet asserted, so it cannot be mistaken for the final signed-candidate SBOM.

The [direct-update trust policy](docs/evidence/2026-08-23-update-trust-policy.md)
now freezes Sparkle 2.9.6 at its full upstream revision before admitting the
dependency. A subsequent [binary provenance and topology audit](docs/evidence/2026-08-23-sparkle-provenance-and-topology-audit.md)
binds its exact upstream manifest, SwiftPM archive, shared license, safe archive
shape, privacy behavior, and minimal non-sandboxed runtime graph. It requires
system profiling and custom feed parameters disabled, strips the two unused
XPC services, and keeps every release tool outside the app. The policy also
requires distinct release-injected beta/stable authorities,
signed feeds, verification before extraction, Ed25519 plus Developer ID trust,
notarized whole-bundle replacement, no initial deltas, and a fresh foreground
confirmation followed by closed admission, inactive Control, drained work, and
a stopped Agent. Thirty-five adversarial fixtures pass; no framework, feed,
key, download, or update action exists yet. The [exact dependency admission](docs/evidence/2026-08-23-exact-sparkle-dependency-admission.md)
now links and embeds Sparkle in an unsigned archive while proving the XPC
services and release tools absent; updater construction remains absent.

The [update installation runtime gate](docs/evidence/2026-08-23-update-install-runtime-gate.md)
now serializes that candidate through a five-minute foreground confirmation,
exactly inactive Control, closed network admission, bounded-work drain, Agent
stop, version match, and one updater handoff. Cancellation records whether
network-only or Agent-plus-network reconciliation is required, and reentrant
events cannot relabel a consumed handoff. Twelve focused tests pass. The
[inert permanent Sparkle adapter](docs/evidence/2026-08-23-inert-sparkle-runtime-adapter.md)
now accepts only a complete release-injected channel, canonical HTTPS XML feed,
and canonical 32-byte Ed25519 public key; community and development builds
construct no updater. Configured builds disable profiling, headers, custom
parameters, automatic checks, and downloads, and expose only an explicit
informational probe in the local menu UI. The subsequent
[exact update candidate admission](docs/evidence/2026-08-23-exact-update-candidate-admission.md)
requires the later post-validation channel, builds, display version, archive
URL, and six trust facts to match that reviewed item before minting one runtime
authority; rejection, cancellation, or reuse consumes it. All download and
installation checks remain denied. The package-owned
[runtime shutdown coordinator](docs/evidence/2026-08-23-update-runtime-shutdown-orchestration.md)
now seals the lower-level authority, rechecks foreground/time/Control at each
transition, executes the exact network-close, work-drain, Agent-stop, and updater
effects, and completes the recorded minimum recovery scope. The containing app
must still map those injected seams to the exact Sparkle validation lifecycle
and concrete runtime owners. The subsequent
[signed update publication binding](docs/evidence/2026-08-23-signed-update-publication-binding.md)
requires Sparkle's successful signed-appcast status, a bounded archive length,
and a canonical 64-byte Ed25519 signature in the informational candidate, then
correlates both archive facts exactly at admission. The audited 2.9.6 callback
does not prove Jenny Media signing identity or notarization, so those facts
remain closed behind a protected release-evidence bridge rather than being
manufactured from `didExtractUpdate`.
The subsequent
[update release-evidence projection](docs/evidence/2026-08-23-update-release-evidence-projection.md)
defines that bridge as a closed 17-attribute signed-enclosure schema. It binds
the exact candidate and five canonical artifact/evidence digests, replaces the
three ambiguous release-trust Booleans with one typed value, and requires all
Developer ID, notarization, application-stapling, and whole-ZIP claims to be
`passed`. The app still permits only informational probes and exposes no
download or installation path; it can only consume the reviewed offer once
into an inert candidate/evidence seed for the later validation bridge.
The subsequent
[validation-correlation checkpoint](docs/evidence/2026-08-23-update-validation-correlation.md)
replaces that exposed seed with a package-owned single-use actor. It requires
the complete signed publication to match across ordered `willExtract` and
installer-start observations, but treats Sparkle 2.9.6's misleadingly named
`didExtractUpdate` as intermediate only. Runtime admission opens only at the
later `showReadyToInstallAndRelaunch` user-driver hold point, after Sparkle's
asynchronous validation and stage-one preparation. Every mismatch or race
closes the actor, and the lower-level admission primitive remains
package-internal. The adapter still implements none of these callbacks and
does not enable a full update check.

The [exact-candidate artifact SBOM](docs/evidence/2026-08-21-exact-candidate-artifact-sbom.md) separately inventories the executable-bearing ZIPs themselves, emits reciprocal `filesAnalyzed: true` SPDX with SHA-1/SHA-256 and package verification codes, and binds release version/build/targets/revision, packaged hashes and sizes, and executable paths/modes. Signed-candidate `--verify-files` rejects source-SBOM substitution, unsafe or noncanonical archives/evidence, metadata substitution, and post-generation archive changes. The [Mac packaging-equivalence receipt](docs/evidence/2026-08-21-mac-packaging-equivalence.md) binds those exact ZIP trees to the sole release DMG through an explicitly authorized read-only APFS inspection, exact device cleanup, and post-inspection rehash. The current [Sparkle nested Developer ID packaging checkpoint](docs/evidence/2026-08-23-sparkle-nested-developer-id-packaging.md) independently verifies all five retained app, Agent, framework, and helper subjects, signs the DMG, and proves one 117-entry application tree across both ZIPs and the DMG while explicitly retaining the unnotarized, unstapled, unsigned-update, non-promotable state. A real signed-candidate claim remains closed until this path runs on the final signed/notarized artifacts under the stable release lane.

The [platform-signing fixed-tool runner](docs/evidence/2026-08-22-platform-signing-fixed-tool-runner.md) provides the first protected-collector execution primitive: pinned absolute tool identity, exact shell-free argv, a closed environment and private root, bounded time and raw outputs, explicit signal/timeout/overflow results, and mode-0600 hashed output retention. The [subject reconstruction and plan derivation](docs/evidence/2026-08-22-platform-signing-subject-reconstruction.md) descriptor-binds and rehashes exact Mac/iOS artifact-SBOM trees, admits only private-root-matched platform provenance, verifies symlink topology and Darwin mode normalization, requires complete graph/release/source coverage, and emits inert deepest-first fixed `codesign` plans. The subsequent [fixed verification execution and parser](docs/evidence/2026-08-22-platform-codesign-verification-execution.md) rederives those plans, reinspects the subject around every real invocation, reopens both retained streams by exact hash and private filesystem facts, and accepts only a closed path-bound success grammar. The [per-architecture construction](docs/evidence/2026-08-22-per-architecture-signature-inspection-construction.md) adds complete numeric-slice inspection plans and independent embedded CodeDirectory, designated-requirement, CMS, runtime, and duplicate-safe XML entitlement facts. The [protected architecture executor](docs/evidence/2026-08-22-per-architecture-signature-inspection-execution.md) now requires freshly revalidated whole-subject success, rehashes the complete candidate around each fixed call, privately retains a bounded contiguous certificate chain, reopens raw outputs exactly, and composes embedded, Apple-display, certificate, and policy facts while retaining `platformAcceptanceEligible: false`. The [semantic DER-entitlement checkpoint](docs/evidence/2026-08-22-der-entitlement-semantic-equality.md) independently decodes the measured CoreEntitlements v1 grammar and admits XML-plus-DER signatures only when both exact bounded policy projections agree; DER-only remains outside v0.1. The [outer codesign checkpoint](docs/evidence/2026-08-22-outer-codesign-verification-construction.md) adds one immutable, graph-bound `--deep` consistency check for the exact reconstructed Mac app without using it for discovery or repair. The [outer prerequisite-correlation checkpoint](docs/evidence/2026-08-22-outer-codesign-prerequisite-correlation.md) rederives and reopens every whole-object and architecture result before the outer invocation, repeats that complete reinspection afterward, and rejects omission, substitution, retained-certificate mutation, or changed policy facts. The [canonical platform-signing record](docs/evidence/2026-08-22-canonical-platform-signing-construction-record.md) deterministically binds the exact release/SBOM/graph/policy bytes, environment, fixed tool, reconstructed subjects, and complete signing records under the 8 MiB profile while retaining every target-specific unresolved gate and immutable `platformAcceptanceEligible: false`. The [Mac Gatekeeper and stapler construction](docs/evidence/2026-08-22-mac-gatekeeper-stapler-construction.md) adds exact graph-bound `spctl` and directly pinned `stapler validate` plans after complete signing reinspection, with Apple-tool-measured success grammars and subject/prerequisite postflight checks. The [two-phase notarization construction](docs/evidence/2026-08-22-two-phase-notarization-correlation-construction.md) corrects the earlier one-submission release shape: it requires distinct accepted transient-app-ZIP and final-content-DMG submissions, exact filename/hash/UUID/log correlation, zero reported issues, nonempty tickets, and application-before-DMG ordering. The signing lane remains deliberately not acceptance-capable: protected submission execution, both post-staple byte transitions, final app/DMG assessment, and stable-toolchain release evidence must still pass before `signedCodePlatformVerificationRequired` can clear.

The [protected notarytool executor](docs/evidence/2026-08-22-protected-notarytool-execution-construction.md) now privately pins each exact upload, uses fixed non-waiting submit plus later info/log calls, rehashes around execution and raw-evidence reopening, and redacts both the Keychain profile and private absolute upload path from retained invocation records. Its validator uses injected Apple responses only. Real uploads, current successful-JSON measurement, application/DMG stapling, and post-staple final-artifact correlation remain explicitly authorization-gated.

The disposable [capture/encode smoke command](docs/evidence/2026-08-21-capture-encode-smoke-construction.md)
now composes the production ScreenCaptureKit and VideoToolbox owners behind an
exact explicit command, one-clean-keyframe acceptance, five-second timeout,
and content-free 17-key report. Eight injected tests pass. The live
permission-denied branch emitted the closed report without prompting or
constructing a graph; real capture remains unrun until Screen Recording is
manually granted on a designated test account.

The [production local-XPC handshake](docs/evidence/2026-08-21-production-local-xpc-handshake-construction.md)
binds the permanent Mach service and targets to reciprocal same-team
exact-identifier requirements and a closed non-authorizing hello. The subsequent
[menu-readiness binding](docs/evidence/2026-08-21-local-xpc-menu-readiness-binding.md)
adds one exact acknowledged post-authentication readiness message, ordered
generation-bound lifecycle publication, authenticated replacement that fences
and cancels the old peer without false recovery, and exact fail-closed transport
cancellation. The subsequent content-free status binding adds an explicit closed read-only
profile, canonical typed snapshots, single-flight generation fencing, and
recoverable source-unavailable replies. The permanent Agent now delegates to a
single sealed application owner: exact enabled/starting preparation selects
readiness/status, exact disabled/stopped selects the one-use durable bootstrap,
durable recovery selects closed authentication-only, and first-unlock deferral
constructs no service. Signed runtime evidence remains a separate gate.

The [local-XPC Agent and dashboard product composition](docs/evidence/2026-08-21-local-xpc-product-composition.md)
now seals the complete startup-reconciled Agent services, lifecycle observation
root, full readiness/status profile, ordered event pump, and typed status reader
behind one product root. The menu-side product drives authenticated hello,
readiness acknowledgement, typed status, temporary source-unavailable retry,
transport-generation fencing, and terminal dashboard retirement without
granting Control or exposing raw payloads. Fifteen injected product tests pass.
The permanent Agent now owns the readiness/status side of this composition only
for exact enabled startup; the permanent menu shell remains transport-inert and
truthfully unavailable until signed runtime activation is connected and proven.

`CompanionAgentPlatform` is a macOS-only host-administration product inside the
aggregate package. iOS application targets must use the separately cross-built
client products; the package-wide iOS floor is not a claim that AgentPlatform
or its host persistence dependencies support iOS.

The [Apple privacy-manifest boundary](docs/evidence/2026-08-20-apple-privacy-manifest-boundary.md) freezes strict candidate resources for the iOS app, Mac containing app, and Mac Agent service. Its validator checks closed plist schemas, the live Swift target graph, and every covered required-reason API source occurrence through 12 adversarial/valid fixtures. These resources are target-ready templates; final signed bundles still must prove that the correct manifest was copied into every executable bundle.

The [Agent release storage root](docs/evidence/2026-08-21-agent-release-storage-root.md) now uses a fixed public release factory to compose one canonical private Application Support hierarchy, handle/path-bound bounded security and audit databases, and a cross-process-locked emergency deny latch into the required-audit composition. Its package-only injection seam is reserved for path, quota, and race tests; diagnostic paths are not represented as a same-UID security boundary. The permanent Agent now invokes this storage root only through the narrow activation-inert preparation boundary; live lifecycle and platform activation remain separate.

The [prepared Agent product bootstrap](docs/evidence/2026-08-21-prepared-agent-product-bootstrap.md) removes the ready-path authorization cycle: host identity, TLS binding, provider/recovery reconciliation, and the primary/local-service root are prepared without a listener, pairing owner, QR context, or caller-supplied review surface. A separate top-layer package product retains that exact preparation with release storage and an inert local-XPC product. Its later composition checkpoint supplies authenticated presentation routing while runtime activation remains disconnected.

The [authenticated menu presentation-surface router](docs/evidence/2026-08-21-authenticated-menu-presentation-surface-router.md) now converts one future already-authenticated menu generation into only pairing-review and host-recovery presentation facets. Strict generation high-water and private issuance-token fences, shared activation/retirement barriers, post-acknowledgement stale checks, and a post-admission weak terminal fence separated from the owner's awaitable finish barrier prevent rollback, stale-facet revival, rejected or retired endpoint shutdown, retain cycles, and teardown self-await. No permanent target constructs it and no XPC presentation message or runtime activation is claimed.

The [authenticated menu presentation contract](docs/evidence/2026-08-21-authenticated-menu-presentation-contract.md) now freezes five explicit publish/withdraw authorizations, exact request/reply shapes, a separate 4,096-byte canonical payload limit, nonzero withdrawal identifiers, pairing identifier/revision bounds, and fresh-review versus durable-resume expiry semantics. A fixture-to-code test binds the normative method set and size ceiling directly to the implementation. That contract checkpoint itself did not claim a menu receiver, product activation, or permanent-target construction.

The [authenticated ready-generation sender](docs/evidence/2026-08-21-authenticated-menu-presentation-sender.md) now binds those five exact envelopes to one cached opaque endpoint issued only for the exact current authenticated and ready peer under an explicit profile used only by package construction. One active plus seven queued requests share the production FIFO; cancellation, overflow, timeout, malformed replies, replacement, and peer-wide cancellation fence all fail closed before session cancellation. The endpoint has no raw session and latches weak-transport failure until its router fence exists. That sender checkpoint itself did not claim a menu receiver, product activation, or signed two-process exchange.

The [authenticated menu presentation receiver](docs/evidence/2026-08-21-authenticated-menu-presentation-receiver.md) now installs the incoming handler before client activation and admits only exact Agent-to-menu operations after authenticated readiness. The production receiver generation is directly testable and owns synchronous copies, exactly-once request leases, one-active-plus-seven-queued FIFO mutation, canonical typed decoding, fresh-only recovery clock checks, exact replay and withdrawal, acknowledgement-after-retention ordering, two-second deadlines, terminal late-callback fences, and an awaitable exact-ID retirement barrier. The public client initializer and permanent targets remain presentation-inert; sender/receiver composition and signed two-process evidence are still separate gates.

The [authenticated menu product composition](docs/evidence/2026-08-21-authenticated-menu-product-composition.md) now connects accepted lifecycle readiness to the exact sender endpoint and generation router, immediately revokes a ready generation when an authenticated replacement arrives or its endpoint terminates, gives the prepared Agent a stable narrow pairing/recovery authority across menu replacements, and waits for authenticated menu availability before consuming the one-use primary preparation into a nonescaping unstarted network product. The production dashboard receiver uses menu-owned presenters with awaited teardown. Menu loss cancels pending visible review state while keeping primary ingress and Observe nonterminal, so a later authenticated generation may deliver a fresh review. The permanent targets remain inert; that checkpoint's listener-activation gate is now implemented by the coordinated product seam below, while signed two-process evidence remains separate.

The [coordinated Agent network-listener activation](docs/evidence/2026-08-21-coordinated-agent-network-listener-activation.md) now constructs, starts, retains, and rolls back the sealed shared listener inside that same nonescaping prepared-product owner. Exact Network callbacks remain the only source of listener and Bonjour readiness, concurrent activation is rejected, start failure terminally converges the one-use product, and menu replacement leaves the listener/Observe path nonterminal. The permanent targets still do not invoke this package seam; live request-context composition and signed two-process evidence remain separate gates.

The [conservative network request-context product](docs/evidence/2026-08-22-conservative-network-request-contexts.md) now owns live wall and monotonic clocks, fresh response IDs, public macOS session/lifecycle notifications, and terminal observer cleanup. The accompanying [public-API research](docs/research/2026-08-22-public-macos-session-state.md) confirms that documented console/session facts do not distinguish an unlocked screen from a locked or switched session, so no public event promotes the Agent to `userSessionActive` or `userSessionLocked`; ambiguity remains `otherConsoleUserActive`. This is safe wiring material, not permanent-target activation or signed runtime evidence.

The [inert Agent application lifecycle facade](docs/evidence/2026-08-22-inert-agent-application-lifecycle-facade.md) now retains one safe-disabled ambiguous product-lifecycle snapshot and that conservative context owner. Construction reads no session facts; start installs only the public workspace observer; explicit or deinitializing terminal finish is idempotent and fails retained primary contexts closed. It deliberately exposes no storage, Keychain, XPC, listener, process-start, login-registration, readiness, pairing-session, or runtime-activation surface, and neither permanent target imports it.

The [durable-intent-ordered Agent preparation facade](docs/evidence/2026-08-22-durable-intent-agent-preparation.md) now constructs one release storage root, loads the absent-safe-disabled or enabled-ambiguous desired state from a dedicated intent subdirectory, and only then prepares host identity and the primary Agent root. A ready result is retained behind its canonical lifecycle snapshot and terminal finish only. This layer may reconcile durable storage and Keychain identity when invoked, but readiness-producing local-XPC construction is deferred until a later package-owned activation; it cannot start an observer, XPC service, listener, process, login role, pairing session, or readiness path.

The [permanent Agent inert-preparation integration](docs/evidence/2026-08-22-permanent-agent-inert-preparation.md) established the dedicated narrow application product. At that checkpoint, the executable retained only the prepared owner and an authentication-only XPC service; first-unlock wait exited for configured launchd retry. The single-service selector below supersedes that temporary runtime policy while preserving its preparation ordering, first-unlock behavior, and fail-closed compensation.

The [permanent menu dashboard lifecycle bridge](docs/evidence/2026-08-22-permanent-menu-dashboard-lifecycle.md) replaces the containing app's synthetic unavailable/retry timer with a package-owned, main-actor observable owner around the real generation-fenced dashboard product. Its construction remains transport-inert, while the application-launch owner below now invokes its package-scoped start. Start failure, finish/start races, repeated finish, post-finish retry, and deinitialization converge through one awaitable terminal barrier without inventing availability.

The [permanent Agent single-service selector](docs/evidence/2026-08-22-permanent-agent-single-service-selection.md) hides all local-XPC construction behind one no-argument application-platform startup. The later [production bootstrap binding](docs/evidence/2026-08-22-agent-bootstrap-production-binding.md) revalidates the exact revision-zero prepared lifecycle immediately before selection, starts the one-use durable bootstrap for canonical disabled/stopped state, keeps durable recovery on closed authentication-only, and constructs no service for first-unlock retry. The selected mode never escapes; failure or cancellation joins terminal cleanup and never falls back. The executable no longer imports or directly links LocalXPC and can retain only the one running owner plus its restart latch.

Canonical enabled startup now uses the [permanent enabled-Agent network activation](docs/evidence/2026-08-22-permanent-enabled-agent-network-activation.md): it starts conservative request contexts, authenticated presentation-capable local XPC, waits for an authenticated menu generation, consumes the one-use TLS/primary preparation, and starts one shared LAN listener on the fixed v0.1 private-range port. Any failure retires the whole product. This was construction-tested only; the permanent menu still uses the presentation-inert dashboard client, so pairing or recovery publication would fail closed. Permanent menu presentation plus pairing-session and decision commands remain the next gate before signed LAN pairing.

The [permanent menu application launch](docs/evidence/2026-08-22-permanent-menu-application-launch.md) established an exactly-once package-owned dashboard lifecycle. The later [foreground setup composition](docs/evidence/2026-08-22-foreground-remote-access-setup.md) now routes real AppKit launch through exact Agent-registration inspection without treating registration as readiness: absent registration exposes explicit setup, enabled registration attempts a fresh authenticated dashboard, and approval-required registration exposes local recovery. The executable retains the exact `SMAppService` values and typed product facades but cannot select a server profile, construct raw storage/bootstrap authority, or start network ingress.

The [current signing revalidation](docs/evidence/2026-08-22-signing-identity-revalidation.md) proves that the earlier zero-identity result was restricted-sandbox Keychain visibility, not missing credentials. The permanent Debug app and embedded Agent now strict-verify under the existing same-team Apple Development identity with their exact distinct identifiers and hardened runtime. Signed construction is open on Xcode 27 beta; durable explicit Agent enablement and reciprocal signed readiness/status remain the next runtime gate.

The [disabled-Agent bootstrap protocol](docs/evidence/2026-08-22-disabled-agent-bootstrap-protocol.md) now freezes that first-enable transition without weakening readiness. A foreground setup action may register only the inert Agent to reach its authenticated bootstrap profile; a five-minute Agent offer and complete consent-bound command atomically advance disabled durable intent by exactly one revision. Its receipt grants no capability and is not readiness: the Agent must restart through the complete readiness/status product before availability, presentation, or network ingress.

The [disabled-Agent bootstrap transport](docs/evidence/2026-08-22-disabled-agent-bootstrap-transport.md) maps that contract to four exact closed XPC envelopes and strict 4,096-byte canonical codecs. One generation-bound transaction admits only an ordered offer read followed by an enable command embedding that exact offer; overlap, substitution, malformed receipts, timeout, cancellation, peer replacement, and late callbacks fail closed. The [production binding](docs/evidence/2026-08-22-agent-bootstrap-production-binding.md) injects the durable authority only for canonical disabled startup, retains the exact preparation-owned store, sends success only after exact durable read-back, and latches a clean launchd restart after acknowledged or unacknowledgeable durable enablement. The [foreground setup composition](docs/evidence/2026-08-22-foreground-remote-access-setup.md) adds the exact same-team menu client, serialized Agent-only registration acquisition, fixed explicit-consent UI, owned-registration rollback, preexisting/post-send ambiguity retention, receipt-gated visible-menu convergence, and fresh dashboard routing. Signed two-process disabled-to-ready acceptance remains open.

The [Interactive lease local-XPC transport](docs/evidence/2026-08-22-interactive-lease-local-xpc-transport.md) now carries strict canonical install, renewal, and revoke operations between the exact authenticated-and-ready Agent/menu generation. The subsequent [initial Desktop runtime transport](docs/evidence/2026-08-22-initial-desktop-runtime-transport.md) adds preparation as the fourth operation: the menu resolves the admission-published opaque display through the same process-local mapping and returns one bounded descriptor without starting capture or exposing physical identity. Install carries that complete descriptor, binds it exactly to the lease during construction and decoding, rechecks Desktop kind and monotonic validity before any platform effect, and hands the full command to capture. One cross-family transaction, asymmetric bounded deadlines, exact receipt correlation, and peer-wide failure on ambiguity preserve fail-closed ownership; menu connection loss invokes local unacknowledged runtime invalidation. The later [permanent Agent runtime binding](docs/evidence/2026-08-22-permanent-agent-interactive-runtime-binding.md) installs one stable fail-closed dispatcher authority before XPC, binds only the exact authenticated-ready generation to its concrete owner and renewal scheduler through the cached opaque endpoint, rechecks its generation plus private token on the server queue, and serializes menu loss or product finish before replacement. This path carries no media or input; concrete menu platform adapters remain next.

The [Interactive runtime composition boundary](docs/evidence/2026-08-22-interactive-runtime-composition-boundary.md) now binds that transport to the existing single-owner menu runtime through a cleanup-failure latch and adds an Agent owner that double-revalidates durable-plus-visible admission around Desktop preparation, transfers channel credentials only after an exact install receipt, renews only the exact current lease after another final admission read, and requires correlated four-effect revocation or compensation. The [opaque-display and lease-scheduling checkpoint](docs/evidence/2026-08-22-opaque-display-and-lease-scheduling.md) makes the permanent menu own a random UUID-to-current-main-display mapping without exposing the physical identifier, refuses silent redirection after display loss, publishes the opaque selection in revision 1, and schedules each Agent renewal from the exact acknowledged replacement without ambiguity retries. The [persistent Control indicator and expiry checkpoint](docs/evidence/2026-08-22-persistent-control-indicator-and-expiry.md) now makes the permanent target construct that runtime, keeps a named red menu-bar/banner indicator visible through uncertain teardown, supplies a local Stop path, and independently expires exact leases with stale-timer and early-wake fencing. The [host Interactive role-ingress checkpoint](docs/evidence/2026-08-22-host-interactive-role-ingress.md) now authenticates strict input/media connections on the shared TLS listener without transferring credential bytes and retains only an exact same-session role pair. The later [host role-data-plane checkpoint](docs/evidence/2026-08-22-host-interactive-role-data-plane.md) transfers that concrete pair to one generation- and runtime-fenced Agent owner, bounds exact input decoding, applies one-record-at-a-time media backpressure, and tears both roles down on either failure. Authenticated local-XPC input/media routing plus concrete capture, frame, and input adapters remain closed before Control can activate.

The [visible Interactive admission checkpoint](docs/evidence/2026-08-22-visible-interactive-admission-contract.md) maps the strict canonical menu-generation/revision/optional opaque-display publication through an independent authenticated local-XPC request/ack transaction into one stable Agent authority. The permanent Agent inserts that same authority into its durable-plus-visible admission reader and presentation-capable XPC profile, while the menu publishes revision 1 only after readiness acknowledgement and before status. Generation loss withdraws it fail-closed. That checkpoint initially published no display; the later opaque-display checkpoint now supplies the random menu-owned selection without itself granting Control.

The [adaptive surface runtime binding](docs/evidence/2026-08-23-adaptive-surface-runtime-binding.md) now closes the construction path from authenticated primary target inventory and selection through the permanent Agent, generation-fenced local XPC family, menu-owned opaque ScreenCaptureKit catalog, two-phase source preparation/runtime-fence commit/activation, continuous media sequencing, clean-frame acknowledgement, and exact replacement-lease expiry. Desktop, application, window, and Desktop escape-hatch transitions are concrete; physical identifiers, bundle/PID/window IDs, titles, and capture objects remain in the menu process. This is compile- and fault-tested construction, not signed live-pixel, posted-input, physical-iPhone, TCC, lock, latency, or external-beta evidence.

The [Agent bootstrap durable authority](docs/evidence/2026-08-22-agent-bootstrap-durable-authority.md) owns the revision-zero-or-disabled offer and exact successor enable commit over the existing cross-process-locked intent store. It requires exact post-write read-back, recovers only an exact post-rename commit, replays only the exact command without a second write, and fences every storage suspension by monotonic peer generation and operation ID. XPC injection, process restart, setup registration, the menu transaction, and receipt-gated dashboard construction are now bound; signed launchd execution and reciprocal readiness/status remain the next gate.

The current hardened gate covers 1,069 repository files and includes 4 native-appearance boundary policy self-tests over 348 Swift source files.

Supply-chain coverage now also includes 26 exact-candidate artifact-SBOM fixtures, 18 artifact-SBOM/release-graph integration cases (including iOS and combined targets), 45 complete signed-code construction-discovery graph fixtures, 17 per-executable signed-code construction-correlation fixtures, 24 Mac packaging-equivalence fixtures, 8 mounted-tree/xattr-policy cases, 5 packaging release-integration cases, 3 partial-attach/recovery cases, 6 fail-closed recovery-refusal cases, 2 interrupted recovery-record update cases, and one concurrent public-path substitution case. The separately authorized packaging lane has 2 full APFS/UDZO reinspection cases; signed-code platform acceptance remains deliberately gated.

The repository currently validates 73 authoritative protocol/product fixtures, 14 repository-material fixtures, 24 dependency-policy fixtures, 35 update-policy fixtures, 12 privacy-manifest fixtures, 10 source-SBOM fixtures, 17 release-evidence fixtures, and 1,530 MacCompanionKit Swift tests plus 8 platform-probe tests, iOS Simulator client-platform and client-UI compiles, a macOS local-authority UI compile, plus three no-prompt/no-network platform probes through the same public unsigned CI entry point. Coverage includes canonical and bounded wire construction, cryptographic vectors, strict canonical X.509 profile parsing/self-signature/current-validity verification, compile-tested host Secure Enclave/Keychain custody with exact bounded tags and in-memory Security.framework certificate-to-`SecIdentity` composition, strict host TLS 1.3/no-resumption local-identity parameter construction, authorization/grant/revocation fencing, a [bundle-independent durable local-device revoke path](docs/evidence/2026-08-21-local-device-revocation-convergence.md), crash recovery, real security and detailed-audit SQLite pager-full atomic rollback plus WAL checkpoint/integrity/capacity recovery, three-boundary torn-WAL whole-transaction recovery, plus owner-controlled canonical no-follow 0600 database/sidecar paths, QR-secret proof and SAS convergence, Agent-owned one-visible pairing-QR creation and dismissal with exact replay, expiry, tombstone, compensation, and commit-race fencing, explicit scan acceptance, untrusted-to-pinned fingerprint presentation, verified-only SAS display, durable-before-paired client publication, distinct opaque client session/approval key custody with exact protection profiles, compile-tested Security/Secure Enclave construction and DER-to-raw signing composition, key-presence revalidation and atomic paired-host publication, strict canonical client-record storage, bounded fsync-and-rename multi-host persistence with injected fault convergence, conflict-preserving prepared-key restart reconciliation, transcript/key-fingerprint-bound locally named pairing approval with atomic device/name persistence, exact already-authorized local review delivery and withdrawal with a revision-fenced Mac SAS/name owner and compile-checked sheet, locally named exact-effect grant review and one-session Interactive warning/stop presentation, exact local grant-decision and completed-teardown IPC with strict decoding and receipt correlation, registry-generation/full-descriptor/effect-bound Agent review consumption, one immutable validated registry/provider publication shared by local grant review, discovery, and bounded-operation admission/execution, a fail-closed Agent bootstrap that loads providers and atomically reconciles restart state before fixing authentication, status, self-audit, store-bound required-audit Interactive, operation, and discovery dependencies, a [first-party native MVP provider composition](docs/evidence/2026-08-21-native-mvp-agent-provider-composition.md) that binds the reviewed mute descriptor and exact inert Core Audio provider into that startup graph, exact-provider post-start removal and lifecycle-fenced primary/Interactive teardown, post-commit privacy-limited registry audit with degraded-health signaling, atomic SQLite grant expansion with stale-fence rollback, concrete pending/active dispatcher shutdown, four-effect menu-runtime teardown proof, Agent-issued surface-replacement leases with exact runtime preparation and clean-media acknowledgement receipts, a distinct clean-media-gated initial Desktop exchange, a closed primary-channel target-inventory and surface select/acknowledge exchange with relative client-local validity, consumed opaque tokens, and exact app/window filter construction, and fail-closed client activation/replacement coordinators, client-pin versus host-listener identity separation, host and client primary-session correlation/replay/deadlines, QR-pairing route racing and serialized framing with one immutable pin and deadline, immutable-pin reconnect racing with late-winner cleanup and authenticated command ownership, single-owner foreground/reachability/candidate/backoff reconnect composition, one-shot exact-connection client TLS verification contexts with a strict `SecTrust` leaf evaluator, a compile-checked concrete client route attempter with injected readiness/authentication latch faults, separate host/client verified-ready Network handoffs, exact-first-frame auth/pairing classification without over-read, a silent-completion pairing pump, proof-gated primary replacement, and a sealed Agent listener service with generation-fenced independent primary/pairing ownership and a [content-free root-status binding](docs/evidence/2026-08-20-agent-listener-status-binding.md), a [coherent content-free Agent status authority](docs/evidence/2026-08-20-local-status-authority-construction.md) with unique read sequences and count-only inventory/security adapters, a [source-scoped route authority](docs/evidence/2026-08-20-local-route-monitor-authority.md), an [authenticated configured-route projection](docs/evidence/2026-08-20-authenticated-route-protocol.md), and a [durable exact-winner client route catalog and heartbeat pump](docs/evidence/2026-08-20-client-configured-route-construction.md), a [revision-bound reconnect owner, durable route-update service, bootstrap authority, lifecycle composition, and stateless package UI](docs/evidence/2026-08-20-client-configured-reconnect-composition.md), plus an [already-authorized local-status reader](docs/evidence/2026-08-20-local-status-read-service.md) issued only by a [fail-closed Agent local-service root](docs/evidence/2026-08-20-agent-local-service-root.md), byte-independent deadlines, and injected readiness/binding/replacement/send/receive/frame/teardown faults, paired-identity publication, capability pagination and partial-catalog discard, safe operation results and failures, provider deadlines/cancellation, native mute read-back behavior, route/freshness/lifecycle policy, sanitized local IPC, correlated local-only device naming, self-scoped bounded audit pagination and privacy-preserving iOS/Mac history projection with explicit gaps, client identity/route/control/lock/surface presentation, and Interactive Control approval, authenticated primary routing and teardown, atomic host bootstrap dispatch, stable SQLite/menu-app admission joins, OS-backed session material, mutually authenticated role channels, exact-read secondary handshake framing and winning-endpoint retention, bounded execution leases, typed install/renew/revoke/surface-transition receipts, serialized visible-menu runtime effects, input suppression across surface replacement until exact clean-media acknowledgement, lease-fenced local input posting without a revocation race, strict AVCC configuration/NAL/keyframe validation, gap-free digest-bound media enqueue with fail-closed backpressure, bounded no-eviction media retention and purge-before-render-blanking, complete-frame ScreenCaptureKit normalization and bounded single-owner event handoff, latency-first VideoToolbox encoding that awaits runtime publication, sequence-preserving configuration/access-unit/discontinuity/end record production, a [bundle-independent client mapper](docs/evidence/2026-08-20-client-input-mapping-construction.md) with half-open render geometry, direct-touch/trackpad modes, balanced drags, reset-on-mode-change, bounded scroll, closed keyboard actions, and an iOS-Simulator-checked main-actor UIKit seam, a [generation-fenced client decoder](docs/evidence/2026-08-20-client-decoder-construction.md) with shared AVCC validation, clean-keyframe reset gates, stale-callback rejection, latest-one frame state, and compile-checked VideoToolbox construction, plus a [bounded client render handoff](docs/evidence/2026-08-20-client-render-handoff-construction.md) with generation/sequence ordering, one scheduled main-actor drain, and compile-checked UIKit display-layer blanking, a [compile-checked SwiftUI-to-UIKit live-control surface](docs/evidence/2026-08-20-client-live-surface-construction.md) with aspect-fit gesture geometry and teardown decoder blanking, a [package-level iOS pairing and host UI](docs/evidence/2026-08-20-client-ui-construction.md) that keeps Remote Control optional and preserves unverified/verified identity, saving, connection, view/control/lock/surface presentation, and Remote-Control-optional distinctions through closed value-driven intents and adds a Desktop/app/numbered-window picker without window titles; Mac presentation keeps durable grant expansion, phone approval, one-session warning/stop state distinct while preserving every effect fact, and its local stop closes only after exact Agent authority/runtime completion.

The package-level UI evidence now includes the [iOS pairing and host surfaces](docs/evidence/2026-08-20-client-ui-construction.md), [one-shot iOS QR scanner and Mac QR renderer](docs/evidence/2026-08-20-pairing-qr-io-construction.md), [Agent-owned local pairing-session composition](docs/evidence/2026-08-20-local-pairing-session-composition.md), [listener-owned pairing availability](docs/evidence/2026-08-20-listener-pairing-context-composition.md), [exact listener-pairing factory](docs/evidence/2026-08-20-listener-pairing-factory.md), [Mac pairing request reducer](docs/evidence/2026-08-20-mac-pairing-presentation-reducer.md), [Mac pairing sheet](docs/evidence/2026-08-20-mac-pairing-sheet-construction.md), [Mac pairing application owner](docs/evidence/2026-08-20-mac-pairing-application-owner.md), [client proof-signing reentrancy fence](docs/evidence/2026-08-20-client-pairing-signing-reentrancy.md), [client pairing application owner](docs/evidence/2026-08-20-client-pairing-application-owner.md), [no-relay client pairing network construction](docs/evidence/2026-08-20-client-pairing-network-construction.md), [local SAS/name pairing approval](docs/evidence/2026-08-20-local-pairing-approval-construction.md), [host pairing wire owner](docs/evidence/2026-08-20-host-pairing-wire-owner.md), [role-safe host listener ingress and pairing pump](docs/evidence/2026-08-20-host-listener-ingress-construction.md), [already-authorized local pairing review delivery and SAS/name sheet](docs/evidence/2026-08-20-local-pairing-review-delivery.md), [sealed pairing product composition](docs/evidence/2026-08-20-pairing-product-composition.md), [sealed Interactive product composition](docs/evidence/2026-08-20-interactive-product-composition.md), [signature-bound initial runtime preparation](docs/evidence/2026-08-20-initial-runtime-preparation.md), [root-bound Observe status](docs/evidence/2026-08-20-root-bound-host-status.md), [durable host-identity release root](docs/evidence/2026-08-20-durable-host-identity-root.md), [recoverable host-identity startup](docs/evidence/2026-08-20-host-identity-startup-coordinator.md), [confirmed host-identity recovery](docs/evidence/2026-08-20-host-identity-confirmed-recovery.md), [local recovery confirmation composition](docs/evidence/2026-08-21-local-host-identity-recovery-composition.md), [unified Agent network startup](docs/evidence/2026-08-20-agent-network-product-startup.md), [client reconnect security composition](docs/evidence/2026-08-20-client-reconnect-security-composition.md), [configured-route Network product](docs/evidence/2026-08-20-client-configured-route-network-product.md), [sealed client pairing product composition](docs/evidence/2026-08-20-client-pairing-product-composition.md), [iOS live-control bridge](docs/evidence/2026-08-20-client-live-surface-construction.md), [continuous initial-to-steady media/input handoff](docs/evidence/2026-08-21-client-continuous-media-handoff.md), [application-global lifecycle binding](docs/evidence/2026-08-20-client-application-lifecycle-binding.md), [scheduling-only coarse reachability source](docs/evidence/2026-08-20-client-coarse-reachability-construction.md), [single composed network application owner](docs/evidence/2026-08-20-client-network-application-owner-construction.md), and [Mac local-authority surfaces](docs/evidence/2026-08-20-mac-local-authority-ui-construction.md). The client package views, synthetic lifecycle, and first-party live-Control screen are also [rendered and accessibility-traversed in an unsigned, no-network Simulator harness](docs/evidence/2026-08-20-client-ui-simulator-harness.md). This is not signed, physical-device, live-network, authenticated-XPC, or release evidence; the Mac UI remains compile-checked only.

The [selected-primary application workspace](docs/evidence/2026-08-21-client-primary-workspace.md)
now binds the real configured-route product to one revision-fenced state owner
and a first-party iOS Observe/Act/Control workspace. A stale or replaced
connection cannot republish status, actions, or teardown over the current
connection, and entering Remote Control remains a separate intent rather than
implicit authorization.

The [permanent iOS application target](docs/evidence/2026-08-22-permanent-ios-application-target.md)
now fixes the iOS 26 iPhone/iPad identity, exact Local Network/Bonjour/camera
declarations, bundled privacy manifest, and a transport-inert protected restart
bootstrap. It creates one stable non-backed-up installation identity and
reports paired only after one exact saved host, its protected key references,
and its sole route catalog revalidate. Signed launch, permissions, pairing, and
live network composition remain separate gates.

The [permanent iOS release composition](docs/evidence/2026-08-22-permanent-ios-release-composition.md)
now advances that target beyond the inert shell: the package-owned QR/SAS
pairing flow, explicit first-route provenance, configured no-relay reconnect,
and first-party Observe, Approved Actions, and separately authorized Remote
Control workspace are composed behind one root-owned application service. A
crash after durable pairing but before route publication resumes route setup
without dialing. Physical pairing, signed-device prompts, live Observe/Act,
and screen/input evidence remain the next gates.

The [selected-primary Control session owner](docs/evidence/2026-08-21-client-primary-control-session.md)
now binds an explicit Desktop request, fresh Control-specific device presence,
correlated approval, accepted role offers, denial/retry, and teardown to the
exact selected primary. Accepted means only that secondary channels may start;
the workspace cannot claim live viewing or input before their independent
authentication and initial clean-media acknowledgement complete.

The [secondary role handshake pump](docs/evidence/2026-08-21-client-secondary-role-handshake.md)
now frames each input/media authentication message with exact bounded reads,
preserves immediately following role bytes, enforces the fixed credential
deadline, and carries only the exact winning primary endpoint into private
role composition. It still does not claim a live socket, rendered frame, or
posted input event.

The [concrete secondary role network owner](docs/evidence/2026-08-21-client-secondary-role-network.md)
now opens both pinned-TLS sockets on only that exact endpoint, consumes each
live connection's evidence once, rechecks the selected primary after both
mutual proofs, and publishes no partial pair. Live host media/input evidence
and automatic product activation remain separate gates.

The [configured-product role binding](docs/evidence/2026-08-21-client-role-product-binding.md)
now starts that pair only after the exact accepted Control value is retained,
and cancels it on retry, rejection, failure, or primary loss. Its readiness
state proves only authenticated role sockets. Exact primary/session-fenced
progress now projects channel connection, channel readiness, initial verified
frame preparation, active input, and stage-specific failure into the workspace;
skipped or stale progress cannot claim a live surface, and input remains closed
until clean Desktop media is decoded, rendered, and acknowledged.

The [remote Control stop exchange](docs/evidence/2026-08-21-client-remote-control-stop.md)
now retires client input/media authority as soon as the exact end request is
enqueued, clears host admission before teardown, and returns success only after
input release, capture stop, media purge, and output blanking complete. Early,
uncorrelated, stale-session, and duplicate stop events cannot claim completion.

The [first-party live Control screen](docs/evidence/2026-08-21-client-primary-live-control-screen.md)
now keeps authority request separate from presentation, owns the verified-frame
UIKit product across navigation, offers touch and trackpad modes, and routes its
prominent Stop action through that exact end exchange. Observe and Approved
Actions remain available without entering or keeping the live screen visible.
Its manual stateless iOS keyboard forwards bounded text/delete actions without
claiming focus-aware Smart Input or retaining a remote field value.

The later [adaptive client surface-switching checkpoint](docs/evidence/2026-08-23-adaptive-client-surface-switching.md)
adds a privacy-limited **View** picker for Desktop, Application Focus, and
Window Focus. It preserves one Control authority and one media/input pipeline:
input reset precedes selection, the replacement clean frame must be visibly
rendered, and input resumes only after the exact host acknowledgement. It does
not claim semantic Smart Input.

The subsequent [manual visual Smart Zoom fallback](docs/evidence/2026-08-23-manual-visual-smart-zoom.md)
adds an explicit local pinch/pan/Fit mode to every live pixel surface. Remote
gestures are reset and suppressed while the user adjusts it; direct points and
trackpad deltas are inverse-mapped when interaction resumes. It transmits no
new metadata and creates no new authority.

The [ordered focus-event lane](docs/evidence/2026-08-23-ordered-focus-event-lane.md)
now freezes and implements that fixture-first client boundary. One closed,
privacy-limited host event kind has independent replay and sequence state,
cannot satisfy command requests, and offers only a short-lived one-use target
for the proven replacement-surface exchange. The host Accessibility producer
and automatic iOS application remain subsequent work; manual zoom stays the
fallback.

The subsequent [host focus-event authority](docs/evidence/2026-08-23-host-focus-event-authority.md)
binds that event's short-lived target to one exact Agent-side surface fence and
focus projection, revokes superseded targets, and consumes the winner once
before the existing runtime transition. Accessibility observation, local-XPC
candidate delivery, live crop construction, and primary-stream emission remain
the next construction steps.

The following [host event transport and Accessibility projection checkpoint](docs/evidence/2026-08-23-host-event-transport-and-ax-projection.md)
serializes that event with authenticated primary replies and adds a
content-minimizing macOS focus reader. The menu process reduces Accessibility
state immediately to a closed category, editable/secure flags, and conservative
normalized geometry; it never reads field values, selected text, labels,
titles, descriptions, or identifiers. Authenticated local candidate delivery,
live focus observation, capture cropping, and automatic client application are
still subsequent work.

The [authenticated focus-candidate local-XPC checkpoint](docs/evidence/2026-08-23-authenticated-focus-candidate-xpc.md)
adds the tenth exact operation to that generation-fenced family. The reply
echoes the complete current surface fence and contains only the sanitized
candidate. A changed focus inside an existing Focused Region releases input
once and keeps it closed until the ordinary replacement clean-frame
acknowledgement; raw Accessibility and platform identifiers never cross the
process boundary. Permanent Agent observation/event publication, live focus
crop construction, and automatic iOS application remain next.

The [permanent focus-event observer checkpoint](docs/evidence/2026-08-23-permanent-focus-event-observer.md)
now binds that candidate to the production Agent lifecycle and the exact
authenticated primary connection that authorized the Interactive session. It
does not sample focus for a missing or replacement primary, emits at most one
event per current surface fence, and revokes plus closes on a send race. Live
focused-region capture cropping and automatic iOS Smart Zoom application are
the next construction lanes.

The [live Focused Region Smart Zoom checkpoint](docs/evidence/2026-08-23-live-focused-region-smart-zoom.md)
now closes those two construction lanes. The menu revalidates the exact
privacy-reduced focus, creates a bounded display-logical ScreenCaptureKit crop,
and retains separate global bounds for input mapping. The selected iOS product
applies the admitted event through the same reset/select/clean-render/ack path,
buffers the acknowledgement-to-promotion race, updates its live descriptor and
dimensions, and exposes an automatic-follow policy that every manual surface
choice turns off. Stable global focus identity prevents recursive re-cropping
after the coordinate space changes. Signed TCC execution, real crop pixels,
physical-iPhone behavior and latency, multi-display edges, and lock behavior
remain evidence gates.

The [signed physical launch baseline](docs/evidence/2026-08-23-signed-physical-launch-baseline.md)
now proves invocation-only Apple Development signing for both permanent apps,
strict Mac containing-app/embedded-Agent verification, physical iPhone
installation and surviving process launch, and a live signed Mac menu-bar
process without writing signing authority into the repository. The iOS build
uses a wildcard development profile, not an explicit distribution identity.
Agent registration, privacy consent, pairing, transport, pixels, and input were
not exercised; explicit Remote Access enablement remains the next confirmed
persistent-access action.

The [permanent Mac containing-app target](docs/evidence/2026-08-21-permanent-mac-containing-app-target.md)
now embeds the separately signed, deliberately inert [permanent Agent
target](docs/evidence/2026-08-21-permanent-embedded-mac-agent-target.md), its
exact LaunchAgent plist, and the bundle-owner-bound privacy resource. Xcode 27
beta proves both reverse-DNS Developer ID identities, universal construction,
and hardened runtime without tracking a team, credential, or managed
entitlement. Authenticated local IPC, lifecycle registration, iOS, CLI,
Keychain-group, and TCC evidence remain gated in the execution ledger.

The [permanent `SMAppService` identity composition](docs/evidence/2026-08-21-permanent-smappservice-identity-composition.md)
also retains the exact Agent-plist and main-app service objects through the
tested convergence/executor chain. Launch proof confirms that construction
does not register or start the Agent; explicit durable enablement and
authenticated readiness remain separate work.

The [bundle-independent diagnostic CLI v0.1 contract](spec/local-cli/v0/README.md)
now accepts only content-free status, sanitized diagnostics export, help, and
version. Its pure package target owns exact parsing, authenticated local-method
planning, fixed exit/error mapping, and revalidated text/JSON rendering. It is
not an executable and cannot contact the Agent; the permanent
`maccompanionctl` target still waits for final signing identity and its own
reciprocal same-team exact-identifier XPC admission proof. It is not admitted
through the already-proven menu-app role.

Local validation with the currently available beta toolchain:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
MACCOMPANION_DISABLE_SWIFTPM_SANDBOX=1 \
bash scripts/validate.sh
```
