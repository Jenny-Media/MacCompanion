# Session menu and shared icon layout — 2026-10-07

## Active Terminal menu

Terminal's Session menu contains Connection Details, App Settings and Exit to
My Macs. Mac Settings and SSH Keys belong to connection configuration and are
removed from this active-session menu. The saved Mac's settings retain account,
address, key selection and installation actions. Login and recovery retain their
relevant setup actions.

## Reproduced clipping

The shared quick panel used a fixed 64-point category height at ordinary Dynamic
Type sizes. Symbols and captions grew with the system text setting, and long
captions wrapped. At XXXL, View & Display's image began about 9 points above its
button and Keyboard & Input's about 6 points above it. The native button clipped
these parts; the labels also extended below their tiles. Terminal reproduces the
same defect because it uses the same control. The largest accessibility size also
overflowed a wrapped title in the single-column layout.

Each configured native button is now measured at its actual column width with
`sizeThatFits`. Category and quick-action rows use the resulting height, keeping
64 points as the minimum. Titles wrap without a fixed line count. Existing
single-column accessibility/short-screen layouts and scrolling are preserved.
The shared 52-point main button uses a fixed 20-point ellipsis symbol so the
symbol also fits at the largest text size; menu text continues to scale.

## Verification

- The new hosted geometry regression fails on the preceding implementation and
  passes with the fix. It checks actual image/title bounds in Desktop and
  Terminal across default, XXXL and two accessibility sizes, at portrait,
  narrow-phone and landscape widths. The main button's image is checked too.
- All 12 focused hosted checks pass on stable Xcode 27.0, including menu scrolling,
  tap/press-and-slide selection and cancellation, haptics opt-out, input-only
  behavior, keyboard avoidance and the shorter active Terminal menu.
- Required `bash scripts/validate.sh` passes on stable Xcode.
- Before/after synthetic captures confirm the category clipping and its removal.
  Full-system Terminal captures confirm the shortened Session menu and quick
  panel in both palettes with the keyboard visible.

Evidence stays outside Git:

- `/private/tmp/maccompanion-control-icons-20261007-before.xcresult`
- `/private/tmp/maccompanion-session-menu-icons-20261007-final.xcresult`
- `/private/tmp/maccompanion-session-menu-icons-20261007-final-images/`
- `/private/tmp/maccompanion-session-menu-icons-20261007-captures/`
- `/private/tmp/maccompanion-session-menu-icons-20261007-validation.log`

Installed development build 14's preceding source is committed as `987c265`.
This menu/layout follow-up has Simulator verification and has not been installed
on the physical iPhone or published to TestFlight.
