# Release-Gated User Update Check

Date: 2026-08-23  
Toolchain: Xcode 27 beta (`27A5218g`), provisional pending stable Xcode 26.6  
Runtime effects: none

## Outcome

Mac Companion now has the narrow source route required for signed two-version
update testing without enabling automatic or background behavior. The tracked
property list carries an empty-by-default
`MacCompanionUpdateUserInitiatedCheckProfile` build value.

When the value is absent or empty, the visible `Check for Updates` action still
calls only Sparkle's `checkForUpdateInformation()`. Only the exact
`maccompanion.user-initiated-full-update-check.v1` value constructs a typed
authority bound to the already validated beta/stable release channel and the
current canonical bundle build. That authority changes the same foreground
action to `checkForUpdates()`. A non-string, unknown, partial, or substituted
profile invalidates the entire updater configuration before Sparkle starts.

The updater delegate admits only the one check kind expected by that immutable
startup authority and one explicit visible-action permit. It still rejects
`checkForUpdatesInBackground()`, keeps Sparkle automatic checks and automatic
downloads false, sends no system profile or custom parameters, and retains the
independent candidate, ready-point, foreground-confirmation, shutdown, recovery,
and one-shot install gates.

## Verification

- Two package tests prove exact profile acceptance, channel/build binding, and
  profile-substitution rejection.
- The dependency validator binds the new property-list key without changing the
  sole exact Sparkle 2.9.6 dependency.
- The permanent source validator requires exactly one authority-guarded full
  check mapping and continues to reject every background check.
- The code-signing-disabled permanent macOS scheme builds with Xcode 27 beta.
- The complete repository gate exits zero with 1,605 package tests plus 8
  platform probes.

No app, Agent, login role, listener, XPC session, update check, feed request,
download, extraction, updater, installer, or network action ran.

## Remaining gate

This source authority is not a release claim. The protected lane must bind the
exact execution profile into the signed-candidate manifest and then retain a
signed old-to-new upgrade matrix covering `Not Now`, foreground loss, Control
active/cleanup-uncertain denial, listener and Agent recovery, successful
handoff/relaunch, forced process loss, rollback, and clean-machine behavior.
An externally distributed beta must not carry the profile before that evidence
passes and receives explicit release approval.
