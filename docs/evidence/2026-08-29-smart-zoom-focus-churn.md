# Smart Zoom focus-churn recovery evidence

Date: 2026-08-29

## Observed failure

During a physical iPhone Control session, a dramatic Mac UI change caused
Accessibility focus to alternate between Desktop and Focused Region. Unified
logs showed successive automatic surface replacements followed by
`surfaceResolve` failing with `bindingMismatch` at 11:13:12.848. The primary
endpoint then closed and the media/input roles retired. This correlated the
user-visible disconnect with focus-driven surface churn rather than raw frame
rate or bitrate.

## Repair

- The Agent stabilizes ordinary focus candidates before publishing them.
- Input-pausing and secure-focus observations remain immediate.
- The iOS product coalesces pending automatic recommendations before changing
  the capture surface.
- Focused Region waits 250 ms; transient Desktop fallback waits 750 ms.
- A transition already sent to the authenticated host is never cancelled.
- The disposable live-control host can emit Focused Region, ambiguous Desktop,
  and a new Focused Region within 100 ms for deterministic regression testing.

## Verification

- `swift test --filter MacAgentFocusEventObserverV1Tests`: 9 tests passed.
- Full `swift test` from `Packages/MacCompanionKit`: passed.
- Client UI harness iPhone Simulator build: passed on the booted iPhone 17,
  iOS 27.0 Simulator.
- `MACCOMPANION_LAB_SUITE=live bash scripts/verify_simulator_features.sh`:
  passed, including the new rapid focus-churn assertion, continued encoded
  frame progress, pointer/zoom/keyboard checks, reconnect, cleanup, and pairing
  regressions. The churn produced exactly one acknowledged replacement.
- Disposable report:
  `/private/tmp/maccompanion-feature-tests.CnPTGn/report.json` (`passed`).

## Remaining boundary

The installed Mac Agent and physical iPhone app have not yet been replaced by
builds containing this repair. Repository validation reached the pre-physical
completion audit and stopped because its recorded soak fingerprint predates
this source change. The stopped soak scheduler was not resumed automatically.
