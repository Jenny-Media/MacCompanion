# Mac Companion Execution and Blocker Ledger

Status date: 2026-08-23

This is the living execution authority for the staged plan. A blocker applies only to work that names it as a dependency. Work in every other safe lane continues. Evidence links point to repository artifacts or reproducible commands; secrets and Apple-account records remain outside the repository.

## Status vocabulary

- `active`: work can proceed now.
- `ready`: prerequisites are satisfied and work is queued.
- `blocked-external`: an external approval, account value, machine, or user decision is required.
- `blocked-design`: a normative decision must be reconciled before implementation.
- `passed`: exit evidence is recorded.
- `no-go`: evidence rejects the capability for the supported product.
- `deferred`: the capability remains optional and has a recorded reason and re-entry condition.

## Resolved execution decisions

- Official bundle and code-signing identifiers use the Jenny Media-controlled `media.jenny` prefix: `media.jenny.maccompanion` for the Mac containing app, `media.jenny.maccompanion.agent` for the standalone embedded Agent, `media.jenny.maccompanion.ios` for the iOS/iPadOS client, and role-suffixed identifiers under `media.jenny.maccompanion.xpc` if XPC services are retained. The Team ID is confirmed privately and the explicit Mac containing-app App ID `media.jenny.maccompanion` is registered. The Agent's distinct code-signing identifier is build-proven without a portal App ID for its current standalone-tool form; the iOS and any retained XPC App IDs are not yet registered.
- The release floor remains macOS 26.0 and iOS/iPadOS 26.0 with stable Xcode 26.6 and Swift 6.3. Installed Xcode 27 beta is permitted for development, compatibility, signing setup, device work, and currently supported TestFlight uploads, but stable Xcode 26.6 remains required for final signed release evidence.
- Development signing may use identities installed on this development Mac. Developer ID, App Store distribution, notarization, Sparkle, and promotion credentials remain in a separately controlled release environment. The [permanent containing-app build](evidence/2026-08-21-permanent-mac-containing-app-target.md), [embedded Agent build](evidence/2026-08-21-permanent-embedded-mac-agent-target.md), and [current signing revalidation](evidence/2026-08-22-signing-identity-revalidation.md) prove valid local Apple Development and Developer ID Application identities plus the exact distinct code-signing identifiers. The earlier zero-identity result was a restricted-sandbox Keychain-visibility artifact; no replacement certificate was required. Final Developer ID custody and promotion remain release-environment gates.
- Execution prefers the shortest signed, physical, runnable product slice over more construction-only infrastructure whenever that slice is unblocked: permanent targets, LAN pairing and reconnection, Observe, `setAudioMuted`, then Desktop video plus mouse and keyboard. App Focus, Window Focus, Smart Zoom, and interaction adaptation remain Stage 2 exit requirements but do not delay the first Desktop Control build.
- First pairing is foreground and same-LAN. A paired device may later reconnect only over ordinary private LAN routes or explicitly saved user-managed private endpoints such as Tailscale MagicDNS, private DNS, IPv4, or IPv6. Route classification never grants authority and Mac Companion does not infer Tailscale from interfaces, DNS, or installed processes.
- Through Stage 3, “full control” means the separately granted live pixel stream, mouse and keyboard input, plus independently granted bounded capabilities. Shell, arbitrary SSH commands, general files, clipboard, audio, automation, provider execution, and future capabilities remain outside the MVP and never inherit Control authorization.
- The intended source license is Apache-2.0 with a separate Mac Companion/Jenny Media trademark policy, both subject to legal review. GitHub private vulnerability reporting is the initial security-reporting channel; a company security address may replace or supplement it later. Because the remote repository is already public, no further push or contribution intake occurs until license/trademark/security publication, full-history review, and provider-side repository protections are resolved.
- The completion boundary is a signed, installable external Stage 3 beta with market-MVP evidence. Stages 4–7 may close with evidence-backed `passed`, `no-go`, or `deferred` decisions; they are not required to ship speculative breadth.

## Current lanes

| Lane | Stage | Status | Current evidence | Blocker or next proof | Independent work that continues |
| --- | --- | --- | --- | --- | --- |
| Design baseline | 0A | passed | Reconciled product documents, ledger, ADR, threat model, permission matrix, three-agent audit, baseline commit `432354c`, and local implementation checkpoint `c92ce7b` | Keep implementation evidence synchronized with the resolved execution decisions | All implementation lanes use this authority |
| Protocol trust kernel | 0B | passed | Normative v0.1 mini-RFC; 64 indexed protocol, Interactive Control, local-IPC, model, binary, and crypto fixtures; pure `CompanionDomain`, `CompanionWire`, and `CompanionSecurity`; restricted RFC 8785 Unicode/safe-integer canonicalization, closed capability schemas/registry, exact operation-approval signatures, strict bounded canonical host-certificate inspection, closed operation and paged capability-discovery messages, programmatic frame-size enforcement, and a closed safe error body; fixture-backed domain/wire/security tests; public unsigned CI workflow | Remote CI result is pending the next published branch; floating-point schemas remain denied unless a later profile passes complete ECMAScript number vectors | IPC interfaces, status sampling, and disposable platform probes |
| Public repository readiness | 0A | active | The [public CI supply-chain boundary](evidence/2026-08-20-public-ci-supply-chain-hardening.md) grants read-only contents access, pins checkout v6.1.0 to its full verified commit, disables persisted credentials, and rejects movable remote-action tags and container tags before compilation; the [repository material boundary](evidence/2026-08-20-repository-material-boundary.md) scans every publishable file and reachable historical blob/path and rejects high-confidence credential, signing, private-database, symlink-escape, and oversize forms through 14 fixtures. The [dependency policy](evidence/2026-08-20-swift-dependency-policy.md) keeps all four Swift manifests and three repository edges local while its [v1 exact Sparkle admission](evidence/2026-08-23-exact-sparkle-dependency-admission.md) permits only Sparkle 2.9.6 in the Mac containing app, bound to its full revision, upstream digests, shared lockfile, privacy settings, consumer, and archive sanitizer. Twelve manifest and twelve Xcode dependency fixtures reject every other remote package, binary target, executable plugin, consumer, or topology. A [2026-08-23 live audit](evidence/2026-08-23-public-repository-live-audit.md) confirms the remote is public, detects no license, has no `main` protection or ruleset, and has secret scanning/push protection/validity/non-provider scanning plus Dependabot security updates disabled while the audited local branch was 74 commits ahead and unpushed | Complete legal review; publish mutually consistent license, trademark, contribution, and security policies; enable and verify private reporting and provider protections; re-scan the exact local range; then obtain exact-head confirmation before any push. Any further production dependency needs its own necessity, provenance, license, privacy, signing, and replacement review | Unsigned fixtures, packages, experiments, documentation, and CI policy continue locally without pushing |
| Distribution evidence | 0A/3 | active | The [release evidence v0.1 profile, validator, and unsigned generator](evidence/2026-08-20-release-evidence-manifest-construction.md) separate unsigned construction, signed candidate, and promotion-ready claims; 17 indexed fixtures prove closed schemas, compatibility/target binding, artifact/executable/notary/SBOM requirements, physical-scenario and human-approval gates, secret exclusion, placeholder rejection, and nonzero invalid CLI behavior; every evidence reference is size/hash bound, file verification rejects mutation and symlink/path escape, and generated manifests use atomic no-clobber publication while retaining exact source/toolchain facts without credentials; the [deterministic SPDX 2.3 source dependency SBOM](evidence/2026-08-20-source-dependency-sbom.md) is live-policy-bound and proven by 10 fixtures plus byte-identical generation; the [Sparkle nested Developer ID packaging checkpoint](evidence/2026-08-23-sparkle-nested-developer-id-packaging.md) adds an 11-case no-overwrite packager, corrects an outer-`codesign`-masked ad-hoc helper defect, verifies five universal Developer ID subjects, signs the APFS/UDZO DMG, and proves exact three-container equivalence on Xcode 27 beta while retaining explicit false notarization, stapling, Sparkle-signature, and promotion claims | Real signed candidates require stable Xcode/signing custody, two accepted notarization phases, post-staple correlation, artifact-complete SBOM and reviewed licenses, physical matrices, Sparkle/App Store records, and human approval | Local release construction can continue without uploading or publishing; notarization remains separately authorization-gated |
| Exact-candidate artifact SBOM | 0A/3 | active | The [v0.1 profile and construction](evidence/2026-08-21-exact-candidate-artifact-sbom.md) stream and inventory executable-bearing ZIPs, emit reciprocal `filesAnalyzed: true` SPDX with SHA-1/SHA-256 and package verification codes, enforce byte-canonical evidence, publish a mode-0600 no-overwrite directory, and bind archive/release/source/target/executable facts; 26 adversarial fixtures and 18 end-to-end release/graph integrations cover deterministic generation, unsafe/polyglot archives, valid and corrupt data descriptors, standard and cyclic symlinks, source-SBOM substitution, metadata substitution, executable path/mode, Sparkle divergence, post-generation mutation, graph omission/symlink/nested-code omission, duplicate executable subjects, and iOS/combined target binding | Real signed archives, an independently pinned SPDX validator, stable release toolchain evidence, reviewed licenses, and platform-verified complete signed-code graph remain required before a signed-candidate claim | The generator and verifier are bundle-independent and ready for release-job integration |
| Signed-code construction discovery, correlation, and policy | 0A/3 | active | The per-executable [construction correlation](evidence/2026-08-21-signed-code-construction-correlation.md), complete [discovery graph](evidence/2026-08-21-signed-code-construction-discovery.md), independently pinned [signing policy](evidence/2026-08-21-signing-policy-construction.md), [fixed-tool runner](evidence/2026-08-22-platform-signing-fixed-tool-runner.md), exact [subject reconstruction](evidence/2026-08-22-platform-signing-subject-reconstruction.md), and [whole-subject verification executor](evidence/2026-08-22-platform-codesign-verification-execution.md) bind exact artifacts, Mach-O objects, architecture slices, tools, raw streams, and policy. The [per-architecture construction](evidence/2026-08-22-per-architecture-signature-inspection-construction.md) independently parses embedded CodeDirectory, designated requirement, CMS, runtime, and duplicate-safe XML entitlements. The [protected architecture executor](evidence/2026-08-22-per-architecture-signature-inspection-execution.md) now requires freshly revalidated whole-subject success, rehashes the complete candidate around each fixed call, retains only a bounded contiguous private certificate chain, and composes embedded, Apple-display, certificate, entitlement, and policy facts. The [semantic DER-entitlement equality checkpoint](evidence/2026-08-22-der-entitlement-semantic-equality.md) independently decodes the measured CoreEntitlements v1 grammar, requires exact XML/DER tagged-policy equality, and retains both blob digests while rejecting DER-only signatures. The [outer codesign checkpoint](evidence/2026-08-22-outer-codesign-verification-construction.md) adds one exact immutable Mac-only `--deep` consistency plan and executor with a closed Apple-tool-measured grammar. The [outer prerequisite correlation](evidence/2026-08-22-outer-codesign-prerequisite-correlation.md) now requires every exact whole-object and architecture record to pass fresh subject, raw-output, certificate, embedded-signature, display, entitlement, and policy reinspection before the outer invocation and repeats the same complete reinspection afterward. The [canonical construction record](evidence/2026-08-22-canonical-platform-signing-construction-record.md) recomposes those facts against exact canonical release/SBOM/graph/policy references, the fixed environment and tool, reconstructed subjects, and target-specific unresolved gates under the 8 MiB profile. The [Mac app Gatekeeper/stapler checkpoint](evidence/2026-08-22-mac-gatekeeper-stapler-construction.md) adds exact `spctl` and directly pinned Xcode `stapler validate` plans only after the correlated signing result, rehashes around both, and repeats the prerequisite afterward. The [two-phase notarization checkpoint](evidence/2026-08-22-two-phase-notarization-correlation-construction.md) replaces the invalid one-submission release assumption with distinct transient-app-ZIP and final-content-DMG acceptances, exact upload hash/name/UUID/raw-log correlation, zero issues, nonempty tickets, and temporal ordering. Its adversarial corpus additionally rejects upload substitution, warnings, unknown/duplicate keys, a single release submission, UUID reuse, reversed phases, removed gates, and attempted acceptance promotion | Add protected `notarytool` execution and both post-staple byte-transition correlations, then final app/DMG assessment; run the real final candidates; add the exported IPA artifact and prove stable-Xcode/final-identity/notarization/physical/promotion evidence | All accepted notary results are synthetic construction inputs; no Mac Companion upload or staple occurred, every canonical record remains `platformAcceptanceEligible: false`, and valid construction still emits `signedCodePlatformVerificationRequired` |

Latest signing-distribution checkpoint, superseding the protected-execution portion of the row above: the [protected notarytool executor](evidence/2026-08-22-protected-notarytool-execution-construction.md) now pins each exact upload into a private immutable copy, uses fixed shell-free non-waiting submit and later info/log calls, rehashes before/after execution and after raw-evidence reopening, and removes the credential profile plus absolute private path from retained records. Injected adversarial tests prove warning, mutation, symlink, profile, submission, and upload-substitution rejection without contacting Apple. Real authorized execution and successful-JSON measurement, both staple transitions, final app/DMG assessment, packaging correlation, and release gates remain open.
| Mac packaging equivalence | 0A/3 | active | The [v0.1 profile, generator, verifier, recovery command, and construction evidence](evidence/2026-08-21-mac-packaging-equivalence.md) bind the exact application ZIP, Sparkle archive, and sole release DMG to one parent-closed canonical app tree; disk tools consume only a private mode-0400 copy made from the already-hashed descriptor; 24 receipt fixtures, 8 attach-free tree/xattr cases, 5 release-integration cases, 3 partial-attach/recovery cases, 6 fail-closed recovery-refusal cases, 2 interrupted recovery-record update cases, and one concurrent pathname-substitution case prove closed canonical evidence and recovery; 2 explicit temporary APFS/UDZO reinspection cases passed on macOS 27/Xcode 27 beta. The current [Sparkle nested Developer ID packaging checkpoint](evidence/2026-08-23-sparkle-nested-developer-id-packaging.md) adds exact five-subject signature checks, exclusive publication, and a real signed-DMG inspection proving one 117-entry Sparkle-containing app tree across both ZIPs and the DMG | Repeat on stable macOS 26/Xcode 26.6 and the final post-staple candidate; add final Gatekeeper acceptance and post-notary byte correlation | Attach-free validation remains in public CI; final platform reinspection is restricted to the trusted, exclusive release lane |
| Apple privacy manifests | 0A/3 | active | The [closed privacy-manifest profile](evidence/2026-08-20-apple-privacy-manifest-boundary.md) owns strict candidate resources for the iOS app, Mac containing app, and Mac Agent; 12 fixtures reject tracking, collection, domains, schema/key/category/reason failures; live validation inventories 14 covered macOS source records and proves that an iOS-reachable call is either absent or whole-file macOS-guarded using the current SwiftPM graph; the [containing-app build](evidence/2026-08-21-permanent-mac-containing-app-target.md), [embedded Agent target](evidence/2026-08-21-permanent-embedded-mac-agent-target.md), and [permanent iOS target](evidence/2026-08-22-permanent-ios-application-target.md) bind all three indexed resources into their release-shaped target topology | Final-candidate bundle inspection remains; re-review Apple's catalog and actual App Privacy answers before submission; any SDK, telemetry, data-flow, covered-API, or topology change reopens the policy | All permanent target resources are bound; final-candidate work continues |
| Apple identifiers and permanent targets | 0A | active | Jenny Media LLC Team ID is confirmed privately; `media.jenny` is the confirmed company-controlled reverse-DNS prefix; the explicit Mac containing-app App ID `media.jenny.maccompanion` is registered; its [checked-in permanent menu-app target](evidence/2026-08-21-permanent-mac-containing-app-target.md) embeds an [inert, separately signed Agent](evidence/2026-08-21-permanent-embedded-mac-agent-target.md); unsigned, Apple Development, and clean Developer ID builds prove both Mac reverse-DNS code identities; the [permanent iOS target](evidence/2026-08-22-permanent-ios-application-target.md) now fixes `media.jenny.maccompanion.ios`, iOS/iPadOS 26.0, exact declarations, protected restart storage, and an unsigned dual-architecture Simulator build without tracked team, credential, profile, or entitlement authority | Register the iOS/iPadOS identifier, provision and sign a physical build, cold-launch the clean app, and bind real pairing; use the bound Mac/Agent designated identities for authenticated local IPC and lifecycle proof | Signed Mac/Agent acceptance and unsigned iOS composition can proceed independently |
| Persistent capture request | 0A | blocked-external | Account Holder eligibility, final Mac App ID, form answers, explanation, and Apple authorization acknowledgement are verified and prepared. A submission attempt on 2026-08-21 was not accepted because Apple requires an App Store URL and numeric App Apple ID even for this directly distributed, unreleased Mac product. An Apple Developer Support Entitlements case was opened the same day; its Case ID is retained privately | Wait for Apple's direct-distribution/prerelease guidance, then use only the confirmed truthful App Store URL/Apple ID path, complete the preserved request, and retain its private confirmation/status | Observe, protocol, lifecycle, ordinary-consent capture experiments, and non-persistent Control work continue |
| Stable release toolchain | 0A | blocked-external | `xcode-select` points to CommandLineTools and Xcode 27 beta is installed. Historical [containing-app](evidence/2026-08-21-permanent-mac-containing-app-target.md) and [embedded Agent](evidence/2026-08-21-permanent-embedded-mac-agent-target.md) evidence proved Apple Development/Developer ID signing, hardened runtime, exact distinct identities, universal construction, and signed launch on the beta toolchain; current [signing revalidation](evidence/2026-08-22-signing-identity-revalidation.md) proves valid Apple Development and Developer ID identities plus a strict-valid permanent Debug app and embedded Agent on Xcode 27 beta | Provide stable macOS 26/Xcode 26.6 and repeat exact signed platform evidence for release; keep distribution credentials in controlled release custody | Signed development and physical-runtime work may continue on Xcode 27 beta; only final release evidence remains blocked on the stable toolchain |
| Process and local IPC | 0A | active | ADR-0001, a [signed peer-identity probe](evidence/2026-08-21-signed-local-xpc-peer-identity-probe.md) proving reciprocal same-team exact identifiers plus closed hello shape and version rejection on Xcode 27 beta, a [production local-XPC handshake](evidence/2026-08-21-production-local-xpc-handshake-construction.md) binding the permanent Mach service and targets to exact reciprocal requirements and a closed non-authorizing hello, plus a [menu-readiness binding](evidence/2026-08-21-local-xpc-menu-readiness-binding.md) adding one exact acknowledged post-authentication message, ordered lifecycle publication, authenticated replacement fencing and cancellation, and exact fail-closed transport escalation, plus a [content-free status binding](evidence/2026-08-21-local-xpc-status-binding.md) adding closed method authorization, typed canonical bounded snapshots, single-flight timeouts, and generation-fenced replies while, at that checkpoint, the permanent Agent remained authentication-only; a [sealed local-XPC Agent and dashboard product composition](evidence/2026-08-21-local-xpc-product-composition.md) now derives lifecycle and typed status from the same complete Agent services, drives ordered menu authentication-readiness-status consumption, preserves recoverable source-unavailable retry, and retires stale dashboard generations; the [Agent release storage root](evidence/2026-08-21-agent-release-storage-root.md) uses a fixed release factory for one canonical private Application Support root with handle-bound databases and a cross-process-locked emergency deny latch, preserves active-latch recovery state, and returns the required-audit composition without treating diagnostic paths as a same-UID sandbox; the [prepared Agent product bootstrap](evidence/2026-08-21-prepared-agent-product-bootstrap.md) adds one-use listener-free identity/TLS/primary preparation and a separate inert top-layer storage/primary/XPC owner without accepting a pre-authenticated review surface; the [authenticated menu presentation-surface router](evidence/2026-08-21-authenticated-menu-presentation-surface-router.md) adds strict generation high-water and private issuance-token fences, shared activation and retirement barriers, post-acknowledgement stale compensation, and an endpoint-only non-waiting terminal-fence capability without adding XPC presentation messages or runtime activation; the [authenticated menu presentation contract](evidence/2026-08-21-authenticated-menu-presentation-contract.md) freezes five explicit publish/withdraw authorizations, exact reply sets, a separate 4,096-byte canonical payload bound, nonzero withdrawal IDs, and fresh-review versus durable-resume semantics; the [exact envelope layer](evidence/2026-08-21-exact-menu-presentation-envelopes.md) adds five operation-specific C parsers/senders, closed acknowledgements and publish-only rejection classification, exact UUID sizing, and synchronous Swift borrowed-byte copies without a generation endpoint or menu receiver; the [authenticated current-ready sender](evidence/2026-08-21-authenticated-menu-presentation-sender.md) adds exact-ready cached opaque issuance, the shared one-active-plus-seven-queued production FIFO, three-second reply fencing, weak-sender terminal latching, and a peer-wide status-and-presentation fence before one session cancel while permanent targets remain inert; a normative shared-payload profile, closed caller/endpoint/method matrix, bounded content-free status/events/export models, 2 indexed diagnostic fixtures, and 57 IPC tests; pairing creation and dismissal are menu-only, strict, Agent-fact-owned, exact-replay, tombstone-before-success, and QR-construction-compensated; complete SAS, transcript, key-fingerprint, policy, and local-name pairing decisions are strict, retry-fenced, and atomically persisted; the [already-authorized local pairing-review delivery](evidence/2026-08-20-local-pairing-review-delivery.md) adds exact pending-authority equality, surface acknowledgement, terminal withdrawal, endpoint-loss cancellation, exact post-commit replay, a revision-fenced Mac owner/reducer, and a compile-checked SAS/name sheet without treating the bundle seam as peer authentication; device-name administration is decode-validated and exactly correlated; grant decisions bind the Agent review, locally shown device name, exact current/proposed sets and revision fences; `CompanionAgent` adds 190 tests for fail-closed provider loading and startup reconciliation, one-Mac/one-phone primary replacement, pairing delivery/withdrawal and unavailable-review closure, registry-generation/full-descriptor/effect-bound one-time reviews, shared publication replacement, visible-review invalidation, replacement-versus-commit exclusion, bounded replay receipts, atomic SQLite compare/approve/queued-work fence/audit commit with injected rollback, unchanged declines, ordered remote-then-runtime stop, exact pending/active dispatcher invalidation, a [store-bound required-audit Interactive product root](evidence/2026-08-20-interactive-product-composition.md), [signature-bound initial runtime preparation](evidence/2026-08-20-initial-runtime-preparation.md), a [root-bound Observe status authority](evidence/2026-08-20-root-bound-host-status.md), a [durable host-identity release root](evidence/2026-08-20-durable-host-identity-root.md), [recoverable host-identity startup](evidence/2026-08-20-host-identity-startup-coordinator.md), [confirmed host-identity recovery](evidence/2026-08-20-host-identity-confirmed-recovery.md), [local recovery confirmation composition](evidence/2026-08-21-local-host-identity-recovery-composition.md), [unified Agent network startup](evidence/2026-08-20-agent-network-product-startup.md), four-effect menu teardown receipts, lifecycle and registry-publication audit isolation, and Agent-issued initial and replacement surface coordination through exact runtime preparation and clean-media acknowledgement, plus primary-channel sequencing, opaque target resolution, and generation-bound listener-handoff race fencing; a [coherent content-free local-status authority](evidence/2026-08-20-local-status-authority-construction.md) with source-owned updates, unique read sequences, count-only SQLite/provider adapters, exact listener projection, and fail-closed deny-latch/storage posture, plus a [source-scoped route authority](evidence/2026-08-20-local-route-monitor-authority.md) that preserves independent listener/Bonjour LAN evidence while expiring only authenticated configured-route contributions, and an [already-authorized local-status read capability](evidence/2026-08-20-local-status-read-service.md) with one clock sample, closed failure, and unique concurrent sequences, all issued by a [single fail-closed local-service root](evidence/2026-08-20-agent-local-service-root.md) with package-owned raw authority and source-specific facets; the [Agent sanitized diagnostic export](evidence/2026-08-21-agent-diagnostic-export-service.md) adds a boot-scoped newest-256 event ring, write-only producer facet, validated root-issued export capability, closed source failure, and explicit menu-app plus CLI authorization without becoming durable audit history; the [Mac Agent administration dashboard](evidence/2026-08-21-mac-agent-dashboard-construction.md) adds a revalidating content-free first-party shell, typed administration intents, and connection-generation/sequence/time fences that prevent stale local replies from restoring availability; the [Mac dashboard action coordinator](evidence/2026-08-21-mac-dashboard-action-coordinator.md) centralizes admission and serialized execution for all seven actions, preserves completed/not-completed/outcome-unknown results, revalidates exports, and fences late effects across authority replacement; the [sealed lifecycle observation source composition](evidence/2026-08-21-lifecycle-observation-source-composition.md) binds Agent self-ready to the complete service graph and issues serialized menu-generation readiness/invalidation capabilities only after platform authentication, without caller roles or PID/status inference; Interactive install/renew/revoke/surface-transition messages carry decode-validated 10-second leases and correlated readiness/safety receipts; the [permanent menu dashboard lifecycle bridge](evidence/2026-08-22-permanent-menu-dashboard-lifecycle.md) replaces synthetic menu status with a retained real product owner while keeping transport start disconnected; the [permanent Agent single-service selector](evidence/2026-08-22-permanent-agent-single-service-selection.md) revalidates canonical durable state and starts exactly one hidden profile: readiness/status for enabled, disabled bootstrap for canonical disabled state, closed authentication-only for recovery, and none before first unlock, with no presentation-capable fallback; the [permanent menu application launch](evidence/2026-08-22-permanent-menu-application-launch.md) binds exactly-once dashboard start to AppKit launch behind a package-owned delegate while keeping raw transport authority outside SwiftUI; [signing revalidation](evidence/2026-08-22-signing-identity-revalidation.md) proves a strict-valid same-team Apple Development app and embedded Agent; the [disabled-Agent bootstrap protocol](evidence/2026-08-22-disabled-agent-bootstrap-protocol.md) freezes a five-minute revision-bound consent command that grants no capability and cannot claim readiness; the [production Agent bootstrap binding](evidence/2026-08-22-agent-bootstrap-production-binding.md) injects the preparation-owned durable authority only for disabled startup, fences five-second exact XPC operations, and latches launchd restart after acknowledged or unacknowledgeable durable enablement while recovery remains closed; the [foreground remote-access setup](evidence/2026-08-22-foreground-remote-access-setup.md) adds exact Agent-only registration acquisition, the same-team menu bootstrap client, fixed explicit consent, owned-registration rollback, ambiguity retention, receipt-gated menu convergence, and registration-routed fresh dashboard construction in the permanent app | Run reciprocal signed clean-state disabled-to-ready acceptance before presentation or network ingress | Signed construction, the complete foreground/menu transaction, durable Agent transition, restart request, and dashboard routing are complete; signed launchd execution plus fresh readiness/status proof remain |
| Agent lifecycle | 0A/1 | active | Pure lifecycle reducer distinguishes explicit enable/disable, lock, logout/login, agent crash, and menu crash; Observe survives only eligible menu failure while Control requires both processes; a [bundle-independent lifecycle audit producer](evidence/2026-08-20-lifecycle-audit-producer-construction.md) validates completed reducer transitions and emits only coarse stable global enabled-intent/Observe-availability events after state/effects exist; the [login-role effect executor, convergence wrapper, and label-free `SMAppService` seam](evidence/2026-08-20-login-role-effect-executor-construction.md) register Agent then menu before enablement commit, roll partial enablement back in reverse, accept disable cleanup only after remote-safety completion, attempt both unregistrations after failure, require exact postconditions, converge idempotent and effect-then-error states, preserve closed approval/missing-service recovery reasons, fail closed on future statuses, project all current framework statuses, and await unregistration completion; the [dashboard lifecycle product composition](evidence/2026-08-21-dashboard-lifecycle-product-composition.md) adds exact prepare/compare-and-commit enablement, stale-state compensation, remote-safe disable ordering, truthful process-start failure, and same-desired-state convergence; the [durable lifecycle intent and restart reconciler](evidence/2026-08-21-durable-lifecycle-intent-reconciliation.md) adds strict canonical revision-fenced atomic desired-state storage, durable-intent-first mutation, safe-disabled absence, fresh non-ready startup state, exact read-back convergence, and enabled/disabled/login-state restart repair; the [generation-fenced process observation owner](evidence/2026-08-21-process-observation-and-lifecycle-aba-fencing.md) adds boot lifecycle revision, per-role epochs, ABA-safe prepared commits, exact-generation readiness/termination, replacement teardown, stale-callback rejection, and closed exact recovery outcomes; the [sealed lifecycle observation source composition](evidence/2026-08-21-lifecycle-observation-source-composition.md) binds Agent ready to the complete required-audit service graph and menu ready/loss to one post-authentication exact-generation connection capability with serialized terminal replay; the [bounded process recovery scheduler](evidence/2026-08-21-bounded-process-recovery-scheduling.md) adds three fixed idempotent menu-start retries fenced by exact lifecycle revision, role epoch, eligibility, and replacement observation; the [permanent SMAppService identity composition](evidence/2026-08-21-permanent-smappservice-identity-composition.md) retains the exact Agent plist and main-app services through the raw/converging/executor chain, while signed negative launch proof shows construction neither registers nor starts the Agent; the [Agent release storage root](evidence/2026-08-21-agent-release-storage-root.md) adds one canonical mode-0700 Application Support hierarchy, bounded mode-0600 security and audit databases, the emergency deny latch, post-construction handle/path binding, and ten reopen/path/concurrency tests; 79 focused reducer/producer/executor/convergence/platform tests prove recovery, non-recovery, privacy, storage-failure isolation, compensation, phase rejection, reentrancy rejection, status convergence, future-status rejection, exact status mapping, atomic persistence, crash-boundary convergence, restart repair, readiness separation, ABA fencing, and process-generation recovery; the [foreground setup composition](evidence/2026-08-22-foreground-remote-access-setup.md) adds same-actor registration acquisition ownership, pre-send compensation limited to the role introduced by setup, safe preexisting-role retention under ambiguity, exact disabled-offer decline cleanup, receipt-gated menu registration, and launch routing that never derives readiness from `SMAppService` | Prove approval/login/lock/crash/disable/logout/update/uninstall on clean users, beginning with the signed disabled-to-ready transaction | Bundle-independent lifecycle, registration ownership, storage, observation, and permanent setup composition are complete; signed platform and physical evidence follow |
| Remote transport | 0B/1 | active | Strict framing/replay/in-flight/reconnect rules, including closed Interactive request/response sets; golden exact P-256 SPKI/TBS DER, verified self-signed X.509 assembly, strict canonical certificate parsing/self-signature/current-validity verification, and 90-day same-key lifecycle; a [compile-tested host custody constructor](evidence/2026-08-20-host-identity-custody-construction.md) uses an exact bounded tag, prompt-free `AfterFirstUnlockThisDeviceOnly` private-key usage, Secure Enclave preference, exact same-key issuance, strict reinspection, and in-memory `SecIdentity` composition without exposing private bytes; a [recoverable host-identity startup coordinator](evidence/2026-08-20-host-identity-startup-coordinator.md) durably fixes the candidate UUID and exact tag before pending key creation, resumes the same key after failure, loads valid listener identity without rotation, and same-key replaces invalid certificates under a stale-write fence; [confirmed destructive recovery](evidence/2026-08-20-host-identity-confirmed-recovery.md) fences every old authority before new-key preparation, deletes the retired key while its tag remains durable, and atomically rotates identity; a [unified Agent network startup](evidence/2026-08-20-agent-network-product-startup.md) binds that result through exact-store primary bootstrap and final certificate comparison before listener consumption; a sealed one-shot host listener constructor binds that exact identity, fingerprint, current leaf, TLS 1.3-only bounds, disabled resumption/early data, and no local endpoint reuse without exposing mutable parameters or starting the listener; its listener owner wraps each exact accepted connection, evaluates negotiated TLS metadata only after readiness, and exposes only a one-use verified pump handoff; fail-closed TLS 1.3/no-early-data client pin/role admission; distinct host-listener TLS 1.3/no-early-data/served-identity binding; explicit pre-unlock/key-loss recovery decisions; a [no-network rejecting Network.framework construction probe](evidence/2026-08-20-network-tls-construction.md); a pure immutable-pin dial-round executor that selects only an authenticated exact-endpoint winner, cancels denial/late work, closes every late or mismatched authenticated route, and retains command-send authority on the winner; one reconnect owner that binds foreground/reachability/candidate changes, exact-round cancellation, connected-route cleanup, terminal denial, and bounded backoff; a one-shot client TLS attempt context binding one route/pin/callback/exact connection reference through a strict single-leaf `SecTrust` evaluator; a concrete compile-checked client route attempter owning readiness timeout, exact handoff, fresh session, denial mapping, command send, and cancellation; injected synchronization tests prove recoverable waiting, ready/failure, timeout/cancel, first-result-wins, and late-success rejection; and separate [host and client primary frame pumps](evidence/2026-08-20-network-primary-frame-pump.md) with serialized I/O and byte-independent deadlines, plus a sealed Agent listener service with a generation-bound lifecycle-owned exact pump handoff and a [content-free root-status binding](evidence/2026-08-20-agent-listener-status-binding.md); ingress follows Observe availability; injected frame-I/O boundaries prove host opaque-challenge framing, client hello framing, first-send failure, malformed input, receive failure, remote denial, and exactly-once teardown without opening a route; 36 transport, 13 host-identity/certificate, 15 host-custody/startup/recovery construction, 13 host Network-platform, and 33 client Network-platform construction/evaluator/fault tests | Execute and inspect host Keychain/Secure Enclave custody under the final signed Agent, physically execute accepted-connection metadata extraction and handoff, then prove multi-route/proxy behavior | Socket-independent diagnostics and no-network platform composition |
| Observation freshness | 1 | active | Receipt subtracts host-reported age plus full request RTT, then expires on a client monotonic deadline; disconnection always yields `unreachable`; platform-neutral presentation keeps retry/background/manual/action cause separate from retained data state; Interactive presentation additionally prevents disconnected retained sessions from claiming control, lock, or a live surface while preserving local Mac identity and coarse route class; 14 tests cover exact expiry, impossible clocks, every connection cause, control/view, lock, and terminal-recovery mapping | Bind to native iOS UI and measure snapshot RTT/reconnect p95 on physical devices | Localized copy, layout, and diagnostics can proceed without a socket |
| Security persistence | 0A/1 | active | Normative v0 storage and exact operation-binding profiles; schema-v7 migration with a durable pre-Keychain bootstrap candidate, atomic reviewed-recovery intent, and last-recovery receipt; atomic canonical grant replacement/reviewed resume with epoch and grant fencing; local-only confirmed device names with atomic content-free events and admission joins; atomic host bootstrap completion/certificate replacement/recovery fencing/replacement; idempotent digest-bound operation admission; no-eviction per-device quota and 30-day terminal retention; exact execution-claim revalidation; suspend/revoke queued-work fencing; crash-to-`outcomeUnknown` recovery; atomic queued/in-flight startup reconciliation with fault rollback; preallocated dual-slot deny latch with retained-inode binding and cross-process transaction locks; a separately quota-bounded 16 MiB detailed audit store with scoped gaps, exact current-grant self filtering, authenticated host/client pagination, and privacy-preserving bounded iOS/Mac history projection; one Agent mutation boundary now serializes registry/provider publication with local grant review/commit, invalidates reviews before post-commit audit, and preserves the committed result under audit failure/drop; the [real security-store](evidence/2026-08-21-security-store-sqlite-full-wal.md) and [detailed-audit-store](evidence/2026-08-21-audit-store-sqlite-full-wal.md) pager-full/WAL recovery proofs require atomic rollback under `SQLITE_FULL`, continued readability, truthful durable-gap state, truncating checkpoints, exact integrity, capacity recovery, and successful resumption; [shared SQLite storage-path hardening](evidence/2026-08-21-sqlite-storage-path-hardening.md) binds canonical owner-controlled parents, exact 0600 single-link regular database/sidecar artifacts, secure creation, and no-follow SQLite opens; the [three-boundary torn-WAL recovery matrix](evidence/2026-08-21-security-store-torn-wal.md) permits only refusal or whole-transaction recovery; 69 passing persistence/audit/latch tests | Simultaneous physical-volume exhaustion across both databases and the deny latch, main-database and directory-entry torn-write loops, Keychain cross-store crash drills, signed-bundle container/owner/Data Protection verification, signed-XPC local-history execution, and stable-toolchain release evidence | Native provider adapters and additional local IPC can proceed independently |
| Application pairing | 0B/1 | active | The host boot-scoped authority enforces random 32-byte secret/nonce material, five-minute monotonic expiry, five-proof limit, exact transcript/HMAC/signature/SAS verification, transcript-bound local decision, atomic SQLite consumption, and strict bounded QR payload encoding; the client authority refuses bytes before QR-pinned TLS, binds both public keys and nonces into the transcript, constructs the exact secret proof and fixed-width signature through an injected signer, fences cancellation and concurrent proof calls across the asynchronous signing boundary, verifies the host transcript/SAS/expiry response, clears the one-time secret, and publishes only a correctly correlated monitor-only final identity; presentation exposes only a secret-free untrusted preview, requires explicit acceptance before a start intent, upgrades fingerprint trust only after pinned TLS, shows SAS only after verified transcript convergence, and remains `saving` until exact durable commit; client custody separates nonexportable reconnect and fresh-presence approval keys behind opaque references and the publication authority revalidates both before one complete retry-safe store transaction; strict canonical local encoding rejects unknown/noncanonical/broadened records; the concrete bundle-independent file adapter bounds inventory and record size, applies 0700/0600 permissions, fsyncs temporary data before same-directory rename and the directory afterward, rejects conflicting identities and visible unknown state, and converges across injected pre/post-rename faults; restart preflight against the real adapter adopts exact committed keys, removes only true orphans, and preserves conflicts; `CompanionClientPlatform` compile-checks role-specific this-device-only/Secure Enclave key construction, public-only registration, LocalAuthentication approval prompts, direct-message ECDSA signing, and DER-to-raw conversion; 107 host/client pairing, local review delivery, Mac approval presentation, and shared-listener ingress, QR, presentation, custody, platform-profile, publication, storage, recovery, network-construction, and [signing-reentrancy](evidence/2026-08-20-client-pairing-signing-reentrancy.md) tests plus the [client pairing application owner](evidence/2026-08-20-client-pairing-application-owner.md) and [no-relay pairing adapter](evidence/2026-08-20-client-pairing-network-construction.md) cover nonmutating paths, immutable-pin route racing, serialized fragmented framing, exact deadline propagation, sanitized failure, cancellation, and durable-commit convergence; the [one-shot VisionKit scanner and Core Image renderer](evidence/2026-08-20-pairing-qr-io-construction.md) are package-constructed and cross-compiled with four logic/render tests; the [Agent-owned local pairing-session composition](evidence/2026-08-20-local-pairing-session-composition.md) adds strict create/dismiss payloads, one-visible-code lifecycle, expiry, replay, compensating tombstones, and durable-commit race fencing; the [local SAS/name pairing approval composition](evidence/2026-08-20-local-pairing-approval-construction.md) binds validated key fingerprints, complete local review, approval-only name, decline-null, policy/expiry fences, one-use outcome, and atomic device/name persistence; the [host pairing wire owner](evidence/2026-08-20-host-pairing-wire-owner.md) binds verified TLS identity, exact begin/prove correlation, shared replay, trusted-local review publication, and durable terminal completion while deferring expiry across an in-flight local commit; the [role-safe host listener ingress and pairing pump](evidence/2026-08-20-host-listener-ingress-construction.md) classify only exact first-frame auth/pairing traffic without over-read, preserve one-use TLS/socket authority, send silent durable completion, keep pairing independent from primary, and delay primary replacement until valid proof reaches ready; the [already-authorized local pairing-review delivery and SAS/name sheet](evidence/2026-08-20-local-pairing-review-delivery.md) bind exact pending review, surface acknowledgement, terminal withdrawal, endpoint-loss cancellation, exact receipt replay, and revision-fenced Mac presentation; the [listener-owned pairing-context composition](evidence/2026-08-20-listener-pairing-context-composition.md) gates new QR codes on exact listener plus Bonjour readiness and consumes active or suspended sessions on withdrawal or terminal loss; the [exact listener-pairing factory](evidence/2026-08-20-listener-pairing-factory.md) derives QR identity, Bonjour service, and port from the same consumed TLS configuration; the [sealed pairing product composition](evidence/2026-08-20-pairing-product-composition.md) binds that listener context to one required-audit security store, QR session owner, host proof authority, decision owner, and authorized review service through a production-only aggregate; the [Mac pairing presentation reducer](evidence/2026-08-20-mac-pairing-presentation-reducer.md) preserves exact command retries, rejects mismatched receipts, and erases the QR on invalidation; the [value-driven Mac pairing sheet](evidence/2026-08-20-mac-pairing-sheet-construction.md) keeps unconfirmed codes visible and never treats implicit close as cancellation success; the [Mac pairing application owner](evidence/2026-08-20-mac-pairing-application-owner.md) composes exact authenticated-local command retries with bounded expiry, cleanup, receipt-adversary handling, and generation-fenced Agent loss without moving pairing authority into UI | Physical QR scan round trip, signed physical camera permission/recovery, Keychain/Secure Enclave creation/access-control/prompt tests, final iOS access group and container Data Protection/backup configuration, live certificate-pinned transport convergence, production same-team exact-identifier XPC transport, restart/error audit detail, and physical-device exchange remain | Application authentication and identity-neutral transport orchestration |
| Application authentication | 0B/1 | active | Unknown/inactive client IDs receive opaque challenges; 10-second challenges are bounded and single-use; golden-vector proof verification re-reads the current device and epoch before returning a principal; session description correlates to `auth.proof`; a [fixture-backed non-authorizing configured-route request/ack, primary-session integration, and generation-fenced Agent projection](evidence/2026-08-20-authenticated-route-protocol.md), a [revision-bound client reconnect, durable route-update, bootstrap, lifecycle, and package-UI composition](evidence/2026-08-20-client-configured-reconnect-composition.md), a [durable-session-key-bound reconnect security composition](evidence/2026-08-20-client-reconnect-security-composition.md), and a [store-bound configured-route Network/UIKit product](evidence/2026-08-20-client-configured-route-network-product.md) bind opaque provenance to the authenticated connection with strict sequence, inclusive 30-second freshness, byte-independent expiry, replacement fencing, LAN preservation, and diagnostic-failure isolation; one host primary-session owner binds listener identity, exact proof correlation, replay, 45-second liveness, per-command durable-principal revalidation, status/Act/discovery/Interactive routing, and exactly-once Interactive authority teardown; separate host and client Network.framework adapters enforce length framing, serialized fail-closed backpressure, disconnect closure, and byte-independent auth/liveness timers after independently verified same-connection handoff; the client one-shot TLS context prevents route/pin/callback/connection substitution and uses the strict single-leaf Security evaluator; the host sealed-listener path prevents connection/binding substitution by constructing a one-use pump authority only from the exact ready connection's negotiated metadata; the concrete route attempter maps only closed remote authentication errors to terminal denial and otherwise preserves transient route failure; injected latches prove cancellation and first-terminal-result semantics; injected client and host frame-I/O boundaries drive real hello/challenge framing, malformed input, send/receive failures, closed remote denial, and idempotent teardown through the pumps; the client authority refuses auth before pinned TLS, owns bidirectional handshake replay/correlation and the same exact deadline, delegates fixed-width signing without key custody, verifies paired host/device IDs, and publishes no connection identity before description success; one opaque session-reference adapter supplies pairing and reconnect signing without approval-key access; 81 authentication/mapper/host-session/client-session/host-and-client-Network/configured-route tests plus custody tests cover the boundary | Instantiate the composed network application owner in the permanent target plus rendered/signed configured-route UI evidence; physical listener metadata execution, live TLS callback ordering, Security.framework signer physical execution, pinned physical convergence, and physical-device exchange remain | Bonjour and foreground client orchestration |
| Discovery and routes | 0B/1 | active | `_maccompanion._tcp`/`local.` is frozen; endpoint text is canonical and closed; TXT metadata is limited to protocol major and an untrusted 64-bit host hint; 3 discovery tests reject ambiguous routes and metadata injection; the sealed TLS listener now preconfigures that exact service and collapses service-registration add/remove callbacks into closed LAN evidence; [no-network construction probe](evidence/2026-08-20-network-discovery-construction.md) maps the profile to Network.framework | Start advertise/browse only in a disposable signed identity, then prove Local Network grant/deny/recovery and route changes on physical identities/devices | Reconnect and route-ranking state can proceed without Local Network permission |
| Capture/input feasibility | 0A | active | Isolated probe compiles ScreenCaptureKit, Accessibility, Core Graphics, VideoToolbox, and `SMAppService`; an availability-gated package factory maps the frozen dimensions/frame-rate/queue-depth/video-range/cursor/audio profile into `SCStreamConfiguration`; a [menu-owned opaque target catalog](evidence/2026-08-20-opaque-target-catalog-construction.md) sanitizes app/window inventory, consumes transient tokens, rechecks live ownership and exclusions, and compile-checks exact selected-display application and desktop-independent window filters without enumeration; 6 tests prove profile bounds, privacy/lifetime invariants, explicit self-exclusion, and aspect-fit construction; a concrete but uninstantiated `SCStream` adapter plus bounded one-newest event owner normalize only complete exact-profile frames and serialize start/stop/system/sample/encoder failures, with 7 in-memory/injected tests; an injectable VideoToolbox policy plus concrete session driver applies realtime High 4.1 with no frame reordering and bounded bitrate/frame-rate/keyframe properties, with 4 tests proving exact order and fail-fast rejection; bounded CoreMedia extraction builds strict AVCC configuration/access units and normalized samples, with 8 tests covering exact construction, extension form, preallocation bounds, real in-memory format-description/block/sample extraction, attachment-derived keyframe truth, and timeline validation; the latency-first encoder owner plus concrete compile-checked `VTCompressionSession` adapter enforce one in flight, one latest waiter, clean recovery after replacement, awaited runtime backpressure, callback correlation, queue rejection, and exact terminal cleanup, with 7 injected tests; 8 publisher tests prove lease-fenced configuration/access-unit/discontinuity/end records, clean recovery, sequence-preserving new-surface fences, terminal rejection, and timeline bounds through the actual runtime action validator; the runtime now suppresses input across exact +1 Agent-issued surface replacements until discontinuity, configuration, clean keyframe, and exact acknowledgement complete; unposted pointer-event construction and pure input-event inspection remain no-post; the [2026-08-20 non-prompting CLI baseline](evidence/2026-08-20-platform-authority-preflight.md) remains no-grant/no-post/no-enumeration/no-stream/no-encoder-allocation; the [explicit capture/encode smoke construction](evidence/2026-08-21-capture-encode-smoke-construction.md) adds exact command parsing, production-owner composition, closed timeout/cleanup outcomes, eight injected tests, and a live permission-denied no-graph report without claiming real pixels | Run separate signed-menu-app Screen Recording, Accessibility observation, real encode, post-event, and lock probes after final IDs | Bind the catalog through authenticated final-identity XPC and physically prove filter/display transforms; continue no-prompt platform composition |
| App Review | 0A/3 | active | Current Apple guidance was rechecked on 2026-08-23; the [external TestFlight review package](testflight-review-package.md) now contains honest LAN-first positioning, 4.2.3(i)/4.2.7 risk treatment, candidate prerequisites, beta description, What to Test, no-account review notes, exact reviewer steps, attachments, clean rehearsal, and rejection/no-go paths without creating an App Store Connect record or submission | Replace candidate-bound placeholders only after explicit iOS App ID/provisioning, notarized Mac download, managed-entitlement disposition, physical scenario matrix, final privacy/export answers, and clean reviewer rehearsal | Internal TestFlight construction and physical product evidence continue; external submission remains explicit and human-authorized |
| Observe alpha | 1 | active | The v0 trust kernel, permission-free macOS metrics sampler, durable compare-and-swap generation/revision authority, validated host-to-wire response composition, single-owner foreground reconnect policy plus immutable-pin route-round execution, and honest monotonic freshness assessment pass locally; failed samples or commits produce no response and consume no revision. The [authenticated client Observe owner](evidence/2026-08-21-client-observe-channel.md) binds status and privacy-limited self-audit reads to the exact primary connection and router lane, fixes generation and strictly increases revisions, computes conservative monotonic freshness, retains disconnected status only as unreachable, preserves audit cursor/gap evidence, and publishes only after the router generation check; the real injected primary pump routes both Observe status and Act catalog responses through the concrete bridge. The [first-party Observe UI](evidence/2026-08-21-client-observe-ui.md) now presents distinct waiting/live/stale/unreachable/unavailable truth, validated Mac health, bounded scoped activity and explicit history gaps without a Control entry; five projection tests, iOS cross-compile, and the six-test Simulator accessibility flow pass | Instantiate the bridge and event-to-presentation binding from the configured-route application product and permanent target, then complete a physical paired exchange after release-shaped identities/lifecycle exist | Signed-target composition and disposable lifecycle/Bonjour probes |
| Bounded Act alpha | 1 | active | Exact effect/authorization/provider-bound operation digest; restricted RFC 8785 corpus; closed schema/registry and invoke/approval/status/cancel wire flow; one validated immutable registry/provider publication now backs local grant review, discovery, admission, release-path provider resolution, execution, and cancellation, while old provider references remain valid only for already-retained in-flight snapshots; the release coordinator retains exactly one publication from invoke/approval admission through provider effect; the authenticated command coordinator hard-gates ingress on startup reconciliation, scopes operations to the principal, preserves original parameters through approval, and resolves exact providers; correlated command dispatch returns only closed status/approval/error responses; the host primary session constructs operation context from its authenticated principal and authentication-issued connection ID after replay and durable-principal checks; the client primary session publishes that connection identity only after pinned TLS, exact proof correlation, and paired host/device verification; separate compile-only Network.framework pumps bind both primary-session contracts to serialized framed I/O and independent deadlines without claiming live trusted sockets; privacy-limited discovery returns only durably granted and currently installed descriptors in bounded stale-fenced pages without provider inventory; the client publishes catalogs only after every fence-matched page and renders live results only after invoked-descriptor schema validation, mapping unknown terminal identifiers to a generic failure; the [independent client Act path](evidence/2026-08-21-client-act-path.md) adds a catalog/session-fenced one-operation owner, complete closed-schema parameter drafts, an approval-key-only fresh-presence signer, exact invoke/approval/status/cancel correlation, late-signature invalidation, same-operation ambiguous-delivery recovery, granted-only Approved Actions UI, complete effect review, and distinct delivery/outcome/result states without starting Control; the authenticated Act channel composes exact-correlated pagination and one-operation routing; the connection-scoped primary router adds closed Observe/Act/Control lanes, exact replay/correlation/deadline admission, generation-gated publication, old-primary fencing, and a real pump bridge while preserving same-ID recovery and late-signature invalidation; the expanded disposable harness proves a typed mute edit and verified result with no socket, credential, or signer; transactional execution claim; monotonic host deadline with conservative `outcomeUnknown`; closed results/failures and cancellation; atomic no-retry startup reconciliation; exact post-start provider removal that retains unrelated provider references; Mac-only desired-state `setAudioMuted` candidate checks Core Audio property/settable state and verifies read-back with locked use disabled; the [native MVP Agent provider composition](evidence/2026-08-21-native-mvp-agent-provider-composition.md) now constructs that reviewed descriptor and exact live Core Audio provider as one value consumed by the complete Agent network startup, eliminating release-target registry/loader drift while remaining inert before admitted execution; the [bounded keep-awake candidate](evidence/2026-08-21-native-bounded-keep-awake-provider.md) adds explicit start-until/stop descriptors and an inert public-IOPM adapter capped at four hours while remaining outside the advertised registry pending physical and UX proof; the proposed three-state [system-appearance action](evidence/2026-08-21-native-system-appearance-no-go.md) is an evidence-backed no-go, with validation rejecting undocumented global mutation and Agent/native-provider Apple Events; 105 focused operation/discovery/wire/native-provider/transport/host-session/client-session/client-UI and native-product-composition tests plus persistence fault tests cover publication validation/replacement, concurrent complete-snapshot reads, multi-consumer generation fencing, one-read invoke retention, review/commit serialization, pagination, grant filtering, stale cursors, partial-catalog discard, safe results, delayed replay, approval execution, ownership, safe error disclosure, reply-kind fencing, missing providers, deadlines, cancellation races, provider removal during pending approval and running cancellation, recovery, and exact first-party startup publication | Instantiate the complete startup-reconciled Agent network product and primary-router bridge from permanent targets; complete verified same-socket certificate/trust handoff; run physical approval-key, authenticated operation exchange, and explicit no-prompt Core Audio support/mutation/read-back tests on signed clean devices; external adapters still require process/channel termination proof | Additional bounded native adapters, signed-target composition, and physical evidence can proceed behind the contract |
| Adaptive Control | 2 | active | Normative bundle-independent session/surface, session/channel-message, security, 96-byte media, reliable-input, macOS mapping, host/client admission/presentation, client security-composition, host command-composition, menu-app execution, and local-warning profiles; 18 indexed Interactive Control fixtures; focused coverage in the 1,270-test Swift suite enforces approval/session limits, privacy/fences, media/input framing, authenticated host routing and exactly-once teardown, closed client reply sets, current grant/menu/display/name admission, stable SQLite plus visible-menu revision joins and a [store-bound required-audit product composition](evidence/2026-08-20-interactive-product-composition.md), Security.framework material generation, correlated host challenge/proof dispatch, final-runtime revalidation, reentrant-request exclusion, disconnect/install-race compensation, exact local pending/transition/active dispatcher shutdown, final host input admission, exact primary-bound fresh-presence approval signatures plus a [selected-primary Control session owner](evidence/2026-08-21-client-primary-control-session.md), closed correlated handshakes, pinned-TLS mutually proven role channels, one-shot approval/channel authorities, atomic session/bootstrap creation with rollback, [signature-bound one-use initial runtime preparation](evidence/2026-08-20-initial-runtime-preparation.md), decode-validated bounded local execution leases, correlated readiness/safety receipts, Agent-issued exact +1 surface-replacement leases, fail-closed runtime preparation receipts, transition-ordered discontinuity/configuration/clean-keyframe admission, relative-validity wire descriptors materialized only on the client monotonic clock, distinct initial-Desktop configuration/clean-keyframe/acknowledgement gating, closed primary target-inventory and surface select/acknowledge sequencing, session-scoped opaque-token expiry and consumption, shared sequence handoff, and exact reply-gated input resumption; the single visible-menu runtime owner serializes effects, shows identity before capture, expires without traffic, terminates on Agent IPC loss, resumes partial fail-closed cleanup without repeating completed effects, correlates input envelope/fence/class/current lease in the same actor turn as its bounded synchronous platform post, strictly validates AVCC configuration/NAL/keyframe structure, and owns digest-bound gap-free bounded media enqueue across renewal with fail-closed queue backpressure; the bounded queue never evicts, rejects mixed sessions, and is purged before renderer blanking; the compile-checked capture-to-publication chain admits only complete exact-profile frames, keeps one newest callback plus one latest encoder waiter, awaits lease-fenced runtime acceptance, emits configuration before clean video, preserves sequence through discontinuity/new-surface fences, and terminates on any sample/encoder/runtime failure; the [bundle-independent client mapper](evidence/2026-08-20-client-input-mapping-construction.md) enforces half-open render geometry, direct-touch/trackpad modes, balanced drags, reset-on-mode-change, bounded scroll, and closed keyboard actions while a thin main-actor UIKit seam is iOS-Simulator compile-checked; the [generation-fenced client decoder](evidence/2026-08-20-client-decoder-construction.md) shares AVCC validation with the host, requires clean reset boundaries, rejects stale callbacks, retains one latest frame, and compile-checks VideoToolbox construction; the [bounded render handoff](evidence/2026-08-20-client-render-handoff-construction.md) orders callback generations and sequences, holds one pending result and one scheduled main-actor drain, and compile-checks exact-format UIKit display-layer presentation plus synchronous blanking; macOS planning maps supported HID and modifiers, tracks/reset releases, and binds constructed Core Graphics batches to exact display/coordinate geometry without posting or off-display buttons; a [compile-checked SwiftUI-to-UIKit live surface](evidence/2026-08-20-client-live-surface-construction.md) binds aspect-fit gesture geometry to one decoder/renderer session and resets plus blanks on disable or teardown; a [package-level iOS UI](evidence/2026-08-20-client-ui-construction.md) preserves unverified/verified pairing, durable-saving, connection, view/control/lock, and Remote-Control-optional distinctions through closed value-driven intents and adds a Desktop/app/numbered-window picker without window titles; Mac presentation keeps durable grant expansion, phone approval, one-session warning, and active stop state distinct while preserving every effect fact, and its local stop closes only after exact Agent authority/runtime completion | Final identities plus physical capture, encode/decode/render, physical UIKit recognizer/renderer evidence, post-event, lock, network latency, authenticated local UI, and safety evidence still gate a usable alpha; authenticated XPC binding and physical app/window filter execution remain open | Pairing/native UI, concrete client identity/key storage, authenticated XPC admission proof and physical transition evidence can continue independently |
| Route classification | 1/3 | active | A [source-scoped generation/freshness authority](evidence/2026-08-20-local-route-monitor-authority.md), [listener-plus-Bonjour LAN authority](evidence/2026-08-20-agent-lan-route-evidence.md), [authenticated configured-route protocol plus Agent projection](evidence/2026-08-20-authenticated-route-protocol.md), and a [fixture-backed client catalog/session state](evidence/2026-08-20-client-configured-route-construction.md) plus [durable reconnect/edit/bootstrap/lifecycle/UI composition](evidence/2026-08-20-client-configured-reconnect-composition.md) pass bundle-independent tests; the [application lifecycle binding](evidence/2026-08-20-client-application-lifecycle-binding.md) serializes UIKit activity and injected scheduling-only reachability through durable-before-dial reconciliation and carries the exact validated lifecycle snapshot; the [private-access guidance contract](private-route-guidance.md) verifies lifecycle coherence, maps every reconnect phase, withholds contradictions, and keeps the disposable iOS harness live across controller-internal completion without socket authority; `privateDNS`/`privateNetwork` derive only from explicit configured provenance on the exact authenticated primary, never DNS/interface/process inference; [primary-source review](research/2026-08-20-route-classification-policy.md) records why generic `NWPath` inference is a no-go | Instantiate the composed owner in the signed target without granting guidance route authority, and physically prove final-identity listener/Bonjour and configured private-DNS/user-managed-private-network routes | Local status reads, listener/discovery composition, UI guidance, and every non-route lane continue |
| No-relay beta | 3 | deferred | Route-independent identity is a fixed requirement | Stages 1 and 2 must pass; external review strategy required | Provider-neutral diagnostics design |
| MacTools/provider work | 4 | deferred | Paper compatibility map only | Market-MVP repeat-use gate | No bridge implementation before the gate |
| Semantic/native surfaces | 5 | deferred | Safety boundary documented | Market-MVP evidence and one validated job | No semantic authority inferred from Accessibility data |
| Administrator capabilities | 6 | deferred | Each capability is independent | Separate demand, threat model, containment, and review per capability | Each item receives its own pass/no-go/deferred record |
| Assisted operation | 7 | deferred | Untrusted-planner boundary documented | Earlier gates plus one validated assisted job and injection review | No model receives control authority implicitly |

Latest permanent-iOS checkpoint, superseding the target-composition and
signed-target-next-step wording in the Apple-target, Observe, Bounded Act,
Adaptive Control, and route-classification rows: the
[permanent iOS release composition](evidence/2026-08-22-permanent-ios-release-composition.md)
now owns protected QR/SAS pairing, crash-recoverable first-route publication,
configured no-relay reconnect, and the first-party Observe, Approved Actions,
and independently authorized Remote Control workspace from the permanent
target. It starts no configured connection before explicit route provenance
and cannot infer authority from routing, reachability, or app lifecycle. The
remaining proof is registered-identity signing and physical same-LAN pairing,
followed by live Observe, `setAudioMuted`, and Interactive media/input evidence.

Latest disabled-Agent durable-authority checkpoint, superseding the durable
owner portion of the Process/local-IPC and Agent-lifecycle next steps: the
[Agent bootstrap durable authority](evidence/2026-08-22-agent-bootstrap-durable-authority.md)
now issues revision-bound expiring offers and commits exact enabled successor
intent through the existing locked atomic store. Exact read-back is required
after every write outcome, exact command replay is write-free, and generation
plus operation high-water fences prevent suspended storage work from crossing
peer replacement. The next proof is injection into the exact XPC handler,
successful-receipt service retirement, explicit Agent-only setup registration,
and foreground menu-client composition.

Latest disabled-Agent bootstrap-transport checkpoint, superseding the
exact-envelope next-step wording in the Process and local IPC row: the
[exact bootstrap transport](evidence/2026-08-22-disabled-agent-bootstrap-transport.md)
now binds the two frozen methods to four closed XPC dictionaries, nonempty
4,096-byte canonical codecs, and one ordered generation/operation-fenced offer
then enable transaction. It rejects overlap, offer substitution, malformed
receipts, timeout, cancellation, peer replacement, and delayed callbacks
without adding durable mutation, readiness, presentation, or network authority.
The next proof is the Agent-owned serialized durable offer/enable handler plus
explicit foreground Agent-only setup registration and menu-client composition.

Latest process/local-IPC checkpoint, superseding the receiver-next-step wording
in the Stage 0A row: the [authenticated menu product composition](evidence/2026-08-21-authenticated-menu-product-composition.md)
now connects accepted lifecycle readiness to the exact sender/router, binds the
production dashboard receiver to menu-owned presenters with awaited teardown,
and lets the prepared Agent wait for a replaceable authenticated menu authority
before one-use construction of a nonescaping unstarted network product.
Authenticated replacement and endpoint-terminal paths immediately fence the
old generation; menu loss cancels pending visible review state while leaving
primary ingress and Observe nonterminal for a later ready generation.
The [coordinated Agent network-listener activation](evidence/2026-08-21-coordinated-agent-network-listener-activation.md)
now retains exact listener construction/start/rollback inside the same
nonescaping product owner and leaves readiness to Network callbacks. Live
request-context composition, permanent-target activation, and signed
two-process evidence remain gated.

The [Interactive lease local-XPC checkpoint](evidence/2026-08-22-interactive-lease-local-xpc-transport.md)
fixes and implements exact install, renewal, and revoke transport between one
authenticated-and-ready Agent/menu generation. The later initial-Desktop
checkpoint adds preparation as the fourth operation on the same cross-family
transaction gate. Strict canonical payloads, asymmetric bounded deadlines,
exact receipt correlation, and generation-wide failure on ambiguity preserve
fail-closed ownership. Connection loss invokes local unacknowledged runtime
invalidation. This transport carries no input or media and does not itself
activate capture or posting; the existing stable pairing/recovery authority
remains Control-free.

The [Interactive runtime composition boundary](evidence/2026-08-22-interactive-runtime-composition-boundary.md)
now forwards the exact lease lifecycle into one serialized menu runtime with a
sticky cleanup-failure latch. Its Agent owner double-revalidates durable and
visible admission around opaque Desktop preparation, transfers channel
credentials only after the exact install receipt, renews only the exact current
lease after another final admission read, and requires correlated four-effect
revocation or compensation. The subsequent
[opaque-display and lease-scheduling checkpoint](evidence/2026-08-22-opaque-display-and-lease-scheduling.md)
retains the physical main-display mapping only in the menu-platform module,
publishes its opaque UUID, refuses redirection after display loss, and renews
from exact acknowledged lease deadlines without retrying ambiguity. Concrete
platform effects and secondary channel handoff remain Control composition
gates.

The [initial Desktop runtime transport checkpoint](evidence/2026-08-22-initial-desktop-runtime-transport.md)
now adds Desktop preparation as the fourth operation on the authenticated
runtime transport's shared single-flight gate. The menu resolves the exact
admission-published opaque display through the same process-local mapper and
returns only a bounded, exactly correlated descriptor without ScreenCaptureKit
enumeration or platform effects. Install now carries that complete descriptor,
binds it to every lease surface dimension during construction and decoding,
revalidates Desktop kind plus monotonic validity before indicator/capture, and
passes the full command into the capture seam. The later
[permanent Agent runtime binding](evidence/2026-08-22-permanent-agent-interactive-runtime-binding.md)
installs one stable fail-closed authority in the dispatcher before XPC and
binds only the exact authenticated-ready generation through its cached opaque
endpoint. The server queue rechecks that generation and its private issuance
token, so stale endpoints cannot redirect work to replacements; menu loss and
product finish serially retire the bound owner. The later
[persistent Control indicator and expiry](evidence/2026-08-22-persistent-control-indicator-and-expiry.md)
makes the permanent target construct the menu runtime, publishes a named
menu-bar and open-menu indicator with local Stop, keeps it visible while any
prior safety effect is uncertain, and schedules exact monotonic expiry with
renewal replacement, stale-token rejection, and early-wake correction. The
later
[host Interactive role-ingress checkpoint](evidence/2026-08-22-host-interactive-role-ingress.md)
adds strict secondary-role classification and mutual proof on the shared TLS
listener, keeps one-time credentials inside the exact generation-bound Agent
runtime, and retains only a same-client/primary/session/epoch input-media pair.
The later
[host Interactive role-data-plane checkpoint](evidence/2026-08-22-host-interactive-role-data-plane.md)
transfers the concrete pair to one generation- and runtime-fenced Agent owner,
applies bounded exact input framing, and enforces one-record-at-a-time media
backpressure with paired fail-closed teardown. The full 1,449-test Swift
catalog, cross-builds, and eight platform probes pass. Authenticated local-XPC
input/media routing plus concrete capture/frame/input adapters remain the next
independent Control slice.
The subsequent
[authenticated local-XPC Interactive role-data checkpoint](evidence/2026-08-22-authenticated-local-xpc-role-data-transport.md)
closes that process boundary with exact input and media dictionaries,
independent generation-fenced single-flight lanes, asymmetric deadlines, and
generation-wide fail-closed invalidation. Input reconstructs its full command
fence only inside the active serialized menu runtime. Media uses a zero-buffer
Agent rendezvous that withholds the menu acknowledgement until the exact
network media role takes the complete record. Production binds both directions
only to the current authenticated menu generation. Concrete ScreenCaptureKit,
VideoToolbox, queue-drain, Core Graphics posting, and signed physical evidence
remain the next independent Control slice.

The [concrete macOS Interactive effects checkpoint](evidence/2026-08-22-concrete-macos-interactive-effects.md)
now closes that construction slice in the permanent menu application. The
exact authenticated lease activates a Desktop-only ScreenCaptureKit stream,
bounded real-time VideoToolbox H.264 owner, non-evicting queue with one
acknowledged local-XPC publication in flight, and the sole release Core
Graphics HID-post boundary. Construction remains inert; display mapping and
input permission are revalidated before capture starts; event planning commits
only after complete construction/posting; and failure withdraws the queue
callback and invokes ordered four-effect cleanup. The indexed fixture count is
71 and the full 1,461-test Swift catalog, macOS/iOS cross-builds, and eight
platform probes pass on Xcode 27 beta. A flaky pre-existing synthetic
route-racing barrier was corrected and passed 20 isolated repetitions. Signed
two-process TCC behavior, real posted input, physical iPhone pixels and
latency, lock/takeover, final-identity XPC, and stable-Xcode evidence remain the
next Control gates; persistent capture authorization remains independent and
is not claimed by this ordinary-consent implementation.

The [visible Interactive admission checkpoint](evidence/2026-08-22-visible-interactive-admission-contract.md)
now carries the closed canonical menu-process generation, exact revision, and
optional opaque selected-display publication through an independent
authenticated local-XPC request/ack transaction. The permanent Agent inserts
one stable authority into both its durable-plus-visible admission reader and
the presentation-capable XPC profile; the menu publishes revision 1 after
readiness and before status. Exact replay, +1 replacement, bounded deadlines,
and generation-loss withdrawal fail closed. The initial display is nil and
grants nothing. The following opaque-display checkpoint now replaces that nil
with a menu-owned random token for the current main online display while
keeping the physical identifier process-local and non-presentational.

The [conservative network request-context checkpoint](evidence/2026-08-22-conservative-network-request-contexts.md)
now supplies live clocks, unique response IDs, and an owned public macOS
session/lifecycle source for that listener seam. [Primary-source API
research](research/2026-08-22-public-macos-session-state.md) found no documented
lock-state discriminator: same-user/on-console/login-complete remains ambiguous
and maps to `otherConsoleUserActive`, never unlocked or locked. Sleep and
terminal lifecycle signals fail closed. Permanent-target invocation, Act and
Control availability, and signed runtime evidence remain separate gates.

The [other-console lifecycle checkpoint](evidence/2026-08-22-other-console-lifecycle-fail-closed.md)
now carries that conservative state through the product lifecycle instead of
forcing it into active, locked, or logged-out. A ready enabled Agent preserves
Observe while another or ambiguous console user is active, but local
administration and new Interactive Control require a positively observed active
configured-user session; a takeover ends current Interactive Control without
closing the primary Observe session. Lock currently follows the same
fail-closed teardown until the ordered genuine-lock-surface transition is
implemented and physically proven. The [inert Agent application lifecycle
facade](evidence/2026-08-22-inert-agent-application-lifecycle-facade.md) now
retains that lifecycle and the conservative request contexts behind one owner.
Construction is safe-disabled and observer-free; start observes only public
workspace lifecycle, and explicit or deinitializing terminal finish cannot
resurrect state even through retained context closures. It creates no
storage, Keychain, XPC, listener, process, login-role, or readiness authority.
The [durable-intent-ordered inert product preparation
checkpoint](evidence/2026-08-22-durable-intent-agent-preparation.md) now loads
the exact durable intent from its dedicated release-storage subdirectory before
constructing primary inputs, rejects invented positive lifecycle state, and
retains a ready prepared product behind its canonical lifecycle snapshot and
terminal finish only. Construction may reconcile durable storage and host
identity, but readiness-producing local-XPC construction is deferred; it starts
no observer, XPC service, listener, process, login role, pairing session, or
readiness path. The [permanent Agent inert-preparation
integration](evidence/2026-08-22-permanent-agent-inert-preparation.md) now
invokes that facade through a narrow application product. Ready preparation and
durable local-recovery wait may open the existing authentication-only XPC
service; first-unlock wait alone exits so the configured launchd policy may
retry. Preparation or
XPC-start failure exits closed, and a ready XPC-start failure awaits prepared-
root retirement. The executable cannot import broad product, network, or lifecycle
platform authority and still activates no observer, product XPC, listener,
process, login role, pairing, readiness, Observe, Act, or Control path.

Local device administration now includes a [bundle-independent active-revoke
convergence path](evidence/2026-08-21-local-device-revocation-convergence.md):
closed five-minute review/command/receipt values, an independent primary-ingress
security fence, proactive session/route/Interactive teardown, exact stale-state
comparison, schema-v8 durable command/receipt journaling, latch-backed atomic
SQLite revoke, startup reconciliation, content-free status convergence, and
cross-restart exact replay for the tombstone lifetime. Issue 13 remains active
until final authenticated-XPC, indicator truth, and signed physical sub-second
evidence pass.

## Public repository remediation

The 2026-08-21 read-only remote audit found that
`Jenny-Media/MacCompanion` is already public, with no declared license, branch
ruleset, classic branch protection, Actions run, private vulnerability
reporting, secret scanning, validity checks, or push protection. The published
root currently contains only `.gitignore`, `README.md`, and `docs`. The local
tree now assigns `@xcv58`, the sole visible Jenny Media member and authenticated
administrator, through `.github/CODEOWNERS` and pauses external contributions
until approved license, contribution, trademark, and private-reporting policies
exist. No remote setting or published file was changed. Provider controls,
private reporting, license approval, history review, and publication of the
local safeguards remain urgent authorized work rather than future launch tasks.

## Immediate milestone

The [bundle-independent diagnostic CLI v0.1 contract](evidence/2026-08-21-diagnostic-cli-contract.md)
now fixes the only commands admitted by the authenticated local-IPC matrix:
content-free status, sanitized diagnostics export, local help, and version.
One authoritative fixture owns valid/invalid arguments, exact request plans,
fixed text, and eight closed failure mappings. The pure `CompanionCLI` target
revalidates typed values before text or compact sorted JSON and has no
executable, transport, file writer, or identity claim. Seven focused tests pass;
the permanent `maccompanionctl` still requires final signing identity and
physical signed final-identity XPC evidence for the CLI role.

The [Agent sanitized diagnostic export service](evidence/2026-08-21-agent-diagnostic-export-service.md)
now closes the source behind both CLI export and the dashboard intent. One
boot-scoped Agent authority assigns content-free event sequences, retains only
the newest 256 entries, and exposes coordinators only to a write-only publisher
facet. The root-issued exporter combines those events with a fresh validated
status snapshot and maps every source/construction failure to one closed error.
The menu app and CLI are explicitly admitted by the closed method matrix; the proven menu-app identity still requires production XPC composition,
while the CLI needs its own permanent identity before either receives the
capability. Seven new Agent tests and one IPC boundary test bring the measured
suite to 1,061 tests, including 185 Agent and 43 IPC tests.

The [Mac Agent administration dashboard](evidence/2026-08-21-mac-agent-dashboard-construction.md)
now gives the menu application a coherent content-free entry surface for
enabled intent, lifecycle, listener, closed route kinds, security posture,
bounded inventory/session counts, and sanitized warnings. Its application
owner revalidates every snapshot and binds it to one increasing local
connection generation; sequence replay, time regression, replacement, loss,
and delayed callbacks cannot restore stale availability. The SwiftUI shell
emits only typed enable, disable, retry, pairing, devices, activity, and
diagnostics intents and keeps the one-device pairing gate explicit. Fourteen
focused tests pass. Production final-identity XPC composition and signed lifecycle
effects remain separate gates.

The [Mac dashboard action coordinator](evidence/2026-08-21-mac-dashboard-action-coordinator.md)
now gives those typed intents one execution owner and one admission policy
shared with SwiftUI. All seven actions re-read and revalidate current status;
effects serialize, local navigation remains effect-free, diagnostics are
revalidated, and the existing pairing owner reports completion only with a
visible Agent-issued receipt. Closed completed, not-completed, and
outcome-unknown results remain distinct. Authority replacement fences a
suspended revision without letting its late completion overwrite current
state. Twelve new tests pass; final lifecycle, status, and diagnostic adapters
still require signed-target peer and platform composition.

The [dashboard lifecycle product composition](evidence/2026-08-21-dashboard-lifecycle-product-composition.md)
now supplies the concrete lifecycle adapter behind that action owner. The
[durable lifecycle intent and restart reconciler](evidence/2026-08-21-durable-lifecycle-intent-reconciliation.md)
extends it with strict revision-fenced atomic desired-state storage. Commands
persist the user's choice before live mutation; missing storage defaults to
disabled; startup restores no stale readiness; and enabled, disabled, and
logged-out states converge roles, reducer state, and eligible start requests.
Forty-four product/platform tests plus the real-root revision/epoch integration
pass. Final signed service construction, authenticated observation sources, and
physical lifecycle evidence are the remaining lifecycle gates.

The [login-role effect executor](evidence/2026-08-20-login-role-effect-executor-construction.md)
now registers both roles before an enable transition may commit and accepts
disable unregistration only after remote teardown. Eight focused tests prove
exact Agent-then-menu registration, reverse rollback, best-effort two-role
disable cleanup, closed failure receipts, explicit readiness handoff, phase
rejection, and reentrancy rejection. The status-aware convergence wrapper adds
thirteen tests for idempotency, exact
postconditions, approval recovery, missing-service detection, and
effect-then-error races. The label-free `CompanionAgentPlatform` adapter maps all
four current `SMAppService` statuses and awaits asynchronous unregister
completion. The generation-fenced observation owner now keeps both roles
starting until exact final-source ready, rejects stale callbacks, and requests
only exact recovery effects. Final-identity construction must supply the
authenticated menu process/IPC adapter without inventing readiness from service
registration, status, start requests, or PID presence. The Agent source is now
bound to the complete required-audit service graph.

The [client application lifecycle binding](evidence/2026-08-20-client-application-lifecycle-binding.md)
now serializes application-global UIKit activity and injected reachability into
the durable configured-route lifecycle. Package tests prove no pre-start or
background dial, reconciliation before the first attempt, active-route closure
on background, one-round re-arming, and fail-closed invalid time. The
[disposable iOS harness](evidence/2026-08-20-client-ui-simulator-harness.md)
passed six UI tests, including a real Home/reactivation transition that starts
exactly one additional synthetic round without opening a socket.

The [independent client Act path](evidence/2026-08-21-client-act-path.md)
closes the previous product-shell gap: Approved Actions are now reachable from
the paired-Mac workspace without entering Remote Control. The bundle-independent
owner binds one operation to the authenticated client/host/device/connection
and exact catalog fence, validates typed schema parameters and results, uses
the separately protected user-presence approval key, discards late signatures,
and queries the same durable operation after ambiguous delivery. Nine focused
tests plus six authenticated-channel race tests pass, the iOS UI cross-compiles, and the six-test disposable harness
edits and completes a typed mute action while asserting that no Control entry
appears in the Act flow. The real primary Network pump now satisfies the narrow
authenticated byte-sender boundary, with catalog pagination and operation
interpretation retained by the Act owner. The
[client primary router](evidence/2026-08-21-client-primary-router.md) now adds
closed Observe/Act/Control request lanes, exact correlation and replay,
generation-gated publication, old-primary fencing, and an authentication-time
bridge that routes real injected pump catalog and status exchanges into their
Act and Observe owners. The
[client Observe owner](evidence/2026-08-21-client-observe-channel.md) adds exact
host/generation/revision status admission, conservative live/stale/unreachable
assessment, bounded self-audit pagination with explicit gap evidence, and
invalidation-wins publication. Six focused owner tests and the authenticated
pump integration pass.
The [configured-route primary product](evidence/2026-08-21-configured-primary-product.md)
now constructs an inert Observe/Act/Control bridge per authenticated parallel
route and
publishes handles and host/connection-tagged events only after the reconnect
state machine accepts that exact winner. A two-route race, real injected-pump
status exchange, selected teardown, and pre-selection termination prove that
losing or stale candidates remain invisible. The
[selected-primary Control session owner](evidence/2026-08-21-client-primary-control-session.md)
adds exact primary binding, explicit Desktop request, fresh Control-only user
presence, the correlated approval continuation, accepted role offers,
typed denial/retry, and stale-route teardown without claiming that the role
channels are active. Permanent-target instantiation, physical approval-key
execution, signed Core Audio mutation, and a physical authenticated exchange
remain explicit gates.

The [client secondary role handshake](evidence/2026-08-21-client-secondary-role-handshake.md)
now binds accepted input/media offers to the exact winning endpoint retained
outside presentation state. Its injected pump performs bounded four-byte
big-endian framing, exact fragmented reads, pinned-role mutual proof, a fixed
30-second monotonic deadline, and no post-accept over-read. A concrete
Network.framework role connector, paired socket-generation owner, clean-media
activation, and physical media/input evidence remain the next gates.

The [concrete client role Network owner](evidence/2026-08-21-client-secondary-role-network.md)
now consumes role-neutral one-shot TLS evidence from each exact live
`NWConnection`, opens input and media only on the selected endpoint, rechecks
the current primary after both proofs, and closes every ready sibling on role
failure or replacement. Configured-product initial Desktop activation now
consumes the ready media socket through a bounded exact-read pump and the
primary descriptor/acknowledgement exchange; live physical exchange remains
open.

The [configured-product role binding](evidence/2026-08-21-client-role-product-binding.md)
now starts the exact pair only after application state retains the accepted
Control value, fences late completion by activation generation, and retires the
pair on retry, rejection, failure, replacement, or exact primary termination.
Its role-channels-ready state remains below presentation. The
[initial Desktop activation owner](evidence/2026-08-21-client-initial-desktop-activation.md)
now drives exact media records through VideoToolbox/render composition and
withholds acknowledgement until a renderer-issued current clean-frame receipt.
The exact primary reply gates a serialized reliable-input sender and UIKit
gesture enablement. The subsequent [continuous media authority handoff](evidence/2026-08-21-client-continuous-media-handoff.md)
keeps admitting exact-surface delta frames while that reply is pending and
transfers the same configured media and reliable-input authorities into steady
surface control without resetting either sequence. Exact-connection and
accepted-session-fenced lifecycle
publication now advances the selected-primary workspace through channel
connection, channel readiness, initial verified-frame preparation, active, and
stage-specific failure without permitting skipped or backward transitions.

The [remote Control stop exchange](evidence/2026-08-21-client-remote-control-stop.md)
is now closed and canonical. The client retires its role pair when the exact end
request is enqueued but reports remote completion only after the correlated
receipt. The host clears admission before awaiting input release, capture stop,
media purge, and output blanking, and sends that receipt only after the safety
boundary completes. Duplicate, early, stale-connection, and wrong-session
events cannot repeat teardown or advance the selected-primary state.

The [first-party selected-primary live screen](evidence/2026-08-21-client-primary-live-control-screen.md)
now requests full Control separately from opening media, owns the UIKit
decoder/render/input product across SwiftUI navigation, waits for the exact
verified-frame acknowledgement before enabling input, offers touch and trackpad
modes, and invokes the typed remote Stop path. The six-test no-network
Simulator harness renders that production destination, exposes the Touch mode,
opens its actual software keyboard, emits typed payloads from visible key taps,
then proves Stop returns to the workspace and dismisses the keyboard. Observe
and Approved Actions remain peers and do not require opening or retaining the
live screen. A manual stateless iOS keyboard forwards bounded text/delete
actions while retaining no remote field value; focus-aware Smart Input remains
a separate gated surface.

The [client primary workspace](evidence/2026-08-21-client-primary-workspace.md)
now consumes that selected product through one expected-host, exact-connection
state owner. Its latest-one revision stream rejects out-of-order UI work,
retains disconnected status only as unreachable, clears all Act authority on
teardown, clears old status on replacement, distinguishes catalog errors from
operation errors, and exposes typed command methods rather than raw bytes. A
first-party SwiftUI workspace makes Observe, Act, and Control separate peers;
opening the Control entry is only an intent and grants no session authority;
the separate typed command starts the selected-primary approval flow, and the
entry remains disabled while preparation is in flight or has failed while an
active session may reopen its already-owned live surface. The
1,129-test hardened package and iOS cross-compile pass. Permanent-target
instantiation and physical private-route evidence remain explicit gates.

The [coarse reachability source](evidence/2026-08-20-client-coarse-reachability-construction.md)
now maps Network.framework path status to a pessimistic Boolean stream with no
endpoint, interface, DNS, VPN, or provenance authority. Two tests prove closed
mapping, one-start lifecycle, idempotent stop, stream completion, and late-event
rejection; the concrete source cross-compiles for iOS. A
[single application-global owner](evidence/2026-08-20-client-network-application-owner-construction.md)
now fixes pessimistic startup, bridge/source stop ordering, and terminal failure
containment. The composed harness passes six UI tests, including exactly-once
failure reporting with no dial after an invalid round. The next client milestone
is permanent-target instantiation and signed physical airplane-mode, Wi-Fi,
background, and private-route recovery evidence. Identity, Keychain, live
private-route, lock-session, and latency gates remain external and do not block
other bundle-independent work.

Latest Adaptive Control construction checkpoint, superseding the
authenticated-XPC/app-window-transition next-step wording above: the
[adaptive surface runtime binding](evidence/2026-08-23-adaptive-surface-runtime-binding.md)
connects the permanent Agent's authenticated primary surface dispatcher to an
exact-generation local-XPC family and a menu-only opaque
ScreenCaptureKit target owner. Desktop, application, window, and Desktop
escape-hatch transitions now use ordered input release, source preparation,
runtime fence/lease commit, activation, discontinuity/configuration/clean-frame
gating, and exact acknowledgement before input resumes. Replacement leases
rearm their exact expiry deadline, stale sessions cannot trigger recovery for
another session, and window input uses retained global bounds plus the backing
scale of the containing display. The full gate passes 71 indexed fixtures,
1,467 `MacCompanionKit` tests, 8 platform probes, cross-builds, and the unsigned
permanent app build. Signed installation/Agent enablement, TCC consent, live
two-process pixels/input, physical iPhone, lock/takeover, latency, and reconnect
evidence remain open; none blocks continued bundle-independent work.

The subsequent [adaptive client surface switching](evidence/2026-08-23-adaptive-client-surface-switching.md)
binds that host runtime to the permanent iOS live product. **View** requests a
fresh privacy-limited application/window inventory, keeps Desktop as an escape
hatch, and drives one reset-before-select replacement exchange. Input remains
inert across selection and media transition; decoder admission alone is no
longer sufficient, because the client must prove the exact clean frame was
rendered before acknowledgement and must validate the host's exact reply
before resuming input. The 45-test Interactive Client and 46-test Client
Network Platform suites pass; the full gate passes 71 fixtures, the 1,468-test
Swift catalog, macOS/iOS cross-builds, unsigned permanent application builds,
and eight platform probes. Focus-pushed Smart Zoom and Smart Input remain
fixture-first work; signed installation, TCC, real pixels/input, and
physical-iPhone evidence remain open external gates.

The [manual visual Smart Zoom fallback](evidence/2026-08-23-manual-visual-smart-zoom.md)
now gives every live pixel surface an explicit local 1x-to-4x pinch, bounded
pan, and Fit mode without changing the host surface or authority fence. It
resets and suppresses remote gestures during adjustment, inverse-maps direct
points and trackpad deltas afterward, and returns to Fit on viewport, encoded
surface, replacement, or lifecycle changes. The 48-test Interactive Client
suite passes; the full gate passes 71 fixtures, the 1,471-test Swift catalog,
macOS/iOS cross-builds, unsigned permanent application builds, and eight
platform probes. This closes the manual visual fallback, not focus-assisted
Smart Zoom: the current strict request/reply primary owner cannot accept an
unsolicited focus event without a separately frozen ordered event lane. Signed
installation, TCC, real pixels/input, physical-iPhone gestures, focus latency,
and lock behavior remain open evidence gates.

The [ordered focus-event lane and client admission](evidence/2026-08-23-ordered-focus-event-lane.md)
now replaces that strict request/reply limitation with one closed Control event
kind. It has an independent replay window and exact sequence, carries only the
current surface fence plus privacy-filtered focus shape, and cannot resolve or
consume a command. Its short-lived one-use target token feeds only the existing
reset, select, clean-frame, acknowledgement, and input-resumption exchange; a
paused event suppresses local input until recovery. The full gate passes 73
fixtures, the 1,477-test Swift catalog, macOS/iOS cross-builds, unsigned
permanent application builds, and eight platform probes. The host
Accessibility observer/token issuer and automatic iOS application are next;
signed installation, TCC, real pixels/input, physical-iPhone focus behavior,
latency, and lock behavior remain open evidence gates.

The following [host focus-event capability authority](evidence/2026-08-23-host-focus-event-authority.md)
now gives the Agent latest-only, one-use admission for a sanitized focus
candidate. Every token is bound to the exact event identity/sequence, current
surface fence, focus projection, and local expiry, cannot be reused within the
session, and is consumed before the menu resolver must reproduce the exact
Focused Region descriptor. A current Focused Region cannot change focus unless
input was first reported paused. The full gate passes 73 fixtures, the
1,482-test Swift catalog, all cross-builds/unsigned permanent builds, and eight
platform probes. Accessibility observation, authenticated local candidate
delivery, primary-stream event sending, live crop construction, and automatic
iOS application remain the next safe lanes; signed and physical evidence
remains open.

The subsequent [host event transport and Accessibility projection](evidence/2026-08-23-host-event-transport-and-ax-projection.md)
now gives the authenticated primary frame pump one serialized event/reply write
lane and admits only the frozen null-correlation focus event after readiness.
The menu-platform Accessibility reader immediately projects the focused element
to a closed category, editable/secure flags, and bounded normalized geometry;
it never reads content, labels, titles, descriptions, identifiers, or selected
text, and unsafe or clipped geometry falls back closed. The full gate passes 73
fixtures, the 1,485-test Swift catalog, all cross-builds/unsigned permanent
builds, and eight platform probes. Authenticated local-XPC candidate delivery,
live observation, Agent product emission, ScreenCaptureKit crop construction,
and automatic iOS application remain the next safe lanes; signed TCC and
physical evidence remains open.

The following [authenticated focus-candidate local XPC](evidence/2026-08-23-authenticated-focus-candidate-xpc.md)
extends that family to ten closed operations. One canonical request/reply binds
the exact current session, epoch, surface, surface revision, and coordinate
revision while carrying only the sanitized target/focus/reason/input-paused
candidate. The menu retains current global input bounds, assigns opaque stable
focus identity from the reduced tuple, and—when an existing Focused Region
changes—releases posted input once and keeps new input closed until the normal
replacement acknowledgement. The full gate passes 73 fixtures, the 1,488-test
Swift catalog, all cross-builds/unsigned permanent builds, and eight platform
probes. A permanent Agent observation/event owner, focused-region capture crop,
automatic iOS application, and signed physical evidence remain open.

The [permanent focus-event observer](evidence/2026-08-23-permanent-focus-event-observer.md)
now closes the live Agent publication lane. It polls only when the exact
server-issued primary connection ID still matches the acknowledged Interactive
session, fences menu-generation replacement across suspension, creates the
ordered one-use event through the existing Agent surface authority, and sends
through the current authenticated primary's serialized write lane. Publication
failure revokes the token and closes surface control. The full gate passes 73
fixtures, the 1,493-test Swift catalog, all cross-builds/unsigned permanent
builds, and eight platform probes. Focused-region ScreenCaptureKit crop
construction, automatic iOS Smart Zoom application, and signed physical
evidence remain open.

The [live Focused Region Smart Zoom checkpoint](evidence/2026-08-23-live-focused-region-smart-zoom.md)
now constructs the bounded ScreenCaptureKit crop and applies the authenticated
event in the permanent iOS product. The menu re-reads the exact reduced focus,
uses display-logical `sourceRect` with global input bounds, and retains an
application-limited display filter for Window-origin Smart Zoom because
ScreenCaptureKit ignores `sourceRect` on single-window filters. The selected
client buffers the first-acknowledgement promotion race, disables input across
the existing two-phase replacement exchange, updates the live descriptor only
after exact acknowledgement, and makes automatic following explicitly
reversible; every manual surface selection opts out. The full gate passes 73
fixtures, the 1,499-test Swift catalog, all cross-builds/unsigned permanent
builds, and eight platform probes. Signed two-process TCC execution, physical
crop pixels, physical-iPhone focus latency/usability, multi-display edges, and
lock behavior remain open without blocking other safe lanes.

The [signed physical launch baseline](evidence/2026-08-23-signed-physical-launch-baseline.md)
now advances the external evidence lane without changing tracked signing
authority. Fresh invocation-only Apple Development builds pass strict
signature inspection for the iOS app and the Mac containing app plus embedded
Agent. The iOS app installs, launches, and survives on a paired physical iPhone
17 Pro Max running iOS 27 beta; the signed Mac containing app launches a live
menu-bar process and status-item scene while the Agent remains absent. The
available iOS profile is wildcard development only, and an unrelated
foreground-app screenshot is intentionally rejected as visual evidence.
Explicit Remote Access enablement/Agent registration requires action-time
confirmation; privacy consent, reciprocal local-XPC readiness, physical
pairing, Observe, Act, Control, and distribution evidence remain open.

The [direct-update trust policy](evidence/2026-08-23-update-trust-policy.md)
now freezes Sparkle 2.9.6 at full upstream revision
`ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a`, distinct release-injected
beta/stable authorities, signed feeds, pre-extraction verification, Ed25519 and
Developer ID trust, notarized whole-bundle replacement, and no initial delta or
installer-package path. A five-minute foreground confirmation is cancelled on
foreground loss; install remains closed until network admission, Control,
bounded work, Agent shutdown, and version compatibility all converge safely.
Thirty-five fixtures pass. The [Sparkle provenance and topology audit](evidence/2026-08-23-sparkle-provenance-and-topology-audit.md)
now binds the clean full revision, upstream manifest, official binary archive,
shared license, safe ZIP/symlink/Mach-O shape, absent upstream privacy manifest,
disabled profiling/custom parameters, and the exact three-object retained
non-sandboxed runtime graph. The subsequent
[exact dependency admission](evidence/2026-08-23-exact-sparkle-dependency-admission.md)
now binds the package and shared resolution, embeds only the required framework,
disables static profiling, strips the XPC services and release tools from
archives, verifies the unsigned three-object topology, and corrects the source
SBOM. No updater object, feed, key, appcast, download, or update action exists
yet.

The [update installation runtime gate](evidence/2026-08-23-update-install-runtime-gate.md)
now admits only a same-channel, increasing-build candidate with every frozen
feed/archive/Developer ID/notarization fact, then serializes five-minute local
foreground confirmation, inactive Control, network-admission closure,
bounded-work drain, Agent stop, exact version match, and one updater handoff.
Every stage rechecks expiry and foreground state; failed partial shutdown
records network-only or Agent-plus-network reconciliation, and reentrant
events cannot relabel consumed handoff authority. Twelve focused tests and the
full 1,511-test gate passed at that checkpoint. The subsequent
[inert Sparkle runtime adapter](evidence/2026-08-23-inert-sparkle-runtime-adapter.md)
adds a bounded release-authority value, unresolved protected build placeholders,
no-authority/no-updater construction, disabled profiling/parameters/headers,
disabled automatic checks/downloads, an explicit informational-probe-only menu
surface, and a fail-closed prohibition on download or installation checks. Its
nine focused tests and the full 1,520-test gate pass. Protected feed values,
Sparkle validation callbacks, signed two-version upgrade, and rollback evidence
remain open. The subsequent
[exact update candidate admission](evidence/2026-08-23-exact-update-candidate-admission.md)
now correlates the reviewed feed item with an independent post-validation
observation, requires all six trust facts, closes direct production construction
of the lower-level candidate, and mints at most one runtime authority. Five new
tests brought that checkpoint to 1,525. The subsequent
[runtime shutdown orchestration](evidence/2026-08-23-update-runtime-shutdown-orchestration.md)
seals the lower-level authority from production consumers, rechecks
foreground/time/Control at every transition, runs the exact four-effect order,
and completes the minimum recorded recovery scope before returning failure.
Five further tests bring the full gate to 1,530; no live updater action ran.
The subsequent
[signed update publication binding](evidence/2026-08-23-signed-update-publication-binding.md)
requires a successfully validated signed appcast, a bounded nonzero archive
length, and one canonical 64-byte Ed25519 signature at informational-candidate
construction, then matches the length and signature exactly at later
admission. An exact Sparkle 2.9.6 source audit also closes an unsafe inference:
`didExtractUpdate` does not attest notarization, and an Ed25519-valid archive
may carry a changed Apple signing identity. Developer ID and notarization facts
therefore remain unavailable until a protected release-evidence bridge binds
them to the same candidate. Two new tests bring the passing full count to
1,532; no live feed, download, extraction, or install action ran.
The subsequent
[update release-evidence projection](evidence/2026-08-23-update-release-evidence-projection.md)
replaces the three release-trust Booleans with a typed, exact-candidate-bound
value carrying five canonical artifact/evidence digests and four required
passing release claims. The permanent adapter now rejects an informational
item unless its signed enclosure has exactly the 17 frozen custom attributes;
unknown, missing, malformed, failed, or substituted fields close the offer.
Five new tests bring the passing full count to 1,537, while every Sparkle
download and installation check remains denied.
The subsequent
[update validation-correlation checkpoint](evidence/2026-08-23-update-validation-correlation.md)
wraps the exact candidate and release evidence in one immutable published value
and makes the lower-level admission owner package-internal. The corrected
single-use actor correlates exact `willExtract` and installer-start events but
does not treat Sparkle 2.9.6's `didExtractUpdate` as validation completion.
Admission opens only at the later `showReadyToInstallAndRelaunch` hold point,
after asynchronous validation and stage-one preparation; mismatch, evidence
substitution, reordering, cancellation, concurrency, or reuse closes it. Seven
tests cover the corrected lifecycle and keep the passing full count at 1,544.
The app still implements none of these callbacks and still cannot start a
download or install.
The subsequent
[Sparkle ready-to-install hold-point bridge](evidence/2026-08-23-sparkle-ready-holdpoint-bridge.md)
adds a compile-verified complete `SPUUserDriver` proxy in the permanent app and
serializes exact `willExtractUpdate` and installer-start callbacks into the
package actor. It intercepts the later readiness reply but cancels with
`.skip`; the source validator rejects an unconditional `.install` reply and
all full/background update checks. The real foreground confirmation and
runtime-effect owner remain open, so no download or installation authority is
enabled.
The subsequent
[update Agent reactivation saga](evidence/2026-08-23-update-agent-reactivation-saga.md)
addresses the Agent's `KeepAlive=true` replacement constraint. One package
owner persists exact source/candidate recovery intent before completed Agent
unregister and advances it only after the process is gone; failure recovery and
startup repair re-register only the exact source or candidate build and clear
the receipt after matching authenticated Agent readiness. Eight injected tests
pass. No live registration or updater action ran; the atomic store and concrete
platform bindings remain open.
The subsequent
[atomic update Agent reactivation store](evidence/2026-08-23-atomic-update-agent-reactivation-store.md)
adds canonical closed receipt encoding and a private, lock-serialized,
no-follow, fsync/rename/directory-fsync compare-and-swap store. Eight tests
cover reopen, phase advance, clear, faults, unsafe filesystem entries, and
concurrent writers. A cached-URL-size mismatch found by the tests was removed
in favor of sole descriptor `fstat` authority. No live Application Support or
Agent mutation ran.
The subsequent
[authenticated Agent build attestation](evidence/2026-08-23-authenticated-agent-build-attestation.md)
extends the reciprocal signed-peer hello acknowledgement with one exact
`UInt64` Agent bundle build, rejects malformed or open dictionaries in C, and
adds a bounded startup-only probe that always cancels its session. Focused
local-XPC tests pass without launching an Agent. Registration state and the
embedded helper file are no longer candidates for running-build evidence; app
startup repair and active-dashboard observation remain to be wired.
The subsequent
[update Agent startup-repair binding](evidence/2026-08-23-update-agent-startup-repair-binding.md)
closes the first of those two wiring gaps. The permanent containing app now
constructs the private atomic store, closed registration mapping, converging
ServiceManagement effects, and bounded authenticated-build readiness, then
runs retained-receipt repair before route reconciliation or dashboard
construction. Missing receipt is effect-free; composition or repair uncertainty
routes unavailable. Seven adapter tests, 49 application-platform tests, and an
unsigned permanent-app build pass. The complete gate passes 1,575 package
tests plus 8 platform probes. No app, Agent, login role, XPC session, or updater
action ran; active-dashboard build retention and runtime shutdown binding
remain next.
The subsequent
[active-dashboard Agent build lifetime](evidence/2026-08-23-active-dashboard-agent-build-lifetime.md)
now retains that exact hello build for one dashboard connection, clears it on
every terminal or ambiguous connection path, and gives production consumers no
mutation API. The permanent app shares the same lifetime with its dashboard and
its candidate-bound Agent-stop factory; startup repair still uses the bounded
one-shot probe. Six focused tests and the unsigned app build pass. The factory
is not invoked, and the complete gate passes 1,579 package tests plus 8 platform
probes. Network close, bounded drain, updater handoff, live Agent shutdown, and
Sparkle installation remain closed.
The subsequent
[reversible update network quiescence](evidence/2026-08-23-reversible-update-network-quiescence.md)
separates reversible listener admission from terminal Agent shutdown, adds
exact authenticated menu-to-Agent close/drain/reopen commands, and composes
them around the existing Agent-stop saga. Race, role-drain, exact-envelope,
authorization, generation, dashboard-lifetime, and minimum-recovery tests pass
without starting any app, Agent, listener, XPC service, login role, or updater.
The complete gate passes 1,590 package tests plus 8 platform probes. The
permanent app still supplies no prepared-installer adapter, so Sparkle's hold
point remains `.skip`; signed two-version execution remains open.
The subsequent
[dashboard update reconciliation](evidence/2026-08-23-update-dashboard-reconciliation.md)
now binds app-level close/drain forwarding to the exact active dashboard and
supplies the shutdown coordinator an inert product-router recovery closure.
Reconciliation is single-flight; explicit current-generation command failure
is retried, unavailable or ambiguous current transport is replaced immediately,
and only one registration-gated replacement may receive up to 40 readiness
attempts at a 250-millisecond cadence. Replacement ambiguity, exhaustion,
registration loss, cancellation, or lifecycle loss stays closed. Six focused
tests pass. The permanent app still has no prepared-installer adapter, and no
app, Agent, login role, XPC service, listener, network connection, or updater
was started. The complete gate passes 1,596 package tests plus 8 platform
probes.
The subsequent
[one-shot prepared-installer reply](evidence/2026-08-23-one-shot-prepared-installer-reply.md)
adds a main-actor owner for the coordinator's final updater effect. Install can
resolve once; explicit cancellation and owner retirement resolve skip; reuse
fails closed. The permanent Sparkle hold point constructs this typed adapter
but still cancels it, while source validation permits the sole install reply
only in the exact closed mapping and forbids any permanent-app start call. Four
focused tests pass. Full update checks, foreground confirmation, coordinator
construction, listener mutation, Agent stop, and installation remain closed;
the complete gate passes 1,598 package tests plus 8 platform probes.

## Blocker handling rule

Every blocked item records its affected artifact, evidence needed to unblock it, and parallel work. The project is not globally blocked while any safe in-scope lane remains active or ready. A later-stage capability is complete only with passing exit evidence or an explicit evidence-backed `no-go` or `deferred` disposition.
