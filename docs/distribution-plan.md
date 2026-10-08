# Mac Companion Distribution and Release Plan

Status: release baseline for the first implementation. This document fixes the intended channels, signing boundary, update model, and release gates; it does not create a release system.

## 1. Decisions

- The Mac product is distributed directly by Jenny Media LLC, outside the Mac App Store.
- Every Mac executable is signed with Developer ID, uses the hardened runtime, is notarized, and ships in one app bundle.
- The initial Mac installer experience is a notarized DMG containing `Mac Companion.app`; no root installer or separately copied daemon is required.
- The embedded per-user LaunchAgent and the containing menu app's login launch are registered through their appropriate `SMAppService` roles after the user opens and enables the app. Stage 0 verifies crash recovery separately from an intentional local Quit and Disable action.
- Mac updates use Sparkle 2 with HTTPS, Ed25519 archive signatures, Developer ID validation, and notarized replacement bundles.
- The iPhone and iPad app uses TestFlight for alpha and beta, then the App Store for release.
- The initial deployment targets are macOS 26.0 and iOS/iPadOS 26.0. Installed Xcode 27 beta may be used for development, compatibility, signing setup, device work, and currently supported TestFlight uploads. Final release evidence is reproduced with stable Xcode 26.6 and Swift 6.3; generation 27 beta remains outside the final release dependency.
- Mac Companion operates no account, relay, rendezvous, VPN, analytics, or update proxy. The download site and signed update feed are the only vendor-hosted runtime-adjacent services.
- Development signing identities may live on the development Mac. Developer ID, App Store distribution, notarization, Sparkle, and promotion credentials remain in a separately controlled release environment.

Apple describes Developer ID and notarization for software distributed outside the Mac App Store in [Signing Mac software with Developer ID](https://developer.apple.com/developer-id/) and [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). The toolchain baseline is recorded in [Xcode 26.6 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_6-release-notes).

## 2. Identifier and account preflight

The following account facts are tracked before permanent release-shaped Apple targets are completed. They do not block the normative specification, pure Swift packages, public unsigned CI, or disposable experiments:

- Legal team name: Jenny Media LLC
- Team ID (confirmed privately)
- Reverse-DNS bundle prefix controlled by the company: `media.jenny` (confirmed)
- Developer ID Application certificate availability and custody
- Apple Development and Apple Distribution certificate strategy
- App Store Connect access and agreements
- Final macOS App ID to use for the Persistent Content Capture request (registered as `media.jenny.maccompanion`)

The confirmed planned identifiers are:

| Target | Planned identifier |
| --- | --- |
| macOS containing app and menu UI | `media.jenny.maccompanion` |
| Embedded per-user agent | `media.jenny.maccompanion.agent` |
| Local XPC services, if selected | `media.jenny.maccompanion.xpc.<role>` |
| iOS/iPadOS app | `media.jenny.maccompanion.ios` |

The Team ID and final containing-app App ID preconditions are resolved. The embedded Agent is now an app-like daemon wrapper with a build-proven reverse-DNS identifier, exact private Keychain group, LaunchAgent identity, and eligible development profile. Its explicit Developer ID App ID/profile remains a distribution gate rather than a source-controlled secret. Remaining iOS/XPC App IDs, authenticated designated-requirement policy, update configuration, managed-entitlement approval, audit migrations, and App Store records still need to be bound deliberately. Renaming an official identifier later is not treated as a cosmetic change.

The Persistent Content Capture entitlement is managed. Apple says it enables VNC apps to view and record the screen and requires a request before use; see [Persistent Content Capture](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.persistent-content-capture). The Jenny Media LLC Account Holder prepared the request against `media.jenny.maccompanion`, including the authorization acknowledgement, but Apple's form requires an App Store URL and numeric App Apple ID. Because the directly distributed Mac app is unreleased, the request remains unsent until a truthful prerelease App Store Connect record path is verified or Apple Developer Support confirms the direct-distribution alternative. An Entitlements support case was opened on 2026-08-21 and its Case ID is retained privately. Stage 1 monitoring can proceed; an external persistent Interactive Control build cannot.

### Open-source builds

The 2026-09-26 owner decision selects GPL-3.0 for combined product distribution, preserving applicable Apache-2.0 and upstream notices under `LICENSING.md`. Corresponding-source delivery, third-party terms, the intended Apple distribution channel, and the separate Mac Companion/Jenny Media trademark policy require review before external release. GitHub private vulnerability reporting is the initial reporting channel; a company security address may later supplement or replace it. Because the remote repository is already public, further pushes and external contributions remain paused until those policies, a full-history review, and provider-side branch/secret/push protections are complete.

Publishing source does not publish Jenny Media's binary identity. Official Mac Companion releases alone use the Jenny Media bundle IDs, managed entitlement, Developer ID identity, notarization records, Sparkle feed, and App Store listing. A fork must choose its own product and bundle identities, request its own Apple capabilities, sign its own binaries, and configure an independent update feed.

The repository may contain public keys, expected designated requirements for official verification, reproducible non-secret build logic, and release evidence formats. It must not contain Developer ID or distribution private keys, provisioning profiles, managed-entitlement profiles, notarization credentials, Sparkle private keys, App Store API keys, or a default configuration that lets an unofficial build consume the official update channel.

## 3. Shipped component boundary

`Mac Companion.app` contains and signs as one release unit:

- Persistent menu-bar app and settings UI
- Embedded per-user LaunchAgent executable
- Authenticated local IPC services selected in Stage 0
- Shared protocol and domain libraries
- Diagnostic CLI, if retained, as a signed bundle resource rather than a root-installed binary
- Sparkle framework and only its required services

The first release does not install a privileged helper, system daemon, kernel extension, system extension, packet tunnel, SSH key, or file under `/usr/local`. MacTools remains a separate application; a future bridge authenticates its installed identity and is not copied into its bundle.

All embedded code is signed before the outer app. The outer app is then signed once, verified recursively without relying on an unsafe blanket deep-signing repair, notarized, stapled, and tested from the exact downloaded artifact.

## 4. Capability, entitlement, and privacy ownership

The Stage 0 permission matrix must confirm the final target ownership. The baseline is:

| Capability | Executing target | Release requirement | User-facing behavior |
| --- | --- | --- | --- |
| Persistent display capture | Menu app | Managed Persistent Content Capture entitlement, provisioning profile, usage description, Screen Recording consent | Explain before the system prompt; show readiness and recovery in settings. |
| Accessibility focus observation | Menu app | Accessibility authorization and a privacy-filtered metadata adapter | Explain focus-assisted framing separately; prove stale-element, secure-field, and revocation behavior. |
| Mouse and keyboard injection | Menu app | Post-event authorization as required by supported macOS; no TCC bypass and no unnecessary Input Monitoring request | Explain exact control, deep-link to System Settings where supported, release all input on loss, and recheck after revocation. |
| System appearance | None in MVP | No Automation entitlement or Apple Events usage description for this rejected action | Do not advertise the three-state action; a future menu-owned light/dark Automation capability requires separate product, permission, and distribution review. |
| Private-network listener | LaunchAgent | Minimal network entitlement only if the selected sandbox requires it | Bind to selected private interfaces; never make discovery equal trust. |
| Bonjour discovery | LaunchAgent and iOS app | One declared Bonjour service type and applicable Local Network usage descriptions | Explain local discovery and provide denial recovery. |
| Pairing-code camera | iOS app | Camera usage description and foreground VisionKit QR scanning | Ask only after explicit Scan; accept one bounded Mac Companion candidate, stop immediately, and keep canonical/expiry verification in the pairing authority. |
| Device and approval keys | iOS app | Keychain and Secure Enclave access-control configuration | Pairing identity and fresh approval identity remain separate. |
| Host identity and grants | LaunchAgent | Keychain access and service-owned protected database | Menu app receives bounded views over authenticated IPC, not direct database access. |
| Agent login item | Containing Mac app | Embedded, signed `SMAppService.agent` registration | User enables the agent explicitly and can disable it from both Mac Companion and System Settings. |
| Visible menu app at login | Containing Mac app | `SMAppService.mainApp` or a Stage 0-proven equivalent | Closing settings preserves the status item; intentional Quit and Disable is distinct from crash recovery. |
| Automatic updates | Menu app | Sparkle public Ed25519 key, HTTPS appcast, signed update archives | Never replace the app during an active control session without explicit termination. |

TCC grants belong to the code identity that performs the protected action. Stage 0 must verify attribution on clean machines; it must not move capture or input into the network agent merely to simplify prompts.

The normative [Apple privacy-manifest profile](../spec/privacy-manifest/v0/profile.md)
owns a separate candidate `PrivacyInfo.xcprivacy` resource for the iOS app,
Mac containing app, and embedded Agent service. The current no-relay,
no-analytics architecture declares no developer collection, tracking, or
tracking domains. The iOS target graph declares no required-reason API use;
macOS-only covered calls remain source-inventoried even though Apple's current
required-reason platform list does not include macOS. A dependency, telemetry,
data-flow, covered-API, executable-topology, or Apple-catalog change requires a
policy review before admission. Permanent targets must copy the indexed
resource into each final executable bundle and retain the built-bundle proof.

The first direct Mac build is not App Sandbox-enabled unless the Stage 0 lifecycle spike proves that sandboxing does not break the listener, IPC, updater, capture, input, or MacTools boundary. Hardened Runtime remains mandatory either way, and each exception requires a written reason.

## 5. Mac installation and onboarding

The clean-user path is:

1. Download the HTTPS-served, notarized DMG.
2. Drag `Mac Companion.app` to Applications and open it through normal Gatekeeper flow.
3. Verify the application identity and show a short product boundary: private route, no vendor relay, logged-in user required.
4. Ask the user to enable the per-user agent. Verify `SMAppService` state and explain recovery if the login item is disabled.
5. Establish the local authenticated IPC relationship and show agent health.
6. Request Local Network access only when the user starts pairing or discovery.
7. Pair an iPhone or iPad with Monitor Only by default.
8. Request Screen Recording, Accessibility observation, and post-event control only when the user explicitly enables the corresponding Interactive Control behavior for a named device; verify each grant and recovery independently.
9. Confirm the visible status item, local suspend action, grants, and uninstall location.

Onboarding never asks for an SSH password, administrator password, Tailscale credentials, Apple ID, or Mac Companion account. Tailscale guidance assumes the user installs and owns Tailscale separately; Mac Companion stores only the private endpoint needed to reach the already-paired host.

## 6. Mac update design

The normative [update trust policy](../spec/update-policy/v0/profile.md) admits
only Sparkle `2.9.6`, pinned to full revision
`ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a`. Current upstream documentation
requires HTTPS, incrementing bundle versions, Ed25519-signed archives, and
Developer ID validation; signed feeds additionally require verification before
archive extraction. The [completed provenance and topology audit](evidence/2026-08-23-sparkle-provenance-and-topology-audit.md)
binds the exact upstream manifest, binary archive, shared license, archive
shape, privacy behavior, and signed-code acquisition graph. The
[exact dependency admission](evidence/2026-08-23-exact-sparkle-dependency-admission.md)
now pins that version and revision in the shared lockfile, disables static
profiling, embeds Sparkle only in the containing app, removes both unused XPC
services from non-sandboxed archives, excludes release tools, and verifies the
retained unsigned topology. The permanent updater adapter must additionally
disable runtime profiling and custom feed parameters; the
[inert adapter checkpoint](evidence/2026-08-23-inert-sparkle-runtime-adapter.md)
now does so while admitting only explicit informational probes behind complete
release-injected authority. Download and installation remain disconnected from
the UI until the runtime installation authority controls one exact handoff.
Signed archive builds must re-sign and inspect every retained nested object.
The [nested Developer ID packaging checkpoint](evidence/2026-08-23-sparkle-nested-developer-id-packaging.md)
now proves this for the containing app, Agent, Sparkle framework, `Autoupdate`,
and `Updater.app`; an outer `codesign --deep` result is not accepted as a
substitute for those exact per-subject checks. See
[Sparkle documentation](https://sparkle-project.org/documentation/) and the
[2.9.6 release](https://github.com/sparkle-project/Sparkle/releases/tag/2.9.6).
The [signed-publication binding](evidence/2026-08-23-signed-update-publication-binding.md)
now retains successful signed-appcast validation, archive length, and the exact
Ed25519 signature in the reviewed candidate and requires exact correlation
before admission. Sparkle's installer-start callback cannot independently
attest the required Jenny Media Developer ID graph or Apple notarization; the
release lane must publish protected evidence for those facts and the runtime
bridge must bind it to the same archive before installation authority opens.
The [release-evidence projection](evidence/2026-08-23-update-release-evidence-projection.md)
now freezes the client side of that publication: 17 exact
`maccompanion`-namespaced enclosure attributes bind the signed-candidate
manifest, platform-signing record, two-phase notarization record,
packaging-equivalence receipt, archive digest, exact candidate, and four passed
release claims. It deliberately binds `signedCandidate`, not `promotionReady`,
because the final signed appcast is itself publication evidence and may not
participate in a circular content hash. The protected release job must still
generate and sign this projection from the real passing records.
The [validation-correlation checkpoint](evidence/2026-08-23-update-validation-correlation.md)
then retains that exact signed publication in a package-owned single-use actor.
It correlates one exact `willExtractUpdate` and matching `didExtractUpdate`, but
the latter is only an installer-start acknowledgement in Sparkle 2.9.6. Only
the later `showReadyToInstallAndRelaunch` user-driver event, after asynchronous
validation and stage-one preparation, can mint runtime admission. Candidate or
evidence substitution, callback reordering, cancellation, concurrency, and
reuse close the actor. The production adapter must subclass or proxy the
standard user driver and withhold `.install` until the foreground-confirmed
runtime coordinator succeeds. No protected publication, download, extraction,
or installation path is enabled yet.
The subsequent
[ready-to-install hold-point bridge](evidence/2026-08-23-sparkle-ready-holdpoint-bridge.md)
implements the chosen proxy shape in the permanent app. It forwards the
complete standard user-driver surface, serializes exact item-bearing delegate
callbacks into the package actor, and intercepts the post-validation readiness
reply. Until the real foreground/runtime owner is bound, it closes correlation
and answers `.skip`, which cancels the prepared installation rather than
allowing Sparkle's install-on-termination behavior. Full update checks and
downloads remain source-policy denied.
The subsequent
[update Agent reactivation saga](evidence/2026-08-23-update-agent-reactivation-saga.md)
defines the safe KeepAlive transition. It binds a durable recovery receipt to
the exact source/candidate builds before completed Agent unregister, retains it
through updater handoff, repairs the source build after failure, and lets only
the exact installed source or candidate build re-register and verify its Agent
before clearing the receipt. All effects remain injected until the private
atomic store, ServiceManagement adapter, and authenticated readiness observer
are bound.
The subsequent
[atomic update Agent reactivation store](evidence/2026-08-23-atomic-update-agent-reactivation-store.md)
implements that receipt under the menu app's private Application Support root.
It uses canonical bounded JSON, exact compare-and-swap, a process-shared lock,
no-follow descriptor inspection, private modes, atomic rename, and file plus
directory durability barriers. Pre/post-rename and post-clear fault tests prove
readback convergence. App construction and real platform/readiness bindings
remain closed.
The subsequent
[update Agent startup-repair binding](evidence/2026-08-23-update-agent-startup-repair-binding.md)
wires the permanent containing app to that exact store, the converging
ServiceManagement owner, and a bounded startup-only authenticated Agent-build
probe. It executes before route reconciliation and dashboard construction and
keeps both closed on uncertainty. Runtime update shutdown must still consume
the existing dashboard lifetime's authenticated build; it may not reuse this
startup probe.
The subsequent
[active-dashboard Agent build lifetime](evidence/2026-08-23-active-dashboard-agent-build-lifetime.md)
binds the reciprocal hello build to exactly one dashboard connection and the
future update Agent-stop owner. Only the package local-XPC binding can publish
or retire it; app and updater code can only read it. This removes the last
temptation to probe a second XPC connection during shutdown, but it does not
yet supply network-admission close, bounded drain, or updater handoff effects.
The subsequent
[reversible update network-quiescence checkpoint](evidence/2026-08-23-reversible-update-network-quiescence.md)
now binds exact close, drain, and recovery-only reopen effects through the
existing authenticated dashboard generation. The Agent listener stops new and
pre-established ingress before draining active primary, pairing, media, and
input roles; advertisement and route readiness remain withheld until a safe
nonterminal reopen. The containing-app composition orders those effects around
the existing Agent-stop saga and requires Agent recovery before it can rebuild
an authenticated dashboard and reopen after a post-stop failure. It accepts no
feed, archive, or general Sparkle authority, so the permanent user driver still
returns `.skip` and no update can install.
The subsequent
[dashboard update reconciliation checkpoint](evidence/2026-08-23-update-dashboard-reconciliation.md)
binds the active dashboard itself as the typed close/drain command channel and
the process router as the recovery owner. Recovery is single-flight, retries a
known authenticated generation only for an explicit command failure, replaces
an unavailable or transport-ambiguous current generation immediately, and
permits at most one newly authenticated replacement with a 40-attempt,
250-millisecond readiness cadence. Agent registration loss, a second ambiguous
generation, exhaustion, cancellation, or lifecycle loss stays closed. These
closures remain inert at construction and the app still has no prepared-
installer adapter, feed, archive, or installation authority.
The subsequent
[one-shot prepared-installer reply checkpoint](evidence/2026-08-23-one-shot-prepared-installer-reply.md)
adds a main-actor reply owner that satisfies only the coordinator's final
prepared-installer effect. It resolves install exactly once, resolves ordinary
cancel or owner loss to skip, and rejects reuse. The Sparkle ready callback now
constructs this typed owner, but the permanent adapter still cancels it because
foreground confirmation and runtime coordination are not yet bound. Source
validation permits exactly one install token in the closed install/skip mapping
and rejects any direct app invocation, so full update checks and installation
remain unreachable.
The subsequent
[foreground update-installation owner checkpoint](evidence/2026-08-23-foreground-update-installation-owner.md)
adds one main-actor lifecycle around the same reply owner and runtime
coordinator. It serializes fresh confirmation, cancellation, foreground loss,
shutdown, recovery, and terminal presentation; a suspended confirmation cannot
cross cancellation or foreground loss. Control-active, cleanup-uncertain,
runtime-failure, and recovery-failure results remain closed and sanitized.
Construction is effect-free, and this package owner is not yet installed in
the permanent Sparkle adapter, so full checks and installation remain
unreachable.
The subsequent
[inert permanent update-runtime composition checkpoint](evidence/2026-08-23-inert-permanent-update-runtime-composition.md)
projects the validated candidate build directly through single-use admission,
binds it to the existing Agent-stop owner, requires the current dashboard for
close/drain, and observes foreground plus visible Control state without
inference. Stopping Control maps to cleanup-uncertain, and an invalid monotonic
clock fails with `-1` at the package authority. The permanent app retains this
composition, but the Sparkle callback does not invoke it; confirmation UI and
termination deferral remain the next binding gate.
The subsequent
[ordered application-termination barrier checkpoint](evidence/2026-08-23-ordered-update-termination-barrier.md)
replaces best-effort quit cleanup with AppKit's `terminateLater` contract. The
package owner cancels a pre-shutdown decision or closes foreground authority
and waits through minimum-scope recovery during shutdown. The permanent app
cancels and joins any update-validation task, then finishes the product before
replying to AppKit. The Sparkle callback remains unbound; future installation
state must join the same barrier before that binding is admitted.

### Channels

- `internal`: development-signed and local-team-only artifacts; never offered to customers
- `beta`: notarized Developer ID builds for invited testers, with an explicit pre-release label
- `stable`: notarized public builds promoted only after beta gates pass

Beta and stable use distinct signed appcast URLs. A client never moves to beta without a local choice. Returning from beta to stable is an explicit supported migration, not a version-number trick.

### Trust and key custody

- Appcast and archives are served only over HTTPS.
- Every update archive has a Sparkle Ed25519 signature verified by the public key embedded in the app.
- Every executable retains the expected Jenny Media LLC Developer ID identity and hardened runtime.
- The final artifact is notarized and its ticket is stapled before publication.
- The Sparkle private key and Apple release credentials are stored outside the repository in controlled Keychain or CI secret storage, with documented recovery owners.
- A signer-rotation release changes only one trust anchor at a time and is tested from the oldest supported release.
- Update metadata rejects downgrades unless a separately signed emergency procedure authorizes a known-safe target.

### Compatibility and choreography

Every component publishes application version, protocol range, database schema, and local IPC version. The agent and menu app refuse an unsafe mixed-version control path while preserving a recoverable administration surface.

Before installation the menu app:

1. Stops accepting new Interactive Control and semantic operations.
2. Presents and records the update transition.
3. Refuses installation while Interactive Control is active or cleanup is
   uncertain; after the user stops it, verifies input release and capture stop,
   then asks the Agent to drain bounded operations.
4. Verifies that durable security state is committed.
5. Allows Sparkle to replace the complete containing app bundle atomically.
6. Relaunches, revalidates the embedded agent identity, and reconciles `SMAppService` registration.
7. Runs forward-only database migration in a transaction and reports any recoverable failure.

The exact runtime effect order is network admission close, active connection
drain, converged Agent stop, and one prepared-installer handoff. A failure
before Agent stop reconciles through the current known-live session or a
replacement authenticated generation after transport ambiguity. A failure
after Agent stop restores and verifies the source Agent before creating a
replacement authenticated session and reopening admission. Unknown transport
outcome never skips that recovery boundary.

Dashboard reconciliation is single-flight and owns routing while active. An
explicit command rejection on the retained authenticated generation is retried;
an unavailable or ambiguous retained transport is retired immediately. Only
one replacement generation may be created, only while the login role remains
enabled, and it gets at most 40 readiness attempts spaced 250 milliseconds
apart. Replacement ambiguity, exhaustion, registration loss, cancellation, or
application finish leaves network admission closed.

The update never swaps an individual agent executable in place. Pairing keys and grants remain in Keychain and service-owned data rather than in the replaceable bundle. A rollback must understand the stored schema or refuse with a clear recovery path; silently reading a newer schema is forbidden.

The [exact update candidate admission](evidence/2026-08-23-exact-update-candidate-admission.md)
separates the informational feed observation from later updater validation and
requires exact channel, build, display-version, and archive-URL correlation plus
every trust fact before issuing one runtime authority. A rejected, cancelled,
or consumed observation cannot be reused. The subsequent
[runtime shutdown coordinator](evidence/2026-08-23-update-runtime-shutdown-orchestration.md)
is the only public production consumer of that authority and completes its
recorded recovery scope before returning any failed attempt.

Automatic checks and download may be offered later; the initial beta keeps both
off. Initial beta installs require a fresh
five-minute local foreground confirmation that is cancelled when the menu app
loses foreground state. This prevents a locked Mac from retaining installation
authority without claiming an undocumented exact lock-state API. Installation
also requires Interactive Control to be inactive and unambiguous, network
admission closed, bounded work drained, and the Agent stopped.

## 7. iPhone and iPad distribution

### Alpha and beta

- Use internal TestFlight for the engineering team and first physical-device matrix.
- Use external TestFlight only after App Review beta information accurately describes the Mac companion requirement, private-network model, Screen Recording use, and absence of a relay.
- Pair TestFlight cohorts with a specific minimum Mac beta version and compatibility range.
- Keep the app foreground-first and avoid background-mode declarations that do not match an Apple-defined use case.

### App Store release

The iOS listing and review notes must state:

- A separately downloaded, signed Mac Companion app is required.
- The user's devices communicate directly over LAN or their own private route.
- Mac Companion does not provide internet reachability, wake, or background alerts.
- Mac Companion is a generic companion for a user-owned Mac: Observe and Act can work without capture, while Control can mirror the full desktop or generically focus an application or window.
- All mirrored software executes and renders on the Mac. The iOS client does not offer a software catalog, remote installation, or a thin client to a hosted cloud Mac.
- Interactive Control requires a logged-in Mac, a local device-specific grant, macOS Screen Recording and Accessibility permissions, and fresh phone user presence.
- Lock-screen operation is described only if the supported public-API matrix proves it.

Before external TestFlight, record an App Review strategy for Guidelines 4.2.3(i) and 4.2.7 plus the system ScreenCaptureKit picker recommendation. The required Mac companion, Observe/Act APIs beyond streaming, and private-route operation are explicit review risks. The first external review build is LAN-first, keeps full Desktop first-class, demonstrates a generic user-owned host mirror before App or Window Focus, supplies the notarized Mac download and complete reviewer pairing resources, and does not imply that Tailscale satisfies a LAN-only interpretation. Review notes explain how the approved Persistent Content Capture entitlement and local Mac consent support remotely initiated surface changes. Existing third-party approvals are market evidence, not a guarantee that Apple will classify Mac Companion the same way.

The candidate-bound metadata, reviewer instructions, attachments, prerequisite
checklist, and rejection decision path live in the [external TestFlight review
package](testflight-review-package.md). It is a prepared draft only; no field is
copied into App Store Connect while a placeholder or readiness item remains.

App privacy answers are derived from actual data flows. Under Apple's
developer-access definition, current real-time peer-to-peer traffic and
on-device records are not developer collection because neither Jenny Media LLC
nor a third party can access them. No telemetry or account data is declared
merely as future intent, and no diagnostics upload occurs without an explicit
later design and a prior privacy-policy/manifest revision.

### Direct-client commercialization decision, 2026-10-05

The current MVP is one iOS client using built-in macOS Screen Sharing/Remote Login,
with no Mac Companion host/helper. The approved model is a permanent basic free
tier and one non-consumable **Lifetime Pro** purchase, with no subscription/account.
Free includes one Mac, one SSH key, unlimited session duration, Desktop/input/basic
Terminal, standard keyboard/number row, key import/export and connection/display
preferences. Pro adds multiple Macs/keys, remote public-key setup and custom
keyboard/actions/snippets. Extra existing records are preserved, with an explicit
choice of active free Mac/key; entitlement changes do not end active sessions.
StoreKit's verified current entitlements, updates and explicit Restore Purchases
control access. Local StoreKit testing does not activate a real store product.
The user approved a US base price of $9.99 and a free 14-day Pro trial. Apple
App Review guideline 3.1.1 permits a separate zero-price non-consumable named
14-day Trial for a non-subscription app. Its verified original purchase date anchors
expiry; restoring/reinstalling does not restart it. There is no automatic charge
or renewal. Basic access and saved data remain after expiry. The app displays the
localized lifetime price and expiring functionality before explicit trial enrollment.

App Store Connect app 6819496840 uses the existing iOS identifier
media.jenny.maccompanion.ios, registered under the already-confirmed team.
Lifetime Pro is product 6819497277 (media.jenny.maccompanion.pro.lifetime);
14-day Trial is 6819497930 (media.jenny.maccompanion.pro.trial14). Family Sharing
remains off. First purchases require an app-version review and are not live merely
because the records and price schedules are saved. The local StoreKit configuration
uses $9.99/$0.00 only for testing.

Security and accessibility are never paywalled. macOS account authorization and SSH
host-key trust remain independent of StoreKit. Existing legacy pairing/grants stay
inactive in the direct client. Client commerce gates are not a security boundary;
official distribution, updates, compatibility and support provide commercial value.

### Direct-client internal TestFlight decision, 2026-10-05

The user authorized the current normal direct iOS client for internal TestFlight
and their existing App Store Connect account as an internal tester. This permits
Apple distribution signing/provisioning for the existing app and session widget,
and an optimized internal archive. Use Xcode's TestFlight Internal Only method
(`testFlightInternalTestingOnly = true`) so this artifact cannot be reused for
external testing or App Store release. Keep the dependency report's
`releaseAdmitted = false`; public release admission and review remain separate.
No new Mac component, developer user, API key or signing private key is required.

## 8. Release pipeline and evidence

Stage 0 defines the reproducible, non-secret build, verification, packaging, and evidence-manifest command skeleton needed by its own release-shaped experiments. Publication credentials and promotion automation are added only after those commands are proven. The release pipeline must produce and retain:

The normative [release evidence v0.2 profile](../spec/release-evidence/v0/profile.md)
and its validator make `unsignedConstruction`, `signedCandidate`, and
`promotionReady` distinct machine-checked claims. A lower claim cannot carry
promotion evidence, and a higher claim cannot omit or placeholder the evidence
listed below. The manifest records references and public verification results;
it never embeds credentials. Every referenced file is path/size/SHA-256 bound,
and a release job uses `--verify-files` against the retained bundle before
promotion. The unsigned generator records the current source and toolchain but
cannot create a signed-candidate or promotion-ready claim.

- Clean build log with exact Xcode and SDK versions
- Test and protocol-fixture results
- Component version and compatibility manifest
- Signed `.app`, update archive, and DMG checksums
- Expanded entitlements and designated requirements for every executable
- Descriptor-bound complete Mach-O/bundle/architecture discovery graph for the
  exact application ZIP and xcarchive, with every Apple verification step
  still explicitly `notRun` until the protected platform lane executes it
- Canonical signing policy whose exact SHA-256 is supplied independently by the
  protected release runner and whose object, slice, signer, requirement,
  third-party, runtime, timestamp, and entitlement rules bind exactly to that
  release, SBOM, and graph
- `codesign` and Gatekeeper verification results
- Notary submission ID, accepted log, and stapling verification
- Software bill of materials and dependency licenses
- Sparkle appcast entry and signature evidence
- Human release approval, channel, and publication time
- Clean-install, upgrade, rollback, permission-revocation, and complete-uninstall results on physical Macs

The protected Mac update lane records `upgrade` and `rollback` through one
canonical [Mac update physical-evidence profile](../spec/mac-update-physical-evidence/v0/profile.md).
Its twelve ordered cases bind denial and forced-loss recovery to the exact
source build, successful/clean-user/no-background-network behavior to the exact
candidate build, and every observation to distinct retained bytes. This closes
the evidence shape but does not replace execution on signed physical machines.
The remaining four Mac promotion scenarios similarly share the canonical
[Mac lifecycle physical-evidence profile](../spec/mac-lifecycle-physical-evidence/v0/profile.md),
which fixes quarantine/Gatekeeper, clean enablement/readiness, permission-
revocation denial, and complete-uninstall assertions plus exact terminal state.
The iOS promotion lane shares one canonical
[iOS physical-evidence profile](../spec/ios-physical-evidence/v0/profile.md)
across physical pairing, Local Network denial/recovery, and background
reconnect. It includes one consented `setAudioMuted` operation and proves that
backgrounding cannot replay work or silently restore Control.

CI is split into three trust lanes:

- **Public pull request:** unsigned package builds, fixture conformance, dependency-boundary checks, linting, and tests with no Apple or publication secrets.
- **Trusted internal:** development-signed Apple targets and controlled physical-device evidence; artifacts are never promoted automatically.
- **Tagged release:** protected Developer ID/App Store signing, notarization, Sparkle signatures, checksums, the [exact-candidate artifact SBOM](../spec/artifact-sbom/v0/profile.md) derived from the packaged executable-bearing ZIPs, the independently pinned [signing policy](../spec/signing-policy/v0/profile.md), the fixed-tool [platform signing evidence](../spec/platform-signing-evidence/v0/profile.md), the [Mac packaging-equivalence receipt](../spec/mac-packaging-equivalence/v0/profile.md) produced by explicit read-only reinspection of the exact DMG, reviewed license evidence, and an explicit human promotion record. The deterministic source dependency SPDX document is an input, not a substitute for artifact inspection. Promotion revalidates the policy, platform record, receipt, ZIPs, and DMG after platform inspection; schema-only, synthetic, beta-toolchain, or attach-free evidence cannot make a signed-candidate claim.

A pull request build cannot publish. Stable publication requires a tagged revision, protected release credentials, and a separate promotion approval. CI logs must never print private signing keys, one-time notarization credentials, pairing material, or live provisioning profiles.

The local trusted lane begins with an already Developer ID-signed `.xcarchive`.
`scripts/package_mac_release.py` verifies the exact official app, Agent,
Sparkle framework, `Autoupdate`, and `Updater.app` identities; requires their
Developer ID authority, timestamps, hardened runtime, and one common team; and
rejects a missing, substituted, ad-hoc, cross-team, or XPC-bearing topology. It
then produces the canonical app and update ZIPs, creates an APFS/UDZO DMG with
`diskutil image create from`, signs that DMG, and publishes a no-overwrite
local directory. Its summary must retain `notarized`, `stapled`,
`sparkleArchiveSigned`, and `promotionReady` as false. The artifact-SBOM and
packaging-equivalence generators then inspect those outputs independently.
Notarization and every later promotion action remain separate, explicitly
authorized commands.

The permanent menu updater now contains the final foreground decision seam:
after exact signed-candidate validation reaches Sparkle's held readiness point,
it can present `Not Now` and `Install and Restart`, and only the latter may ask
the package-owned shutdown coordinator to close sessions, stop the Agent, and
resolve the one-shot installer reply. This source binding does not enable a
shipping update path by default. The tracked empty
`MacCompanionUpdateUserInitiatedCheckProfile` leaves the visible action
information-only. A protected two-version evidence build may inject only the
exact `maccompanion.user-initiated-full-update-check.v1` profile to make that
same foreground action stage an update. Automatic and background checks remain
disabled. No externally distributed beta may carry the full-check profile
until signed old-to-new installation, foreground-loss, forced-loss recovery,
rollback, and clean-machine evidence is retained and the release manifest
binds that exact profile. Release-evidence v0.2 now performs that binding by
reading the exact canonical application archive's bounded `Info.plist`; this
source gate does not replace the still-required signed physical matrix.

## 9. Versioning and compatibility policy

- User-visible app releases use semantic product versions.
- `CFBundleVersion` is monotonically increasing across every distributed build in a channel.
- Protocol major versions are incompatible; minor features negotiate explicitly.
- At least the current stable Mac and iOS client versions interoperate during staged rollout.
- Security revocation can raise the minimum accepted version with an explicit user explanation.
- Provider contracts and database schemas version independently from the app presentation.
- The oldest supported stable release is included in update and migration tests.

The first public support policy targets only macOS 26.x and iOS/iPadOS 26.x. Each annual platform release triggers a decision to advance the minimum or carry one prior major version based on measured support cost and adoption; the project does not promise indefinite backward compatibility.

## 10. Uninstall and recovery

The Mac app provides `Disable and Remove Mac Companion Data` before the user deletes the app. It:

- Suspends access and advances all authorization epochs
- Ends sessions and operations safely
- Unregisters both the per-user agent and the menu app's login launch
- Revokes pairings and removes durable grants, audit, operations, saved endpoints, and host keys after confirmation
- Explains which macOS privacy grants may remain visible in System Settings and how to remove them
- Leaves no privileged helper or copied executable because none was installed

Deleting only the app is detected as an incomplete uninstall case in testing. Documentation provides a signed, non-destructive recovery route for a stale login-item registration. Reinstall does not silently inherit remote authorization unless protected retained state and product policy explicitly support recovery.

## 11. Go/no-go gates

### Ready for permanent release-shaped Apple targets

- Team ID is confirmed privately; the reverse-DNS prefix is fixed as `media.jenny`.
- Final target identifiers are registered.
- Developer ID certificate custody is verified.
- Stable Xcode 26.6 is installed and recorded.
- The process, entitlement, TCC, and update ownership in this document has no unresolved boundary change.

The final Mac App ID is registered. Completing the Persistent Content Capture request now waits only on Apple's required App Store URL/Apple ID path for this unreleased, directly distributed Mac app. Pending request status does not block non-capture permanent targets; approval gates the release entitlement/profile and external persistent Control builds.

The registered containing-app identity and profile-capable Agent identity have
therefore advanced independently: the [containing-app target](evidence/2026-08-21-permanent-mac-containing-app-target.md)
and [Agent Keychain provisioning repair](evidence/2026-08-23-agent-keychain-provisioning-repair.md)
prove the non-capture bundle topology, exact distinct signed identifiers,
private Agent Keychain group, and privacy ownership on Xcode 27 beta. The
checklist above still gates the explicit Agent Developer ID profile, remaining
Apple targets, and final release evidence; this proof does not waive
stable-toolchain, authenticated lifecycle, notarization, packaging, or
clean-machine requirements.

The [permanent iOS application target](evidence/2026-08-22-permanent-ios-application-target.md)
now fixes `media.jenny.maccompanion.ios`, iOS/iPadOS 26.0, the exact permission
declarations, and the indexed privacy resource in a generated release-shaped
bundle. The [release application composition](evidence/2026-08-22-permanent-ios-release-composition.md)
now binds protected QR/SAS pairing, crash-recoverable first-route provenance,
configured no-relay reconnect, and the first-party Observe, Approved Actions,
and separately authorized Remote Control workspace into that target. The build
remains unsigned; App ID registration, provisioning, signed device launch,
physical permission/network evidence, TestFlight, and final privacy/submission
inspection remain promotion gates.

### Ready for external Mac alpha

- Developer ID signing, hardened runtime, notarization, stapling, Gatekeeper, DMG, Sparkle, and clean uninstall pass on clean physical Macs.
- The agent survives expected lifecycle transitions and cannot outlive local disablement.
- The update path safely drains active work and preserves or refuses database state.
- A revoked or expired signing/provisioning scenario has a documented recovery plan.

### Ready for external Interactive Control beta

- Apple's managed entitlement is approved for the shipped App ID, or a documented public alternative passes equivalent review.
- Screen Recording, Persistent Content Capture, Accessibility observation, and post-event input onboarding and revocation are independently verified on every supported OS version.
- Locked behavior matches the published contract exactly.
- A security review has no unresolved critical finding in signing, update, local IPC, or Interactive Control.

### Ready for public release

- Mac download and iOS App Store metadata describe the same compatibility and privacy model.
- Beta-to-stable and stable-to-next-stable upgrades pass from the oldest supported version.
- Signing-key owners, rotation, incident response, compromised-release response, and update-feed recovery are assigned.
- A user can install, pair, understand permissions, update, suspend, revoke, and completely uninstall without engineering help.
