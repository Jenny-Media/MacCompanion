# Add/Edit Mac address controls and default port

## Changes

The generic toolbar Edit button controlled only address deletion/reordering while
the other fields were already editable. It is replaced by Reorder beside the
Connection Addresses heading when multiple addresses exist, becoming Done while
reordering. Cancel and Save remain in the navigation bar. Leaving fewer than two
addresses exits reordering so the editor cannot be stuck in a hidden edit mode.

Previously, clearing Port resolved to zero and disabled Save. One shared parser
now resolves empty or whitespace-only text to 5900 and rejects nonempty values
outside the integer range 1–65535. Validation, shared-endpoint information and
Save use that same resolved port. The empty field shows 5900 (default) and the
footer explains the behavior. Existing custom ports remain prefilled. Editing
the port retains the saved Mac UUID and its login.

The normative specification and the existing indexed direct-screen-sharing
fixture were updated before implementation. Twelve editor port vectors cover
blank/whitespace, valid defaults/overrides/boundaries, zero, negative, excessive,
nonnumeric, fractional and overflowing input. No extra fixture corpus was added.

## Verification

- The actual Simulator Add Mac form was inspected: only Cancel and Save appear
  at the top; one address hides Reorder, adding another reveals it, and activating
  it shows the address move/delete handles and section Done. The Advanced field
  shows the default placeholder and explanation, with Save enabled when valid
  addresses and an empty port are present. Custom port entry was also checked.
- All 46 hosted Simulator tests pass, including the twelve editor vectors and
  actual atomic library persistence plus synthetic Keychain credential retention
  after clearing a custom port. An invalid port leaves the record/file unchanged.
  Result: `/private/tmp/maccompanion-editor-default-port-tests-20261005.xcresult`.
- Required `bash scripts/validate.sh` passes with stable Xcode at
  `/Applications/Xcode.app/Contents/Developer`. Log:
  `/private/tmp/maccompanion-editor-default-port-validation-20261005.log`.
- The normal device app builds; all 480 recorded source hashes and the signed
  binary hash are rechecked after tests. Deep signature, existing Keychain group,
  device profile and ActivityKit extension verification pass. Private report:
  `/private/tmp/maccompanion-editor-default-port-signed-ios-20261005/report.json`.
- Installation on iPhone 18 Pro Max succeeds, sequence 8284, preserving app data.
  Automatic launch is denied because the iPhone is locked. Physical editor
  acceptance remains pending; the user can open the installed app after unlock.

Screenshots and synthetic typed content remain outside the repository. No commit,
publication or production release is made.
