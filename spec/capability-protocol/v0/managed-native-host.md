# Managed native host profile v0.1

A MacCompanion-owned Sunshine process is subordinate to the existing authenticated
Control enrollment. It starts only after the indexed native enrollment signature
has admitted one complete client certificate for the immutable approved display
and original Control deadline. It cannot provide an independent approval path.

The process owner and supervisor enforce the existing Control maximum lifetime
of four hours (14,400 seconds). They reject an expired or longer remaining
lifetime and retain the supplied original deadline; native activation or lease
renewal cannot extend it.

The process owner supplies `MACCOMPANION_MANAGED_ENROLLMENT=1` at spawn. In this
profile the host must not start its configuration Web UI or plaintext HTTP
listener. Its authenticated HTTPS routes are limited to serverinfo, applist,
launch and cancel. Native pair, resume and application asset routes are absent.
The sole application is Desktop. Native input, audio and UPnP remain disabled.
The profile does not change certificate admission or signing semantics.

The owner configures both LAN and WAN encryption modes as mandatory (`2`).
Authenticated launch without encrypted RTSP support (`corever` absent or `0`)
is denied with status 403 and no game session. Accepted launch returns only an
`rtspenc` route; a plaintext RTSP request on that pending session is closed.
The upstream negotiated video/audio encryption requirements also remain mandatory.
These restrictions reuse the pinned upstream transport cryptography and existing
enrollment vectors; they introduce no new pairing or signing algorithm.

The environment flag is a local trusted process setting, never a wire field or
client request. The owner explicitly clears inherited values before selecting
the profile. Reference experiments may select the upstream default profile for
comparison; those processes cannot serve as managed enrollment backends.

Loss of Control, original deadline expiry, parent death or host failure retires
the process and its private credentials. Retirement joins process termination
before admitting a replacement. A trusted local composition selects either
loopback IPv4 (`127.0.0.1`), all IPv4 interfaces (`0.0.0.0`), or dual-stack
interfaces (`::`, with Sunshine `address_family = both`). Remote requests
cannot choose this setting. The default component/test composition remains
loopback; the admitted normal Mac Debug composition selects dual-stack interfaces so
its paired phone can connect on the existing verified primary route. This does
not classify a route as LAN or authorize UPnP, discovery, a relay or release
packaging. Reachable IPv4 and IPv6 interfaces all retain mandatory encryption, exact
client certificate admission, sealed routes and the original Control bound.
The local readiness probe continues using loopback and the prepared certificate.
The primary may select IPv6 on the same local network; native listeners must
support that measured address without substituting an independently resolved
IPv4 address. IPv4 component compositions remain available for isolated tests.

Certificate generation explicitly selects a trusted local OpenSSL configuration.
The admitted bundled composition uses its catalog-bound `openssl.cnf`; component
tests use an empty configuration with the same explicit certificate options.
Generation cannot depend on the helper's compiled developer installation path.
A missing selected configuration fails closed. This changes no certificate
purpose, enrollment proof, signing bytes or approval requirement.

The native endpoint carries only its existing port base. The client uses the
address of its current verified primary route and must reject any stream URL
with a different address, port or unencrypted scheme. Listener reachability
alone cannot authorize enrollment, capture, input or a replacement primary.
Retirement must close network listeners before removing private state.

The manifest-indexed admission fixture names the mandatory checks. Public
fixtures contain no keys, certificates, private state or input content.

## Private Mac sample geometry

The menu may project App/Window capture geometry from its committed
ScreenCaptureKit selection. It must match the current session, epoch, surface,
surface/coordinate revisions, encoded and logical size, and unrotated descriptor
to the native scope. Source pixels derive from that selection's logical bounds
and backing scale, not the initial Desktop display's mode. A window projection
also requires its retained local window/process identity and exact input bounds;
an application projection requires its retained local application identity.
Physical identities and ScreenCaptureKit objects remain non-Codable and local
to the menu. A pending/uncommitted selection, expired lease or mismatched scope
cannot expose a retained native selection.

This projection alone grants no native enrollment or input. App/Window native
enrollment requires the current acknowledged replacement descriptor, a matching
retained selection, a fresh managed operation and its selected filter. The
selected adapter's actual sample evidence and the new renderer's correlated
presentation receipt are required before input admission. Component frame
evidence does not by itself establish normal-app playback or release readiness.
The indexed `native-selected-capture-projection-v0.1.json` records this local
geometry contract.

A local selected-surface stream adapter may consume a retained ScreenCaptureKit
filter with immutable source geometry and aspect-fit output configuration. Its
constructor is inert. Before starting and before every delivered frame it must
check its injected current-selection/Control predicate. Start, frame delivery,
revocation and Stop are serialized; Stop fences frames immediately and terminal
completion follows the stream's stop acknowledgement. A late start completion
cannot reopen a stopped capture. Idle/blank frames cannot refresh evidence;
complete frames must have current monotonic display time, exact image/format
dimensions, full encoded clean aperture and matching aspect-fit content placement.
The display time must increase and be no more than two seconds old; a WindowServer
timestamp up to 100 milliseconds ahead of a fresh local clock read is admitted
for scheduled display and measurement skew. A larger future offset is malformed.
`SCStreamFrameInfoScaleFactor` maps the content rectangle into encoded pixels;
`SCStreamFrameInfoContentScale` must be finite, positive and bounded but may
reflect ScreenCaptureKit resampling of the native source. The latter cannot be
equated to the menu's approved output pixel size. The selected target and
configured output geometry still require separate exact checks.
Malformed or changed complete samples terminate the capture. Failure must
propagate to Sunshine's streaming and encoder-probe results; waking
a capture waiter without an accepted image cannot report successful capture.
The adapter has no pairing, permission prompt, independent approval or input API, and does not
change native App/Window enrollment admission. The indexed
`native-selected-stream-lifecycle-v0.1.json` records this component contract.

### Private selected capture spawn context

An explicitly admitted local backend may project a committed App/Window
selection into `selected-capture.json` in that operation's private 0700 directory.
This is a closed, at-most-4096-byte canonical JSON spawn context with mode 0600,
owner UID, one regular-file link and no symlink traversal. It is not an Agent,
application or remote protocol message. Its local physical display/window/process
identifiers may reach only the exact owned capture child, never Agent IPC or the
network. ScreenCaptureKit objects remain in their respective process.

The parent matches the selection's complete existing native authority, public
key and geometry before writing the context. The record binds the exact native
operation ID, original Control expiry, selected process launch instance, kind,
bundle identity, display/window identity, global bounds, scale and source/encoded
dimensions. The child requires the managed profile, exact private path,
operation/display and encoded mode. Inherited selection-path values are cleared.
The parent resolves its existing private root with POSIX `realpath` before
creating the operation directory and passing its path to the child. The child
walks every literal path component with no-follow directory opens; a symlinked
alias such as `/tmp` is rejected even when it resolves to the same directory.
Unknown fields, duplicates, malformed/noncanonical records, unsafe file topology,
wrong operation/mode or expired/overlong lifetimes fail closed without falling
back to Desktop.

Before resolving a new filter and before every accepted frame, the child checks
the same live process launch instance, source bounds, display rotation and scale.
Window capture uses a desktop-independent window filter for that exact owner.
Selected App/Window streams explicitly set their output destination rectangle to
the centered aspect-fit rectangle of the admitted source and encoded dimensions.
Platform default top-left placement cannot stand in for that geometry. Complete
frame metadata must still match the centered rectangle within one encoded pixel;
this repair does not relax sample, owner, expiry or input checks.
Application capture includes only that app on the selected display, with the
existing 24-point padded/clipped visible-window crop. Moving, resizing, closing,
replacing or changing the selected content requires a new admitted selection.
Application crop resolution and both live geometry checks use on-screen,
nonempty layer-zero windows owned by the exact application. Desktop/background
and elevated overlay windows cannot enlarge that crop. Private Core Graphics
and ScreenCaptureKit inventories must apply the same layer rule.

After a locally owned native backend retires, an exactly matched health command
may return `active=false` with no capture evidence, certificate, port or input
admission. The menu retains at most 64 complete retired backend/operation/scope
bindings for this non-authorizing observation. Unknown or mismatched bindings
remain unavailable; a retired health observation cannot affect a newer backend.
Retirement fences native input and joins the child before publishing inactivity.
A current client may make one explicit Desktop selection after an App/Window
native connection failure. This is a fresh acknowledged replacement under the
same Control authority and original expiry, not continuation of stale geometry.
Input resumes only after fresh native presentation acknowledgement. Stop,
backgrounding, authority loss, expiry, and another selection cancel recovery.
Capture permission is preflighted; the child cannot request a permission prompt.
It does not extend the parent's original deadline or provide independent approval.

The indexed `native-selected-capture-context-v0.1.json` provides synthetic local
records and denial requirements. Existing native signature bytes and golden
vectors remain unchanged: this context cannot replace their proof or the runtime
fence. Normal App/Window enrollment follows the authenticated replacement
clean-frame acknowledgement and drains the prior native renderer, TLS identity
and enrollment before creating this new operation context.

The menu backend owner may route its exact committed target into private
backend preparation. A missing selected object means Desktop only when the
active descriptor is Desktop; a missing, pending or replaced App/Window target
is an error. The owner must recheck the same session, lease, surface revisions,
geometry and local target while preparing and during each health/input fence.
The local route supplies no new Agent, client or process authority. An absent
selected object cannot start an App/Window backend or fall back to Desktop.

The opaque lease display and the physical capture display are distinct local
facts for Window. The opaque display must continue to resolve to its original
physical display, while the exact committed window supplies its own current
physical display, bounds and backing scale. Window capture may therefore reside
on another display. Desktop uses the opaque display's physical mapping;
Application retains its selected-display crop. Every health/input check must
revalidate both the unchanged opaque mapping and the immutable selected capture;
moving the window between displays requires fresh selection. Neither physical
identifier crosses Agent IPC or changes the existing native signature scope.

Before deleting a retired operation's private state, the menu may retain closed
capture/encoder diagnostic codes from at most the final 64 KiB of each owned
child log. This excludes raw log text, request URLs, credentials, input content,
selection identities, bounds and pixels. Diagnostics do not confer admission or
change retirement; expected encoder probes may also emit codes.

The managed Mac adapter supplies an operation ID, private geometry-report path
and exact expected encoded dimensions in a closed local spawn context. Inherited
values are cleared. Managed launch rejects a missing/different requested video
mode; the first profile accepts exactly the admitted width×height×60 mode.
RTSP stream negotiation must independently use the same dimensions and frame
rate; a matching HTTPS query cannot authorize a different announced stream.
This is a backend geometry restriction, not new certificate/signature admission.

The pinned Mac AVFoundation capture path emits bounded atomic sample metadata
only in this managed context. It records its initial display-mode pixel size,
actual CVPixelBuffer and CMVideoFormatDescription dimensions, actual clean
aperture, configured aspect-fit scaling, sample sequence and monotonic time.
It carries no image, input, key, certificate, physical display ID or route.
The path belongs to the operation's private directory and is deleted on drain.

A geometry observation is usable only for that current, running operation after
exact scope/capture-mode revalidation. The report must be canonical sorted JSON of at most 2048 bytes and have the closed
`maccompanion.native-capture-evidence.v0.1` shape, agree with expected encoded
and source dimensions, use configured aspect-fit, have a full encoded clean
aperture, and have a recent positive sample sequence/time (at most 2 seconds old;
future time is denied). Missing/stale reports are pending, not input authority.
Malformed or mismatched reports fail closed. Actual sample dimensions are not
inferred from the launch request or the physical display measurement alone.

Native input remains disabled. This observation does not prove client decode or
presentation and cannot replace a correlated native presentation acknowledgement.
The initial profile remains unrotated, uncropped Desktop with aspect-fit padding.

## Local bounded input executor

A trusted local composition may request a bounded input batch from the exact
active operation. Unsupported backends refuse it. This internal execution API
does not create a remote input route or presentation grant. Sunshine keyboard,
mouse and controller routes remain disabled.

The managed backend requires an injected atomic Control/process permit. While
that permit is held, it synchronously verifies the running operation, original
Control bound, current short lease deadline, current physical capture-mode
geometry and fresh actual sample metadata before invoking one synchronous batch.
There is no suspension between these final checks and the batch. A previous
watchdog or pre-activation observation does not suffice. Missing/stale/malformed
samples, changed geometry, ended process, revocation or unsupported atomic permit
refuse posting. Retiring the owner revokes this permit before awaiting drain.

The menu binds physical display resolution and capture geometry into its local
permit before passing it to the backend factory. Its final guard re-resolves the
selected display and repeats geometry measurement under the same permit lock.
The backend must not call the permit's separate read-only status getter while
inside that lock. Presentation admission and runtime installation are still
required separately; this executor alone cannot enable client input.

## Production wrapper composition

The first-party process and enrollment wrappers may live in the normal Mac
platform module without admitting foreign binaries. They consume the same
menu-owned Control/capture permit and original deadline described above.
Production construction selects artifacts only through a trusted local
validator. The backend factory checks the permit before and after that
synchronous validation; rejected artifacts or a revoked permit cannot construct
or start a child. A public wrapper, file URL, package signature or successful
reference experiment does not admit a new remote authority or permanent binary.
The normal app must keep its factory unavailable until the corresponding local
artifact/dependency/signature admission supplies this validator. No experiment
implementation is linked into a permanent target by a compatibility alias.


## Bundled development selection

The normal Mac Debug composition may select the exact locally admitted development
host catalog from the containing app's sealed resources. Its catalog digest is a
compiled local authority, not a digest supplied by a client or by the catalog
itself. A valid containing-app signature for the existing menu identity, an exact
catalog, a complete matching regular-file inventory, and the current Control permit
are required. Missing resources remain unavailable; changed files, symlinks and
unlisted files reject selection. The executable locations are fixed inside the
bundle. Release composition does not select this development authority. No network,
pairing, approval, certificate or operation-signature semantics change.
Refreshing the development host requires rebuilding the complete package inventory,
pinning its newly computed catalog digest in both the normal Mac Debug selector
and staging tool, and rechecking the signed containing app. An earlier catalog
must never authorize a new package by name or version alone.
Native enrollment retirement alone does not revoke the primary Control grant.
When the native owner reports enrollment loss after an acknowledged App/Window
presentation, the client MUST obtain a fresh current primary Control state before
the single Desktop recovery attempt. Control revocation, inactive foreground,
or the original deadline prevents recovery; no native receipt renews Control.
