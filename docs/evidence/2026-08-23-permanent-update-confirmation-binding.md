# Permanent Update Confirmation Binding

Date: 2026-08-23  
Toolchain: Xcode 27 beta (`27A5218g`), provisional pending stable Xcode 26.6  
Runtime effects: none

## Outcome

The permanent macOS target now binds Sparkle's held
`showReadyToInstallAndRelaunch` reply to the package-owned validation,
foreground-confirmation, shutdown, recovery, and one-shot installer owners.
The visible menu presents two unambiguous choices: `Not Now` and
`Install and Restart`.

The bridge accepts only the active validation correlation and the same visible
candidate build and display version. It waits for serialized validation to
reach installation readiness, consumes the single-use admission, constructs
the permanent runtime owner, and requests foreground user attention. Missing
runtime composition, phase drift, mismatch, cancellation, or competing owner
resolves `.skip`.

Only `Install and Restart` calls the foreground owner's confirmation method.
Foreground loss is forwarded into that owner, and ordered application
termination cancels and joins the ready-callback bridge, then joins both the
owner and its in-flight task before AppKit receives the termination reply. The
sole Sparkle `.install` reply remains the typed install-to-install mapping from
the package-owned one-shot reply.

## Verification

- Regenerated the checked-in `MacCompanion.xcodeproj` from `project.yml`, which
  added `MacCompanionUpdateRuntimeCompositionV0.swift` to the target.
- `scripts/validate_permanent_apple_targets.py` passes and asserts runtime
  installation, readiness correlation, foreground forwarding, explicit UI
  decisions, termination joining, and the absence of full/background checks.
- `xcodebuild -project MacCompanion.xcodeproj -scheme MacCompanion
  -configuration Debug CODE_SIGNING_ALLOWED=NO build` succeeds with Xcode 27
  beta.
- The repository-wide validation gate exits zero with 1,603 package tests plus
  8 platform probes; this binding adds no package test target.

No Mac Companion app, Agent, login role, listener, XPC session, update feed,
download, extraction, installer, or network path was launched or mutated.

## Remaining gate

The ordinary menu action still calls only `checkForUpdateInformation`, and
automatic/background checks remain disabled. Therefore normal product behavior
cannot reach download, extraction, the ready callback, network quiescence,
Agent stop, or installation. Enabling a user-initiated full check remains a
separate protected-release decision after signed old-to-new installation,
foreground-loss, forced-process-loss recovery, rollback, clean-machine, and
physical confirmation/accessibility evidence is available. Stable Xcode 26.6
verification is also still required.
