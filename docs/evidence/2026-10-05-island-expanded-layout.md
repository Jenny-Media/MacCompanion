# Expanded Dynamic Island layout

## Change

The expanded island previously put the phase text in the narrow trailing region
beside the camera and reused the larger Lock Screen action buttons below it. That
layout leaves little room for a longer phase or larger text. The earlier ordinary
card render checks did not cover the expanded island's content.

The camera-adjacent regions now contain small desktop and phase symbols. The
full-width bottom region shows the Mac name and phase together, followed by two
compact, single-line actions. Names can use two lines; very long names still
truncate with their complete VoiceOver label retained. The compact ending action
says End and retains the accessible name End Session. Expanded text scales through
xxxLarge, bounded to the island's limited space. Lock Screen actions retain their
full labels. Resume URLs, End Session activity-ID scoping and connection behavior
are unchanged.

## Verification

- The normal app and WidgetKit extension compile in the Simulator composition.
- The expanded bottom component renders at 280, 320 and 368 points with a long
  synthetic name and the widest phase, Reconnecting. Large, xxxLarge and
  accessibility3 settings are exercised. All nine configurations fit within the
  132-point bottom-region budget; exported image inspection confirms Resume and
  End fit without truncation at the narrowest/largest combination.
- The first render run counted the host window's safe-area insets as content
  height; the measurement now excludes those host insets. Its screenshot also
  exposed truncation of the long End Session button label, corrected by the short
  expanded label. A subsequent runner launch failed before testing; restarting
  the Simulator app resolved that environment failure. The corrected focused run
  passes with no skipped checks:
  `/private/tmp/maccompanion-island-layout-fitted-20261005.xcresult`.
- An isolated test outside the repository created a real synthetic Live Activity.
  SpringBoard registered its name and phase in accessibility, but the Simulator
  did not visibly render or expand that system island during automated interaction.
  Component rendering is therefore not claimed as physical/system visual acceptance.
  The temporary test was removed from the private QA project afterward.

- All eight hosted session tests pass, including scoped End Session, stale/repeated
  intent handling, ActivityKit lifecycle, opt-out/recovery, Lock Screen cards and
  the new expanded component check. A test-runner bootstrap stalled before any
  tests; it was stopped and the app relaunched. The recovered passing result is
  `/private/tmp/maccompanion-island-layout-verified-session-tests-20261005.xcresult`.
- Required `bash scripts/validate.sh` passes with stable Xcode. Log:
  `/private/tmp/maccompanion-island-layout-final-validation-20261005.log`.
- Normal device build, 566 frozen source hashes, matching device profile,
  ActivityKit extension and deep signature verification pass. Existing app data
  and the credential Keychain group are preserved. Signed report:
  `/private/tmp/maccompanion-island-layout-signed-ios-20261005/report.json`.
- The update is installed and launched on iPhone 18 Pro Max, sequence 8348.
  Physical expanded-island visual acceptance remains pending. Check: connect to
  M5, background the app, expand the island and verify the name, complete phase,
  Resume and End are visible. End still deliberately closes the session.

Screenshots, synthetic system
preview source, result bundles and development signing material stay outside the
repository. No commit or public release is made.
