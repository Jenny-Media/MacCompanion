# Competitive task matrix — 2026-08-23

Status: official-source desk research and product-decision input. This is not
hands-on validation, a security audit, or evidence of user demand. Product
behavior and prices can change; recheck them before pricing, launch, or public
comparative claims.

## Evidence rules

- **Published** means an official product site, App Store listing, or Apple
  support page explicitly makes the claim. It does not mean Mac Companion has
  reproduced it.
- **Not found** means the reviewed official material did not state the fact. It
  is not proof that the capability is absent.
- **Conflict** means official materials disagree. The product is treated as
  unverified until a clean-install hands-on test resolves the difference.
- No published source supplied a comparable measured time to first controllable
  frame. Setup descriptions below are only a friction proxy.

## Task-level overview

| Product | Availability and setup proxy | Route and trust model | Visual and input scope | Useful without video | Published price at review |
| --- | --- | --- | --- | --- | --- |
| [Helm](https://apps.apple.com/us/app/helm-mac-remote-controller/id6761204919) | Shipped iPhone app; enable macOS Remote Login, then discover the Mac with Bonjour and authenticate over SSH. No separate Mac app. | Same-LAN SSH, host-key verification, password stored in iOS Keychain; no product relay claimed. | Trackpad and keyboard shortcuts; screenshot rather than a live desktop stream. | Audio and power controls; Pro adds media, brightness, appearance, Bluetooth, app, browser-tab, storage, and screenshot controls. | Free; Helm Pro **US$4.99** in-app purchase. |
| [Cuevello](https://cuevello.app/) | Shipped Mac and iOS apps; grant Mac permissions, discover or scan QR, and confirm a short pairing code. | Local Bonjour or user VPN by default; optional self-hosted relay; end-to-end encryption and an extra-authorization mode are published. | Monitor, app, or window stream; touch, keyboard, app/window switching, and menu commands. | Workflows, files, clipboard, URLs, app actions, Shortcuts, widgets, Watch, and audio. | Mac app free; Cuevello Pro **US$8.99** one-time in-app purchase. |
| [MacReacher](https://macreacher.app/) | Public beta/trial; install the Mac host and viewer, approve the first device fingerprint, then authenticate with the Mac account. | Direct LAN or saved LAN/Tailscale candidates with route racing; no vendor relay claimed. | Full desktop, single app, Simulator, app switching, multi-monitor, virtual display, H.264 up to a published 60 fps, and multiple input modes. | Clipboard, audio, and files. | **£5/month**, **£29/year**, or **£99 lifetime**; viewers free. |
| [Apperture](https://runapperture.com/) | Shipped; grant Screen Recording and Accessibility, scan a single-use two-minute QR code, and approve on the Mac. | Private network only; Tailscale recommended; local approval and Keychain-held trust; no vendor relay claimed. | One selected Mac app/window, touch and keyboard, searchable menus, clipboard, and Simulator-specific touch/rotation. Secondary-dialog support is explicitly limited. | No general nonvisual operation surface found. | Mac host free; 15-connection trial; **US$24.99** launch lifetime purchase, with yearly pricing described as later. |
| [Tomaco](https://tomaco.app/) | Shipped; install both apps, grant Screen Recording and Accessibility, enter a pairing code, and approve on the Mac. | LAN discovery or user-managed Tailscale; peer-to-peer TLS-PSK and Secure Enclave device keys are published; no vendor relay claimed. | Conventional full desktop, multi-display, virtual display, local cursor, keyboard/mouse, audio, file and clipboard; up to a published 5K/120 Hz HEVC. | Files, clipboard, Wake-on-LAN, and connection utilities; no separate Observe/Act model found. | Free at 1080p/30; Tomaco Pro **US$19.99** one-time purchase. |
| [CommandDeck: Remote for Mac](https://apps.apple.com/us/app/commanddeck-remote-for-mac/id6774549798) | Shipped iPhone/iPad app plus free Mac menu app; same-LAN setup uses a one-time six-digit PIN. | Direct local Wi-Fi, no account, and no vendor-routed commands are published. | No live desktop stream; buttons, toggles, sliders, widgets, and community control packages. | Volume/media, app launch, keep awake, lock, display sleep/wake, Shortcuts, and scripts. | Free basic controls and 7-day Pro trial; **US$2.99/month**, **US$29.99/year**, or **US$79.99 lifetime**. |
| [Shellcove](https://apps.apple.com/us/app/shellcove-remote-coding/id6774076404) | Shipped; install the Mac companion, grant Screen Recording and Accessibility, then scan a QR code containing the pinned certificate and candidate routes. | LAN, Tailscale, or VPN; TLS with self-signed certificate pinning; no account, cloud, or analytics claimed. | Remote desktop plus keyboard, mouse, clipboard, explicit key-down/up, and terminal-oriented controls. | Window Text exposes focused-window text without video, plus iOS dictation and input methods. | **US$8.99** purchase. |
| [Apple Screen Sharing](https://support.apple.com/guide/mac-help/share-the-screen-of-another-mac-mh14066/mac) | Built into macOS; enable Screen Sharing, connect from another Mac, and authenticate with a Mac username/password or Apple Account where supported. | Apple-documented Mac-to-Mac connection; the reviewed page does not define a phone-first private-route workflow. | Observe or control full displays, scale or use dynamic resolution/HDR, and transfer clipboard/files. | No independent status or bounded-action surface found. | Included with macOS. |
| [Apple Remote Login / SSH](https://support.apple.com/guide/mac-help/allow-a-remote-computer-to-access-your-mac-mchlp1066/mac) | Built into macOS; enable Remote Login and select allowed users. | SSH/SFTP using a macOS account; optional Full Disk Access can broaden file visibility. Network routing is user supplied. | No live graphical desktop, app/window focus, touch mapping, or visual fallback. | Broad shell and file automation. | Included with macOS. |

All prices above are exact published storefront/site values captured on the
review date, not converted estimates. Currency, tax, trials, regional
availability, and launch discounts are not normalized.

## Permission, recovery, privacy, and support boundaries

| Product | Permission/onboarding observations | Recovery and diagnostics | Privacy and support boundary |
| --- | --- | --- | --- |
| Helm | Remote Login exposes a real macOS SSH account rather than a Mac-specific capability grant. This minimizes installation steps but inherits broad account authority. | Bonjour and ordinary SSH behavior are the main published mechanisms; product-specific authorization epochs, visible active-control state, and durable recovery semantics were not found. | “No cloud/no tracking” marketing sits beside an App Store privacy declaration listing identifiers, usage data, and diagnostics as not linked to the user. Treat the exact data path as unresolved, not as either claim being false. |
| Cuevello | Screen and input permissions plus QR/discovery pairing; an Extra Authorization mode is published. | Reconnect and pairing-reliability work appear in release notes, but a detailed fail-closed recovery/audit contract was not found. | App Store privacy says data is not collected. Optional self-hosted relay and broad workflows create a larger support surface than Mac Companion's MVP. |
| MacReacher | Screen Recording and Accessibility; Ed25519 first-device approval followed by real macOS account authentication and brute-force backoff. | Automatic route racing/fallback and explicit connection-end reasons are published. | No account or telemetry is claimed, with one routine license check. Headless/virtual display, files, audio, and credentials materially expand security and support scope. |
| Apperture | Screen Recording, Accessibility, iOS Local Network/camera, expiring QR, local approval, and either-side revocation. | Auto reconnect and adaptive quality are published. Official materials conflict on locked-Mac behavior: the site describes lock detection/reporting while App Store release notes claim Face ID wake/unlock. This requires physical validation and security review. | Site says a local 30-day history stores device, time, and app names but not keystrokes or frames; App Store privacy lists unlinked usage and diagnostic data. One-window behavior and dialog limitations narrow support scope. |
| Tomaco | Screen Recording, Accessibility, pairing code, and local Mac approval. | Adaptive networking and Wake-on-LAN are published; detailed authorization-recovery and audit behavior was not found. | App Store says no data is collected. Official materials disagree on Intel support while both state macOS 14+, so supported hardware should be verified before comparison. |
| CommandDeck | One-time local PIN pairing is published; the reviewed listing does not explain device-key identity, permission granularity, script containment, or package trust. | Release notes mention connection reliability, but a detailed authorization, recovery, or audit contract was not found. | App Store says no data is collected. Community packages, scripts, system controls, and Shortcuts are shipped breadth, but their security and support boundaries need hands-on review. The same-name [commanddeck.app](https://www.commanddeck.app/) site describes a different-looking, unreleased cross-platform “free forever” product; do not merge its claims with the App Store product. |
| Shellcove | Screen Recording, Accessibility, certificate-pinning QR, and route selection. | Automatic fastest-route selection plus manual route choice are published; detailed audit and crash-recovery semantics were not found. | App Store says no data is collected. Window Text is useful but transports app content and therefore exceeds Mac Companion's content-minimizing MVP policy. |
| Apple Screen Sharing | Screen Sharing permission plus Mac account access. | Apple documents connection and display behavior, but not Mac Companion-style paired-device grants, operation outcomes, or user-exported task diagnostics. | Full-display pixels, clipboard, and files are intentionally in scope. It is a generic Mac-to-Mac baseline, not a phone-first companion. |
| SSH | Remote Login permission and selected macOS users; Full Disk Access is a separate broadening switch. | Mature transport and shell tooling, but application-level task recovery is left to scripts and callers. | A shell account can exceed the authority needed for a specific remote task. It has no built-in capability schema, app/window revision fence, visible Control lifecycle, or content-minimizing audit. |

## Findings for Mac Companion

### Category parity

The following are necessary capabilities or quality bars, not a sufficient
positioning claim:

- direct LAN operation and user-managed Tailscale/private routes without a
  vendor relay;
- QR or short-code pairing with explicit Mac approval;
- hardware video, adaptive quality, touch/keyboard control, reconnect, and
  app/window focus;
- a full-desktop fallback and clear Screen Recording/Accessibility onboarding;
- privacy claims that are concrete enough to reconcile with the platform
  privacy declaration.

Single-app presentation is especially not unique: Cuevello, MacReacher, and
Apperture already publish versions of it. Performance numbers such as 5K/120
Hz are a conventional remote-desktop competition that Mac Companion should
measure honestly but not make its initial differentiation thesis.

### Differentiation hypothesis to test

Mac Companion should compete on the combination, not on any isolated feature:

1. **Observe, Act, and Control are independently useful.** A user can inspect
   trustworthy state or run one explicitly granted desired-state action without
   starting screen capture.
2. **Adaptive Control is revision-safe, not merely cropped video.** Desktop,
   App Focus, Window Focus, Smart Zoom, interaction mode, current target, and
   fallback state remain explicit and host-authoritative. Stale surface or
   authorization state cannot receive input.
3. **Authorization and recovery are product features.** Named-device grants,
   visible local activity, immediate suspension, conservative operation
   outcomes, and truthful stale/unreachable/locked/sleeping states should be
   easier to understand than a broad SSH account or an opaque reconnect loop.
4. **No relay does not mean hidden networking magic.** Mac Companion documents
   LAN and user-managed private-route responsibilities and distinguishes route,
   reachability, authentication, permission, lock, and sleep failures.

These are hypotheses until calibration and confirmatory cohorts demonstrate
repeated real jobs. Competitor breadth is not a reason to pull files,
clipboard, audio, shell, general workflows, or plugins into Stage 3.

### What to learn, and what not to copy

- Learn from Helm's small setup surface. Do not adopt SSH as the primary
  runtime: a macOS login account is broader than Mac Companion's named,
  separately granted Observe/Act/Control capabilities.
- Treat Cuevello and the shipped CommandDeck action/package model as signals
  that nonvisual workflows may matter. Stage 4 still waits for repeated
  Observe/Act jobs and one bounded provider need; marketplace breadth and
  arbitrary scripts are not evidence that Mac Companion should expose them.
- Learn from MacReacher's explicit connection-end reasons and route fallback.
  Do not inherit account-password, file, audio, virtual-display, or headless
  scope without separate Stage 6 evidence.
- Treat Apperture's conflicting locked-Mac claims as a warning: Mac Companion
  must report physical lock behavior exactly and never market an inferred
  unlock capability.
- Keep Shellcove's Window Text out of the MVP. It may be reconsidered only as a
  reviewed Stage 5 semantic surface with explicit content, secure-field, and
  retention boundaries.

## Hands-on calibration protocol

Desk research cannot establish time to first controllable frame, prompt order,
recovery quality, or whether published security language matches runtime
behavior. Before public comparative claims, test each eligible product on a
clean or reset Mac/phone pair without purchasing anything unless separately
authorized.

For each run, record with a stopwatch and content-free notes:

1. start at first launch/download complete;
2. record every Mac and iOS permission, account, QR/code, and local-approval
   step;
3. mark first authenticated connection, first visible frame, and first
   controllable frame separately;
4. complete one representative Desktop, app/window, keyboard, and nonvisual
   job when supported;
5. interrupt Wi-Fi, lock/unlock, sleep/wake, quit/relaunch, revoke, and switch
   between LAN and a user-managed private route;
6. record every ambiguous state, silent retry, unintended input risk, and
   physical return to the Mac;
7. distinguish `not supported`, `not found`, `failed`, and `conflicting` from a
   verified absence.

The same stopwatch and failure taxonomy must be used for Mac Companion. The
comparison is valid only on recorded product/OS versions and equivalent route
conditions.

## Stage 4–7 disposition after this review

| Stage | Current disposition | Re-entry evidence |
| --- | --- | --- |
| 4 — MacTools/provider contract | **Deferred.** Competitors indicate workflow demand, but the Stage 3 thesis can be tested with native `setAudioMuted` and the three first-party paths. | Confirmatory users repeatedly complete a nonvisual job; at least one required action is owned better by MacTools or another provider than by a narrow native adapter; the provider adds value without becoming a remote shell. |
| 5 — semantic/provider-native surfaces | **Deferred.** App/window streaming already covers the initial visual job, while focused text or Accessibility semantics would add content and stale-element risk. | A repeated job fails materially in App Focus/Window Focus/Smart Zoom, and a reviewed native/semantic surface demonstrates better completion with explicit secure/private-value fallback. |
| 6 — administrator capabilities | **Deferred independently per capability.** Competitor bundles do not justify inheriting shell, file, clipboard, audio, headless, wake, or pre-login authority. | For each capability: repeated job, local named-device grant, threat model, isolation boundary, revocation/audit design, physical failure evidence, and an independent security review. A pass for one capability does not reopen another. |
| 7 — assisted operation | **Deferred.** No Stage 3 job requires a model, and remote/provider content would introduce an untrusted-instruction boundary. | The direct workflow first proves demand; one assisted job has a measurable advantage; planner/capability separation, prompt-injection tests, data/retention policy, cost, and offline behavior pass review. |

These are evidence-backed deferrals, not permanent rejections. They satisfy the
current decision requirement while preserving narrow re-entry gates and keep
the implementation goal focused on a signed, usable, no-relay Stage 3 beta.
