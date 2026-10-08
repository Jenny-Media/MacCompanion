# Session controls, login and private network routes

## Scope and network diagnosis

The user approved multiple addresses per Mac, an advanced port, a clearer login
screen, adjustable trackpad speed, saved display selection, issue-only status,
and a floating glass controls menu with primary press-and-slide and customizable
shortcuts/text. The normal iOS client still connects directly to built-in macOS
Screen Sharing. No Mac app/helper, new pairing or authentication is introduced.

The user reports Tailscale IPv6 works. The previous IPv4 endpoint filter rejected
100.64.0.0/10, including Tailscale addresses, before TCP connection. This is a
confirmed source defect. The corrected filter permits shared-address-space
endpoints while preserving public/unspecified/multicast rejection and exact
resolved-sockaddr use. Current Mac Tailscale reports Running/online; a local TCP
probe to its own Tailscale IPv4 port 5900 succeeds. A self-IPv6 probe times out;
neither self probe verifies the iPhone's VPN route. After installation, the user
confirms the requested iPhone IPv4 connection and press-slide menu test works.
No endpoint, peer list, account identity or credentials are retained.

## Implementation

- Direct library schema 2 stores 1–8 explicitly configured, ordered addresses and
  port 1–65535 (default 5900). Version-1 records retain UUIDs and saved logins.
  Local/private-VPN fallback happens only before the first TCP success. It never
  tries credentials against further addresses after a protocol/login failure.
  DNS/TCP waits remain bounded and cancellable. Editor addresses can be reordered.
- Logins remain scoped to the Mac UUID in the existing non-synchronizing,
  device-local Keychain service. Different Macs do not share one app-wide login.
  Native Passwords/1Password selection is separate: associated-domain AutoFill
  cannot reliably identify arbitrary Screen Sharing hosts. The selected Mac is
  prominent; username/password AutoFill, password visibility and per-Mac Save
  Login remain available. Route/port changes clear the saved login; rename and
  reorder preserve it. Invalid fields and retention failures remain visible.
- Login/progress shows actual contacting, signing-in and opening-desktop phases,
  with Cancel. Connected presentation waits for a fresh frame; metadata alone
  cannot admit initial or resumed pixels. Healthy sessions omit Connected text.
- One bottom-right native Liquid Glass button opens quick actions and Displays,
  Input, Extra Keys/Gestures and Session categories. The keyboard/modifier strip
  remains directly available. Hold, slide and release is primary, with highlight
  and haptics. Outside/cancel/background cannot trigger an action or remote input.
  Tap/accessibility equivalents remain. Exit to My Macs uses a deliberate tap.
  Portrait, landscape and keyboard panel bounds are checked.
- Trackpad accumulates incremental deltas, normalized by backing/logical scale,
  with bounded velocity acceleration. Per-Mac speed is adjustable from 0.5 to 3,
  default 1.5, independently of local zoom. Mouse mode is also remembered.
- A saved display ID restores only against verified current metadata and frame
  geometry. Missing/incompatible bounds retain All Displays; explicit All
  Displays clears the saved ID. This does not reconnect or alter Mac displays.
- Quick actions can be hidden, reordered and customized with modifier chords or
  text up to 256 Unicode scalars. Custom content uses a separate local,
  non-synchronizing WhenUnlockedThisDeviceOnly Keychain entry per Mac. Unreadable
  entries are preserved, not overwritten with default actions. Text is sent as
  balanced key events rather than a clipboard operation. Custom actions enter
  the input queue as one complete batch; a busy queue rejects the whole batch
  with a retryable issue instead of partial text or disconnect. Modifiers clear.
  Background/recovering sessions cannot send custom actions. Content never
  enters diagnostics or ActivityKit.

The normative direct profile and its existing manifest-indexed fixture were
updated before endpoint/input admission changes. No second fixture index or
cryptographic scheme was added. Test harness code remains under Experiments and
is absent from the generated normal application target.

## Verification and installation

Toolchain: `/Applications/Xcode.app`, Xcode 27.0, build 27A266a.

- Hosted native/Swift suite: **33 passed, 0 failed, 0 skipped** at
  `/private/tmp/maccompanion-controls-queue-tests-20261004.xcresult`.
  Includes actual TCP fallback/custom-port connection, schema migration,
  credential deletion boundaries, per-Mac preference/content isolation,
  preservation of damaged synthetic Keychain entries, press-slide release and
  cancellation, accelerated deltas, verified saved display fallback, balanced
  shortcut/text batches, nonfatal busy queue, first-frame status fencing, and
  existing actual native owner/ActivityKit/parser/viewport/cursor tests.
- Required `bash scripts/validate.sh`: exit 0. Private output:
  `/private/tmp/maccompanion-controls-required-validation-20261004.log`.
  Restricted reruns initially failed Swift manifest evaluation in dependency
  policy; the identical command passes with access to the Xcode caches.
- Rendered Simulator checks: focused selected-Mac login, Add Mac with preferred
  and fallback fields and advanced 5900 port, and native glass controls over
  synthetic desktop colors. The hosted display-picker preview also uses only
  synthetic geometry. Preview attachments remain in private temporary output.
- Normal iPhone build and source-input verification pass; 480 input hashes match
  the final checkout. Build report:
  `/private/tmp/maccompanion-controls-device-20261004/build-report.json`.
- Existing development device profile, signing identity, app Keychain group,
  matching extension version, and deep signatures pass. The ActivityKit
  extension still has no credential Keychain group. Signed application SHA256:
  `51563f184d540b70fc977a6a1a2e5a538a9dd4ff602ec4102dd3b9252c423a6c`.
- Update installed on iPhone 18 Pro Max, database sequence 8180, and launched
  successfully. No uninstall or real credential/content extraction occurred.
  Private install/launch reports:
  `/private/tmp/maccompanion-controls-install-20261004.json` and
  `/private/tmp/maccompanion-controls-launch-20261004.json`.

The user answers “it works” to the requested installed-iPhone test of the Mac's
Tailscale IPv4 connection and holding/sliding/releasing the controls button.
This verifies those physical acceptance items. Automatic fallback across an
unreachable route, multiple-machine Passwords/1Password selection, custom text/
shortcuts, perceived pointer speed, display restoration after a new session and
sustained reliability still need physical testing. Public release and
secure-transport admission remain separate gates.

## Primary references

- [Tailscale IP addresses](https://tailscale.com/docs/concepts/tailscale-ip-addresses)
- [Apple Password AutoFill workflow](https://developer.apple.com/documentation/security/about-the-password-autofill-workflow)
- [Apple native glass effects](https://developer.apple.com/documentation/uikit/uiglasseffect)
