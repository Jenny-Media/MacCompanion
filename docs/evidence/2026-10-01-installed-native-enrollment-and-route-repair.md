# Installed native enrollment and authenticated route repair

The normal development apps were tested against the user's physical iPhone 17
Pro Max through iPhone Mirroring. Its existing Mac Companion pair authenticated
without pairing again. The installed Mac dashboard showed Agent/menu ready,
private listener listening, Screen Recording and Accessibility ready, and Control
allowed. This is development evidence; it does not admit release artifacts.

## Reproduced failures

The first physical Control request was approved and started. During native
enrollment the Mac reported `nativeBackend` preparation `invalidCertificate`;
the Agent ended the role pair, and the phone recorded a media read failure.

The packaged OpenSSL helper retained an `OPENSSLDIR` under the historical
`/private/tmp/maccompanion-native-host-sources-20260927` build tree. Its `req`
command failed because that configuration file was absent. Running the same
command with the already-packaged `openssl.cnf` succeeded. Disposable keys and
certificates from this isolated reproduction were removed.

The Mac backend now explicitly selects a local configuration for certificate
generation. The bundled composition supplies the configuration already covered
by the fixed development catalog. Component composition uses an empty
configuration with the existing explicit certificate options. A missing selected
configuration remains an error. Enrollment/signature bytes, certificate purpose
and independent grants are unchanged.

A signed repaired Mac app was installed at
`/Users/yihong/Applications/Mac Companion.app`. Its containing signature and
nested Agent entitlements were verified. The exact admitted Sunshine resource
files and catalog were retained without modification. The previous app is
recoverable at `/private/tmp/maccompanion-mac-pre-config-repair-20261001.app`.

The next physical request completed native enrollment and started the managed
host, then failed on the phone with `NativeLaunchFailure.invalidRoute`. The
normal primary-state reader supported configured numeric endpoints but did not
retain the measured numeric address of DNS/Bonjour connections.

The client now takes that measurement from the ready Network.framework
connection after consuming its verified TLS handoff. It publishes the address
only with the selected authenticated primary and removes it on replacement or
termination. Native launch does not resolve the name again or accept a route
from server metadata. Unresolved names remain unavailable. A loopback hostname
probe verified that `currentPath.remoteEndpoint` exposes a numeric endpoint.

Native failures now supply fixed recovery text through the local adapter
interface. The normal root no longer claims that an unsuccessful command always
kept the previous verified state. No raw server text, addresses, keys or input
content is displayed by this interface.

## Verification and installation

- The real relocated-helper backend regression passes with the developer
  configuration absent. It also rejects a missing explicitly selected
  configuration, and removes its disposable credentials.
- Two route tests pass, including eight selection cases across IPv4, IPv6, DNS
  and Bonjour with and without measured addresses. They cover unselected and
  stale candidates, replacement and termination. Numeric extraction rejects
  names, service endpoints and missing paths.
- `bash scripts/validate.sh` passes on Xcode 27.0 (`27A266a`), including 116 indexed
  fixtures, the real helper regression and the route tests. This is a stable
  installed Xcode result, not the historical beta lane.
- The final native SDK and normal `iphoneos` build pass with source input hash
  `433a454966df48d0a44beb05603d0d84239dd73bbeafcbc7bec9c1d0e4a69672`.
  Xcode signs the app using the existing development profile. Strict signature
  verification and installation on the physical iPhone 17 Pro Max pass.

## Physical IPv6 playback and repeated-session failure

The user completed Touch ID through iPhone Mirroring. An approved request
completed enrollment and bound the measured route, but its first native HTTPS
request failed. The established primary connection was IPv6; the managed native
backend was configured for IPv4 interfaces only. The development composition
now selects dual-stack listeners with the same attested client, sealed routes,
mandatory encryption and Control deadline. Component default remains loopback.
The existing packaged host already supports this configuration; its binary and
catalog did not change.

The next approved physical session completed serverinfo, applist, encrypted
launch and the native presentation receipt with input admitted. The normal
iPhone app displayed real moving Mac video. Content-free diagnostics recorded
advancing frame counters for more than four minutes, with no native errors.
The display picker loaded while playback was active. Stop recorded a successful
terminal event, retired the native process, and returned to the authenticated
workspace without pairing or reconnecting.

A second Control request on the same primary exposed an independent repeat
failure. Content-free diagnostics showed matching display, menu generation and
deadline, but a different menu revision. The activity indicator advances its
receipt counter on show/clear/show, while the authenticated menu publication
can remain unchanged. Initial runtime admission already accepts a receipt at
least as new as publication; native setup incorrectly required equality.
Native setup now uses the same revision floor as initial runtime admission,
while retaining exact snapshot/admission stability, generation, session, surface,
display, key and deadline checks. A golden-vector-backed regression failed
before the correction and passes after it; an older receipt remains rejected.
All 11 native bridge tests pass. The signed repair is installed on the Mac.
The final `bash scripts/validate.sh` run passes, including this regression,
the real relocated-helper test, 116 indexed fixtures and all platform lanes.
Its first physical approval prompt expired without approval, so repeated-session
acceptance was initially pending. Subsequent user approvals verified two sessions
on the repaired build: Stop returned to the authenticated workspace, and a fresh
request on the same primary started real moving video without reconnecting or
pairing again. The second session's frames advanced for more than 21 minutes.
The App shortcut visibly switched the Mac application. The surface picker opened
while playback continued. Real pointer effects, text entry/modifiers and selected
App/Window focus remain unverified; text testing was paused because the shared
Mac display was in use outside the disposable test document.
No approval presence was substituted or paired key changed.

## Failed product and background recovery

Terminal live-product and role preparation failures now capture the exact
accepted session and owning primary channel, disable local input, and submit the
existing authenticated Stop for that session. A stale action cannot target a
replacement session or primary, and concurrent failures reserve one pending
Stop. Local navigation does not submit Stop. The failure screen uses terminal
recovery text and removes keyboard and surface controls instead of retaining an
active workspace description. The selected-session regression passes all 18
ordering cases, including stale/duplicate retirement, and an eight-callback
concurrency test emits one exact session/epoch Stop. Five iOS coordinator tests
pass on the existing iPhone 17 Pro Max Simulator, including one retirement after
failure and no remote retirement for local navigation.

Physical backgrounding reproduced an independent failure: the hidden legacy
VideoToolbox bootstrap decoder continued processing beside native playback and
failed after the phone app entered background. The media/input roles closed,
the host stopped Control, and the primary disconnected. Foreground return
automatically authenticated the saved pair again and returned to a fresh
Request Remote Control state. It did not resume the retired native generation.

Native video construction now suppresses legacy decoding only after the exact
bootstrap descriptor's clean-frame acknowledgement is active. Media records
remain fully admitted and validated; suppression supplies no native presentation
or input authority. New replacement surfaces still require their own bootstrap
render and acknowledgement. EOF remains terminal. A fresh approved physical
session on the updated client recorded bootstrap suppression, native presentation
input admission and advancing frames. Backgrounding produced no hidden-decoder
failure. The configured ten-second primary background grace expired, Control
stopped, and foreground return automatically authenticated the saved pair again.
The retired native generation did not resume.

The final normal client is built, signed with the existing development profile,
strictly signature-verified and installed on the physical iPhone 17 Pro Max. Its
source input hash is `c3ac0960e9f30f7ff5b4437251b7342b3eadbde7f03355be8c3382fb53724bf7`.
The final `bash scripts/validate.sh` passes on stable Xcode 27.0 with 118 indexed
fixtures and all platform lanes. Eight bootstrap lifecycle cases and both
legacy/native replacement cases pass. This installation retains the saved pair
and does not substitute approval presence.

## Native display replacement

On the updated physical client, choosing the other display during native playback
immediately failed. The native product's display method still rejected an active
native owner, although the picker offered that choice. The captured failure
retirement submitted Stop for the owning session, and the Mac recorded Control
stopped while the primary remained authenticated. This physically verifies failed
product retirement for that failure, without injected consent or pairing changes.

Display replacement now uses the existing native App/Window drain and fresh
enrollment path, including the authenticated Desktop replacement and its clean
bootstrap acknowledgement. All four native/legacy App/Display ordering cases pass.
The signed normal client with source input hash
`9264cf1d2a70f2e59fea95be366249e76ab26e0e4fccf6595f8b482cd8ae0959`
is installed on the same physical phone. The repeated display choice now succeeds:
diagnostics record renderer/enrollment drain and preparation join, reset before
selection, host acknowledgement, fresh enrollment, native presentation input
admission and advancing video on the other display. No reconnect or pairing was
needed. The UI briefly shows restart guidance while the old renderer drains,
then returns to live video; clearer transition presentation remains a usability
improvement.

The surface picker on the other display exposes available App/Window targets.
Automated wheel and drag gestures through iPhone Mirroring have not moved the
picker list, so TextEdit selection and text/pointer effects remain unverified.
Final required repository validation on stable Xcode 27.0 passes after this
display correction, including 118 indexed fixtures and all platform lanes.

## Local evidence

No screenshots, audit databases, private state or input content enter this
document or Git. Local diagnostics and construction records are retained at:

- `/private/tmp/maccompanion-iphone17-runtime-attempt1-20261001.log`
- `/private/tmp/maccompanion-iphone17-runtime-after-config-fix-20261001.log`
- `/private/tmp/maccompanion-enrollment-config-test-20261001.log`
- `/private/tmp/maccompanion-measured-native-route-tests-final-20261001.log`
- `/private/tmp/maccompanion-physical-final-validation-20261001.log`
- `/private/tmp/maccompanion-mac-config-repair-stage-20261001.json`
- `/private/tmp/maccompanion-normal-iphone17-final-20261001/build-report.json`
- `/private/tmp/maccompanion-normal-iphone17-final-sign-20261001.log`
- `/private/tmp/maccompanion-iphone17-final-install-20261001.log`
- `/private/tmp/maccompanion-iphone17-diagnostics-20261001-1832.log`
- `/private/tmp/maccompanion-iphone17-dual-stack-20261001-1837.log`
- `/private/tmp/maccompanion-mac-dual-stack-stage-20261001.json`
- `/private/tmp/maccompanion-native-admission-validation-escalated-20261001.log`
- `/private/tmp/maccompanion-indicator-revision-before-20261001.log`
- `/private/tmp/maccompanion-indicator-revision-after-20261001.log`
- `/private/tmp/maccompanion-mac-revision-repair-stage-20261001.json`
- `/private/tmp/maccompanion-physical-revision-final-validation-20261001.log`
- `/private/tmp/maccompanion-iphone17-second-session-20261001.log`
- `/private/tmp/maccompanion-iphone17-background-20261001.log`
- `/private/tmp/maccompanion-failed-retirement-channel-final-20261001.log`
- `/private/tmp/maccompanion-failed-ui-tests-20261001/test.log`
- `/private/tmp/maccompanion-native-bootstrap-suppression-final-20261001.log`
- `/private/tmp/maccompanion-native-background-final-validation-20261001.log`
- `/private/tmp/maccompanion-normal-iphone17-background-20261001/build-report.json`
- `/private/tmp/maccompanion-iphone17-background-sign-20261001.log`
- `/private/tmp/maccompanion-iphone17-background-install-20261001.log`
- `/private/tmp/maccompanion-iphone17-background-repair-live-20261001.log`
- `/private/tmp/maccompanion-iphone17-background-repair-return-20261001.log`
- `/private/tmp/maccompanion-iphone17-display-failure-20261001.log`
- `/private/tmp/maccompanion-native-display-replacement-final-tests-20261001.log`
- `/private/tmp/maccompanion-normal-iphone17-display-20261001/build-report.json`
- `/private/tmp/maccompanion-iphone17-display-sign-20261001.log`
- `/private/tmp/maccompanion-iphone17-display-install-20261001.log`
- `/private/tmp/maccompanion-iphone17-display-repair-live-20261001.log`
- `/private/tmp/maccompanion-native-display-final-validation-20261001.log`

Failure retirement and terminal UI recovery are implemented and locally tested;
the display-selection failure physically verifies the owning session's retirement.
Other failure paths and remaining input/focus checks still require follow-up.
Earlier Simulator acceptance does not establish those physical results.
