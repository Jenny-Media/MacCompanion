# Sparkle ready-to-install hold-point bridge

Date: 2026-08-23

Status: containing-app construction and unsigned target pass. No protected
appcast, full update check, download, extraction, installation, relaunch,
network-listener transition, or Agent lifecycle action ran.

## Outcome

The permanent macOS adapter now uses
`MacCompanionSparkleUserDriverV0`, a complete `SPUUserDriver` proxy. It forwards
every required Sparkle 2.9.6 user-driver method to `SPUStandardUserDriver` and
intercepts only `showReady(toInstallAndRelaunch:)`. Swift cannot safely
subclass this behavior because `SPUStandardUserDriver` declares protocol
conformance without redeclaring the witness method on its public class
interface; the checked-in proxy is the compile-verified integration shape.

The adapter also implements the exact item-bearing updater callbacks:

1. `willExtractUpdate` reconstructs the complete signed publication, requires
   it to equal the retained informational offer, and starts one package-owned
   correlation;
2. `didExtractUpdate` reconstructs the publication again and records only the
   installer-start acknowledgement; and
3. the user-driver readiness reply waits for those serialized events and
   requires the package actor to be awaiting installation readiness.

The synchronous Objective-C delegate callbacks enqueue one ordered task chain,
so a fast `didExtractUpdate` cannot overtake the preceding `willExtractUpdate`
actor call. Candidate/evidence mismatch, reordering, cancellation, task
cancellation, updater abort, missing state, or adapter loss retires the
correlation.

## Closed installation authority

The bridge does not yet bind the real foreground confirmation and runtime
shutdown owner. Consequently it cancels the correlation and replies `.skip`
at the readiness hold point. In Sparkle's installing stage, `.skip` cancels the
staged installation without permanently skipping that version; `.dismiss` is
intentionally not used because Sparkle may still install a dismissed prepared
update when the app terminates.

The existing delegate policy still admits only `SPUUpdateCheck.updateInformation`
and calls only `checkForUpdateInformation()`. The source validator requires the
proxy, both item callbacks, serialized correlation, cancellation reply, and
absence of an exposed pending-correlation getter. It continues to reject full
or background update checks, automatic checks/downloads, arbitrary sessions,
and any unconditional `.install` reply.

## Verification

The code-signing-disabled Debug `MacCompanion` scheme builds successfully on
Xcode 27 beta with the exact Sparkle 2.9.6 binary interface. The permanent
Apple-target validator accepts the bridge and the focused package correlation
tests continue to cover the exact three-stage sequence, substitution,
reordering, cancellation at every phase, and concurrent ready calls.

The complete repository gate passes 73 authoritative fixtures, 35 update-policy
fixtures, 1,136 repository files and 1,920 historical blob paths, every
supply-chain, privacy, SBOM, signing, packaging, and release-evidence validator,
1,544 MacCompanionKit tests, 8 platform-probe tests, and every permanent target
and supported cross-platform compile on Xcode 27 beta.

## Deliberate non-claims

This checkpoint does not present Mac Companion's foreground update
confirmation, call `reachedReadyToInstall()`, construct the runtime shutdown
coordinator, close the real listener, drain the real dispatcher, stop or
restart the Agent, forward `.install`, enable a full update check, or exercise
a signed two-version upgrade. Those actions remain closed until a concrete
runtime owner can perform and recover the required effects without silently
disabling remote access.
