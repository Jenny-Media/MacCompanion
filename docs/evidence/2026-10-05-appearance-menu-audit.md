# Appearance and menu audit

Scope: user approved real light/dark appearance and an audit/reorganization of all
active direct-client menus. Legacy helper/paired-product menus remain inactive.

## Audit and changes

| Surface | Finding | Implemented organization |
| --- | --- | --- |
| My Macs menu | Connect modes and credential removals mixed with management | Connect: Desktop, Trackpad & Keyboard, Terminal. Manage Mac: Edit, Remove. |
| Edit Mac | Credential removals duplicated in the root menu; SSH errors ignored | One Saved Logins & Server Trust section, separate confirmations, visible errors. Address Reorder remains in the address section. |
| App Settings | Session-only name covered authentication and other preferences | Appearance, Security and Session sections. System/Light/Dark plus independent Terminal colors. |
| Floating controls | Long flat list pushed quick actions away from the thumb | Three categories above quick-action tiles. First saved actions closest to the button; tap and press-and-slide retained. |
| View & Display | Presentation choices mixed with input and connection tools | Desktop display/fit and presentation (bar/video) groups. Video-only actions unavailable in input-only mode. |
| Keyboard & Input | Mouse choices, extra keys, shortcuts and gesture help mixed | Mouse mode, Keyboard, Preferences & Help. Selected mode checkmark and state-aware keyboard label. |
| Extra Keys | Unstructured arrows, editing and a single modifier | Editing, Navigation, Special Keys; F1–F12 submenu and balanced standalone modifiers. Gesture Guide separate. |
| Input & Quick Actions | Top Edit was ambiguous; Cancel did not cancel speed/cursor edits | Section-local Reorder and draft Save/Cancel for all preferences. |
| Session | Exit and details buried under a generic sheet | Connection Details and App Settings, separate Exit to My Macs. |
| Terminal | Forced-dark login and content; no organized controls | App-themed login, terminal-only color choices, keyboard/reconnect and settings groups. Done remains the single exit. |
| Display picker | Forced dark despite system-colored cells | Inherited appearance, layout indicators and selected display retained. |
| Live Activity | Resume/End already distinct and small | Retained both actions and system appearance. |
| SSH trust / remote clipboard / links / unlock | Confirmation semantics already explicit | Preserved decisions and privacy gating, themed content. |

## Implementation

DirectAppearanceV1 stores nonsensitive app/terminal choices. SwiftUI uses one root
appearance preference; native windows (including the privacy window) receive the
same style. Child controls inherit it. Terminal overrides only its renderer and
keyboard, updating its default foreground/background/caret without opening a new
SSH session. The black remote canvas and cursor outline are intentional.

Apple references:
- [Choosing a specific interface style](https://developer.apple.com/documentation/uikit/choosing-a-specific-interface-style-for-your-ios-app).
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).

No wire, trust, credential isolation, background recovery, dependency pins or Mac
helper behavior changes. Credentials and typed content are absent from evidence.

## Verification

- Final hosted suite: 65 passed, zero failed. Result:
  `/private/tmp/maccompanion-appearance-menus-verified-tests-20261005.xcresult`.
  New checks cover appearance persistence, invalid-value fallback, native trait
  propagation without session replacement, independent terminal palette and
  system inheritance, maximum quick-action reachability in landscape, disabled
  video actions and native submenu/back navigation. Existing socket, input,
  recovery, credential, SSH-trust and viewport tests remain passing.
- The submenu test initially tried opening a second menu before UIKit completed
  dismissal; waiting for that transition corrected the test, and the final suite
  passes. It did not require changing the remote-session implementation.
- Visual inspection verified App Settings in light and dark, grouped Mac menu,
  light Desktop and Terminal login, and the synthetic floating-control panel.
  Screenshots and synthetic test attachments stay outside the repository.
- Stable Xcode required full `bash scripts/validate.sh` exits 0. The initial
  sandbox-only run could not evaluate Swift manifests; the final complete run
  with cache access succeeds:
  `/private/tmp/maccompanion-appearance-menus-verified-validation-20261005.log`.
- Normal iPhone build succeeds; frozen source hashes, pinned dependencies,
  existing Keychain group, matching device profile and deep signatures verified:
  `/private/tmp/maccompanion-appearance-menus-signed-ios-20261005/report.json`.
- Installed on iPhone 18 Pro Max after completion (database sequence 8324):
  `/private/tmp/maccompanion-appearance-menus-install-20261005.json`.
- Launch was denied because the phone was locked; the app is installed and can be
  opened when unlocked. Evidence:
  `/private/tmp/maccompanion-appearance-menus-launch-20261005.json`.

Physical gesture/remote-session acceptance is separate from Simulator and install
results. Permanent Release gates and public distribution remain unchanged.
