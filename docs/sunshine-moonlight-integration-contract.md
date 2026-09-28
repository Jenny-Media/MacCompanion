# Sunshine / Moonlight integration contract candidate

Date: 2026-09-26. Status: implementation design; not normative protocol admission.

This records the next composition boundary for the approved integration plan.
The existing capability specification and golden cryptographic vectors remain
authoritative. Authenticated enrollment and native Desktop playback/input through normal
first-party owners now pass in the isolated signed Simulator composition. See
the [background and reconnect evidence](evidence/2026-09-27-native-background-route-recovery.md). Permanent installed-app composition remains unfinished.

Implementation now includes the normal UIKit native video owner and injection
hook, plus the [normative enrollment signing and local challenge profile](../spec/capability-protocol/v0/native-video-enrollment-signing.md).
The host challenge verifier checks the golden session signature, exact current
authority, original Control deadline, and single-use consumption. Certificate
registration and finite startup now pass against an isolated experimental
backend, with a production client owner that reconstructs and verifies the
attestation before session-key custody. See the [managed host checkpoint](evidence/2026-09-26-managed-native-host-enrollment.md).
Authenticated [primary enrollment records](evidence/2026-09-26-native-video-primary-enrollment.md)
and the [experimental TLS/launch adapter plus normal UIKit startup hook](evidence/2026-09-26-native-client-tls-launch.md)
are implemented. The isolated Mac runtime/backend composition and full native
launch/frame/input journey now pass. Permanent dependency/process/TCC admission
and installed normal-app configuration remain unfinished.

## Engine and input selection

The first integrated candidate uses Sunshine/Moonlight for video and the existing
MacCompanion authenticated Control channel for pointer, keyboard, and text input.
Upstream keyboard, mouse, controllers, native pen/touch, and automatic game launch
remain disabled. The client engine exposes video events and asynchronous Stop;
it cannot discover, pair, approve, launch an application, or submit input.
Audio is outside this first candidate.

This preserves the existing independent Observe, Act, and Control grants and
allows keyboard/modifier work to use the normal input path. Input admission must
still match the displayed surface and coordinates; the current video first-frame
callback is insufficient to authorize input by itself.

## Managed Mac process

The Mac Control owner starts one managed, pinned host process only after current
Control approval and capture ownership are established. The owner supplies the
original monotonic deadline, generation, authorization epoch, and revalidation
predicate. Revalidating or restarting the helper never extends that deadline.

The experimental supervisor already handles parent death, finite expiry, Stop,
and child reaping. The Swift owner retires after termination. Permanent process
identity, TCC attribution, signature verification, packaging, and local command
admission still need repository gates before release integration.

Each approved session needs isolated state, a Desktop-only profile, bounded
configuration, and only the current admitted client credential. Do not reuse the
user's separate Sunshine state or accept another paired client from retained
upstream configuration. UPnP and the remote management interface are not product
capabilities. Port conflicts must produce an explicit failure without modifying
or stopping another installation.

## Enrollment and session preparation

The normal primary authenticated channel owns enrollment and engine preparation.
An engine endpoint or successful GameStream pairing cannot issue Control.
The bridge must bind the exact client identity, host identity, interactive session,
authorization epoch, surface revision, media generation, endpoint, credential,
expiry, and Stop behavior. Its wire records, denial cases, and matching golden
cryptographic vectors must be added through the existing normative specification
and the sole fixture manifest before implementing those semantics.

Do not infer that MacCompanion credentials can be substituted for Moonlight's
certificates. Evaluate an authenticated enrollment bridge against an explicit
one-time re-pair migration and choose only after cryptographic compatibility is
established. The loopback reference's normal PIN pairing proves neither option.

## Presentation and teardown

The client has explicit preparing, connecting, displaying, failed, and retired
states. A failure stays visible with a useful reason; it does not silently dismiss
the Control view. The engine holds its process-global native owner until sockets
and decoder callbacks drain, blanks its renderer immediately on Stop, suppresses
retired callbacks, and erases its internal transport key after native teardown.

Desktop coordinates must describe the actual capture dimensions, scale, crop,
and surface revision. Window focus or viewport changes require a new validated
presentation fence before input resumes. The first candidate must not promise
window crop or viewport bitrate savings based on full-desktop reference playback.

Both sides terminate on revocation, expiry, owner loss, permission loss, or an
unprovable session. Reconnect does not replay input or restore an expired grant.
Normal-app acceptance remains the plan's repeated starts, sustained session,
Stop/revocation matrix, recovery checks, and physical-device tests.
