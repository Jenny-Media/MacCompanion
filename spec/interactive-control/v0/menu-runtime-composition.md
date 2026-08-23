# Interactive Control visible menu-app runtime composition v0.1

Status: normative for the bundle-independent single-owner runtime seam. Authenticated local-XPC lease lifecycle, initial-Desktop preparation, permanent menu-bar indicator, local stop, and monotonic expiry scheduling are implemented. Concrete ScreenCaptureKit, VideoToolbox, Accessibility, Core Graphics event, and media/input adapters remain platform work and require their own evidence.

## Ownership and admission

The permanent Agent primary dispatcher receives one stable fail-closed runtime
authority before local XPC construction. That authority contains no runtime at
construction. Only an exact authenticated-and-ready menu generation may bind
one concrete runtime owner, and every install/termination is serialized with
generation binding, invalidation, and replacement. A stale generation cannot
bind, a replacement cannot silently redirect an active session, and generation
loss terminates the bound session with `menuAppUnavailable` before a later
generation can bind. Terminal Agent teardown makes the authority permanently
unavailable.

Exactly one visible menu-app runtime owner serializes install, renewal, acknowledged revoke, lease expiry, and Agent-IPC invalidation. Actor reentrancy may enqueue another command but cannot overlap platform effects. No view model, capture callback, XPC callback, or remote channel owns execution state independently.

Install accepts only the typed local-IPC command and a current local monotonic
time inside both the 10-second execution lease and enclosing approved-session
deadline. It shows the persistent indicator, including the locally confirmed
device name, before starting capture. Install success is published only after
capture reports platform readiness for every interaction class in the lease and
a correlated receipt validates; it does not mean input is ready. The runtime
enters `requiresConfiguration(installCommandID)`, accepts an exact initial
configuration and clean keyframe, and remains input-denied until the separate
initial acknowledgement is accepted. Exact replay of the same installed
command returns the same receipt without repeating effects. A different install
while any session is active or terminating fails closed.

The local install command and capture adapter receive the complete validated
initial Desktop descriptor, including the exact lease binding established before
install. It may not reconstruct media authority from process state, unrelated
shared mutable state, or only the display/surface UUIDs. The menu revalidates
the descriptor's monotonic validity at install before the indicator or capture
performs any platform effect.

Before install, the Agent asks the same authenticated ready menu generation to
prepare the initial Desktop descriptor through the runtime transport's shared
single-flight gate. The request binds the session, authorization epoch, opaque
selected display, and exact interaction classes. The menu samples its own
monotonic clock and resolves physical display state only inside the menu
platform module. The returned descriptor is not an execution lease, starts no
capture or input, and is accepted only when exactly correlated and bound to the
request.

Renewal preserves the host, device, session, authorization epoch, selected display, surface, surface and coordinate revisions, and exact interaction classes. It replaces the lease ID, increments the counter exactly once, begins before the prior lease expires, is current at local receipt time, remains bounded to 10 seconds, and cannot outlive the approved-session deadline. Renewal performs no capture or indicator effects.

Surface replacement is a separate Agent-issued local command and cannot be represented as renewal. The command correlates one prior lease to one replacement lease and the complete new descriptor. It preserves host, device, session, authorization epoch, and selected display; uses a distinct lease; binds the replacement surface ID exactly to the descriptor; increments the lease counter exactly once; strictly advances both surface and coordinate revisions; keeps the replacement interaction classes within the session-approved classes; and requires those classes to equal the new descriptor. Its lifetime obeys the same current-time, 10-second, prior-lease-overlap, and approved-session-deadline bounds as renewal.

The runtime serializes a surface replacement before later input, media, renewal, revoke, or expiry work. It denies input immediately, releases every held input transition, and asks the capture adapter to suppress output and prepare the exact replacement source. Only after both effects succeed does it install the replacement lease and return a correlated prepared receipt. Preparation failure invokes full safety teardown because partial capture/filter state cannot be rolled back safely. Exact replay returns the original receipt without repeating effects; conflicting command reuse fails closed.

A prepared surface admits no input. Its media state accepts only a gap-free discontinuity under the replacement fence, then exact decoder configuration, then a clean access unit with matching dimensions. Delta video, old-fence media, configuration before discontinuity, or a second discontinuity is terminal. The runtime records the clean access-unit sequence and remains input-paused. A separate Agent-issued acknowledgement must correlate the transition command, replacement lease, complete surface fence including exact focus token/revision when the descriptor has focus, and that exact ready media sequence. Exact replay is effect-free. Only then does the runtime resume input admission. Renewal may extend the current replacement lease but cannot change or bypass its prepared/media/acknowledgement phase.

Every input action contains the already validated remote envelope plus a local execution fence. The menu runtime requires exact session, authorization epoch, surface, surface revision, and coordinate-revision agreement between them, then validates the full host/device/session/epoch/display/surface/revision lease and its current monotonic lifetime. Pointer, button, and scroll require `pointer`; physical-key and modifier events require `keyboard`; text requires `text`; reset widens no class but still requires the current lease. The bounded synchronous platform post occurs in that same serialized actor turn. Renewal, revoke, expiry, or IPC invalidation therefore cannot interleave between the last local lease check and the platform call. A denied or failed post returns no success and is never retried implicitly.

Every encoded media action similarly binds the binary header to the local fence and current lease, requires `view`, and carries a payload whose exact length and AVCC configuration/access-unit structure match the validated header. The runtime owns a gap-free media sequence across lease renewal and surface replacement. Exact replay of the latest command ID is effect-free only when the complete header-plus-payload SHA-256 is identical; a changed reuse fails closed. Any other duplicate or gap is denied before enqueue.

The media adapter is a session-bound bounded in-process queue with a synchronous all-or-nothing enqueue: `true` transfers ownership of the complete record, while `false` accepts no byte. Queue rejection terminates the runtime through the full safety cleanup and is never retried implicitly. The retained-frame blanking effect must also purge this queue, so accepted bytes cannot drain after revoke, expiry, IPC loss, or failure. XPC/network acknowledgement is downstream transport evidence and never retroactively changes runtime admission.

## Termination and recovery

All termination paths use this order. They attempt input release, capture stop,
and retained-frame blanking even when an earlier one fails. They clear the
indicator only after all three preceding safety effects are proven complete:

1. release all remotely held input;
2. stop capture;
3. blank the last retained frame;
4. clear the persistent indicator.

An acknowledged revoke returns success only after all four effects succeed and the receipt exactly matches the command, lease, and session. Exact replay returns the prior receipt without repeating effects. A partially failed cleanup retains content-free completion bits, denies new installs and renewals, and retries only incomplete effects. The indicator remains visible while input release, capture stop, or frame blanking is uncertain. It never claims idle or successful teardown while a step remains uncertain.

The menu-app composition root schedules expiry at the exact monotonic deadline published by the owner. Successful install arms that deadline and successful renewal atomically replaces it. Each scheduled callback is bound to one private token and exact deadline; cancellation or a stale callback cannot expire a replacement lease. An early callback reschedules only the remaining monotonic duration. At or after the exact deadline it terminates without waiting for Agent acknowledgement. Successful revoke, local stop, and authenticated Agent-IPC invalidation disarm the timer before teardown. None of these paths depends on receiving another IPC byte, media frame, input event, or wall-clock tick from the Agent.

Install failure runs the same four-step cleanup because an asynchronous platform call may have partially succeeded before returning an error. If cleanup completes, install returns a closed failure and the owner becomes idle. If cleanup remains uncertain, the owner enters safety-recovery-required denial.

## Platform adapter rule

The injected indicator, capture, input-posting, input-release, media-queue, and retained-frame interfaces are narrow effects, not authorities. The permanent menu indicator is process-owned and names the locally confirmed device in both its menu-bar state and open menu surface. Its Stop control remains visibly `stopping` until the serialized runtime cleanup clears it; failure restores a visible active state. Production cleanup adapters must be idempotent, and no adapter may infer a lease from process presence or return success before the underlying effect is externally true. The input-post and media-enqueue adapters perform one bounded synchronous action so no suspension creates a time-of-check gap. Final signed-target evidence must prove the visible indicator cannot be hidden while capture or input remains usable, expiry fires without traffic, IPC invalidation terminates, every key/button is released, capture stops, queued media is purged, and rendered retained content is blanked.
