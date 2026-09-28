# Installed Agent entitlement preservation and dashboard recovery (2026-09-28)

The signed normal Mac development app installed in the preceding dashboard
checkpoint launched, but its own window showed **Mac Agent unavailable**.
ServiceManagement kept the nested Agent process running, so process existence
alone had overstated recovery. Inspection of that installed Agent's code
signature showed no entitlement payload. The development staging script had
re-signed the Xcode-built Agent without preserving its signing metadata. The
Agent target requires its application identity and Keychain access group for
the existing secure host identity.

`scripts/stage_bundled_native_host_development.py` now rejects a source Agent
without a Keychain entitlement, preserves identifier, entitlements, internal
requirements, flags, and runtime metadata when re-signing the containing graph,
and requires the staged Agent's entitlement payload to equal the source
payload. A fresh Xcode-signed Agent had the application identifier, team
identifier, and Keychain access group. The staged Agent retained that same
payload and the containing app passed strict deep signature verification.
Trying to stage the entitlement-missing installed app failed before making an
output bundle, as intended.

The corrected development app was installed at
`~/Applications/Mac Companion.app` and its containing signature and Agent
entitlements verified in place. The existing enabled Agent registration was
restored through the app's `maccompanion://repair-agent-registration` command;
pairing data and separate Observe, Act, and Control grants were not reset.
The normal installed window then showed **Mac Companion is on**, Agent and menu
ready, private listener listening, local-network route, security storage
available, and Remote Control allowed. A controlled Agent termination changed
the Agent PID while the dashboard kept its PID. The same installed window
returned to that ready/listening state after the restart. This observes the
real installed dashboard reconnect rather than inferring it from process
survival. The separate Sunshine installation was not changed.

The dedicated MacCompanion QA Simulator's normal iOS app currently opens at
its unpaired pairing screen. Another booted iPhone Simulator correctly refuses
the normal app because its protected local storage is unavailable. Neither
Simulator was paired to this installed Mac during the check. The already
installed normal iOS app launched successfully on the connected, paired
physical iPhone 18 Pro Max.

The user then requested Remote Control on that iPhone and reported the generic
**Command did not complete** alert. The installed Mac still displayed Agent
ready/listening and Control allowed; there was no confirmed video frame or
input effect. A content-free read of the Agent's local audit database showed
one earlier Control session approved and started without a terminal event
before this attempt. Six subsequent requests from the same device were
recorded while that session was still active; they had no approval or start
event. The host records a request before checking its active-session guard,
which returns `interactive.sessionActive` when an earlier session remains.
That makes the guard the likely rejection for these six requests, although the
exact response was not captured on the device. The earlier session was
subsequently cancelled and its connection closed. The iOS workspace discards
the underlying command error when presenting the generic alert. The reason
the earlier session remained active after the user-visible failure is not yet
established. No post-recovery native Control stream, video frame, or input
effect is claimed.
Temporary window and Simulator captures used for inspection were removed;
no screenshot, pairing secret, profile, certificate, or typed content is tracked
here.

Build and staging records stay under `/private/tmp`:

- `maccompanion-entitlement-preservation-build-20260928.log`
- `maccompanion-entitlement-preservation-stage-20260928.json`

The previous installed development bundle remains recoverable under
`/private/tmp/maccompanion-entitlement-missing-installed-20260928.app`; an
earlier signed preinstall backup remains under
`/private/tmp/maccompanion-dashboard-recovery-preinstall-20260928.app`.
