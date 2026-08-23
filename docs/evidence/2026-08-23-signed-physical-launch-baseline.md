# Signed Physical Launch Baseline

Date: 2026-08-23

## Outcome

The current Xcode 27 beta development environment has a valid Apple
Development identity and a paired, booted physical iPhone with Developer Mode
enabled. No certificate, account credential, App ID, or provisioning profile
was created or changed during this checkpoint.

An invocation-only team and Apple Development identity override produced a
fresh signed `iphoneos` Debug app. Strict code-signature inspection accepted
the app, its designated identifier is `media.jenny.maccompanion.ios`, and its
private team identity matches the expected Jenny Media development team. The
embedded development profile is valid into August 2027. It is a wildcard team
profile, not evidence that the explicit iOS App ID or distribution profile is
ready.

The signed app installed successfully on a paired physical iPhone 17 Pro Max
running iOS 27 beta, launched under the expected bundle identifier, and
remained present in the physical device process inventory. The first
device-targeted build intentionally exposed a release-construction nuance:
because the generated iOS target pins an empty code-sign identity to keep
tracked authority inert, supplying only a development team still creates an
unsigned app. The successful signed build additionally supplied `Apple
Development` only on the local invocation; no signing authority entered the
project or repository.

A separate fresh signed macOS Debug build passed strict deep verification. The
containing app and embedded Agent have the exact identifiers
`media.jenny.maccompanion` and `media.jenny.maccompanion.agent`, share the
expected private development team, and carry hardened runtime. Launching the
containing app created a live menu-bar application process and AppKit status
item scene. The embedded Agent was not registered or launched.

## Safety boundary and non-claims

No Remote Access enable action was invoked, no `SMAppService` registration was
requested, no Agent process was started, and no Accessibility, Screen
Recording, Local Network, camera, or other privacy prompt was accepted. The Mac
unified log recorded TCC access checks from the menu app, but this checkpoint
does not treat a check as consent or permission.

The physical iPhone was already being used by another foreground app. Although
Mac Companion remained alive, a later device screenshot showed that other app,
so it is deliberately excluded from visual Mac Companion evidence. This
checkpoint proves signed construction, installation, process launch, and
survival only. It does not prove visible iPhone UI, QR/SAS pairing, explicit
iOS App ID registration, Data Protection behavior, live LAN transport,
Observe, `setAudioMuted`, captured pixels, input posting, automatic Smart Zoom,
lock behavior, TestFlight, or release signing.

## Next gate

The next signed action is consequential: explicitly enable Remote Access in
the signed Mac menu app, which registers and launches the persistent Agent.
That action must be confirmed at action time. After it succeeds, the evidence
sequence is reciprocal signed local-XPC identity/readiness, physical same-LAN
QR/SAS pairing, one fresh Observe result, one consented `setAudioMuted`
operation, and only then live Desktop plus Smart Zoom.
