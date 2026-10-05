# Expanded island curved-edge correction

The user's physical screenshot of sequence 8348 confirms the updated name/status
and compact actions fit, but the two camera-adjacent symbols are still clipped by
the expanded island's upper curved mask. This is a remaining region-placement
issue, not an action-label issue.

The expanded configuration now uses only the full-width bottom region. The desktop
symbol sits beside the Mac name there, and the redundant upper phase symbol is
removed. All expanded content has additional top, horizontal and bottom spacing.
The compact/minimal presentations and existing Resume/End Session behavior retain
their current composition and session scope.

The existing narrow-width/larger-text render regression exercises the new header
and insets, retaining a bounded bottom height budget. Prior Simulator limitations
still apply: component rendering does not establish physical expanded-island visual
acceptance.

- All eight hosted session tests pass with no skips, including the revised
  expanded component at 280/320/368-point widths with larger text. Exported
  image inspection confirms the new header and both actions fit. Result:
  `/private/tmp/maccompanion-island-inset-session-tests-20261005.xcresult`.
- Required `bash scripts/validate.sh` passes with stable Xcode. Log:
  `/private/tmp/maccompanion-island-inset-validation-20261005.log`.
- The normal device build, 566 frozen source hashes, existing Keychain group,
  device profile, widget extension and deep signature checks pass. Report:
  `/private/tmp/maccompanion-island-inset-signed-ios-20261005/report.json`.
- Installed and launched on iPhone 18 Pro Max, sequence 8356. The user subsequently
  confirms that the expanded layout works, passing the physical acceptance check
  for the clipped upper edges. This confirmation covers the reported layout issue;
  it does not establish additional session-action or extended-session acceptance.

Private screenshots and signing material remain outside the checkout. No public
release is made.
