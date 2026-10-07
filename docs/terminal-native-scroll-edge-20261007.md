# Native Terminal scroll-edge treatment

## Decision

The user compared the physical Terminal screen with another app and identified
that the faded, still-sharp letters behind the status icons did not match the
native progressive blur. They requested trying the system treatment to reduce
custom presentation code.

The custom `TerminalStatusFadeView`, gradient colors, mask sizing and palette
updates are removed. The Terminal controller registers its real scroll view
with `setContentScrollView(_:for:)` for the top edge and chooses the native
`topEdgeEffect.style = .automatic` on iOS 26 and later. The normal client already
targets iOS 26. No transparent placeholder bar, custom blur, extra terminal,
image sampling or simulated system control is added.

The first hosted full-system capture confirms this integration renders the
native progressive blur in the existing headless layout. The native effect
already reaches the status area; it does not require a visible navigation bar
or `UIScrollEdgeElementContainerInteraction` here. The result replaces the
custom fade introduced in local build 9.

The physical-window leading inset, whole-row usable PTY grid, keyboard avoidance
and existing SSH lifecycle remain as described in
[`terminal-immersive-scrolling-20261007.md`](terminal-immersive-scrolling-20261007.md).
Sign-in and recovery stay inside the safe area. Initial output remains below
the status icons. Only scrollback passes behind them.

Apple's guidance:

- [UIKit scroll-edge integration](https://developer.apple.com/videos/play/wwdc2025/284/)
- [Scroll-view design guidance](https://developer.apple.com/design/human-interface-guidelines/scroll-views)
- [Native top edge effect](https://developer.apple.com/documentation/uikit/uiscrollview/topedgeeffect)

## Evidence

- Stable Xcode 27.0 (27A266a), iPhone 18 Pro Max Simulator on iOS 27.0.
- Eight synthetic full-system captures show sign-in, initial output, scrollback
  and keyboard-open scrollback in light and dark palettes. History behind the
  icons is visibly blurred by UIKit, and text below the transition stays sharp.
  Initial output is clear of the transition in both palettes.
- Source and screenshots are verified separately: the successful capture test
  does not by itself prove the native effect appeared. The full-system images
  were inspected at original resolution.
- Native effects follow system behavior. High contrast and Reduce Transparency
  are not independently verified on physical hardware in this follow-up.
- All 23 focused regressions pass, including initial output and history geometry,
  keyboard and palette transitions, full-screen terminal buffers, menus and
  in-process SSH app-switch retention.
- `bash scripts/validate.sh` passes with stable Xcode. The normal device app
  and extension build successfully, and signing verifies all 577 source and
  dependency inputs with the existing app/widget and private Keychain identities.
- The final pre-commit stable-Xcode validation rerun also passes with exit zero:
  `/private/tmp/maccompanion-native-terminal-commit-validation-20261007.log`.

Evidence remains outside Git:

- `/private/tmp/maccompanion-terminal-native-edge-auto-20261007.xcresult`
- `/private/tmp/maccompanion-terminal-native-edge-auto-20261007-captures/`
- `/private/tmp/maccompanion-terminal-native-edge-regression-20261007.xcresult`
- `/private/tmp/maccompanion-terminal-native-edge-validation-20261007.log`
- `/private/tmp/maccompanion-terminal-native-edge-20261007-device/build-report.json`
- `/private/tmp/maccompanion-terminal-native-edge-20261007-signed/report.json`

The local comparison page is
`http://127.0.0.1:50636/native-scroll-edge/`. Its HTML and all 16 synthetic
before/after images load successfully; screenshots stay outside Git.

The user subsequently confirmed the physical result and requested a local commit.
No push or TestFlight publication is requested for this checkpoint.

## Physical delivery

Local development **1.0 (10)** is installed and launched on iPhone 18 Pro Max.
CoreDevice reads back build 10 and installation sequence **9072** for the
existing `media.jenny.maccompanion.ios` bundle. The saved application and private
Keychain identities are retained. The user confirmed "It works" on the physical
iPhone and supplied a screenshot showing Terminal history behind the status
icons with the native blur. This establishes physical visual acceptance of the
scroll-edge treatment; accessibility settings remain a separate check.
