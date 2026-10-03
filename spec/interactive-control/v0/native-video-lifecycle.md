# Native video session lifecycle v0.1

Status: normative local lifecycle boundary; no new remote message is admitted.

The approved Sunshine/Moonlight candidate keeps application authentication,
pairing, approval, and input on the existing MacCompanion authorities. This
boundary admits only local bookkeeping, not an engine endpoint, dependency,
credential, or new way to acknowledge the existing media role.

The authenticated Control owner supplies the exact host identity and pin, client
identity, primary connection ID, Interactive session ID, authorization epoch,
grant and policy revisions, local Control generation, and original monotonic
deadline. The immutable binding uses the same fields as the existing media lease.
The local deadline is in the authoritative owner's clock domain; a host timestamp
must never be compared directly with a client's monotonic clock.

One capture configuration has an immutable surface ID, surface revision,
coordinate-space revision, and encoded width/height. Encoded dimensions must be
320…8192 by 240…8192. A locally minted increasing generation identifies each
native connection. Native sockets and decoder callbacks must drain before another
generation is reserved. Foreground return cannot reset the deadline or resume a
retired session. A replacement surface requires a new approved capture binding.
The supported native kinds are Desktop, App and Window. Focused region requires
its own later capture and input contract. The App/Window descriptor is admitted
only after the existing replacement clean-frame acknowledgement, followed by a
fresh native enrollment and selected capture context. Old renderer generation,
enrollment proof and input authorization cannot move to the replacement.
The optional connection-preserving profile in
`spec/capability-protocol/v0/native-stream-continuity.md` retains certificates
and sockets only with a fresh proof, frame epoch and presentation receipt. It
does not retain the old surface's renderer generation or input authorization.
Until both normal-app adapters admit that complete profile, the replacement
path below remains required.
During a native surface choice, the client continues validating records on the
existing authenticated media role but does not submit old-surface frames to the
renderer after that surface is fenced. New-surface records still require the
existing clean-frame render and acknowledgement before a fresh native enrollment.
Malformed media or a failed media role remains terminal; suppressing stale visual
output does not weaken media admission.

A display choice during native playback uses that same replacement lifecycle.
Fence input and drain the current native renderer, enrollment and preparation
before sending the existing authenticated Desktop replacement for the selected
opaque display. The new display must render and acknowledge its bootstrap frame
before fresh native enrollment. Input resumes only after the exact new native
presentation receipt. A display choice does not reuse old capture geometry,
renderer generation or input admission, or change pairing and approval semantics.

Every preparation, callback, and presentation query revalidates the exact binding
and deadline. An identity/revision/deadline mismatch retires the session and
requires teardown. Stale-generation events are rejected without mutating a newer
connection. A current connection failure retires it, clears presentation, and
retains a bounded typed failure for the UI. Stop is terminal, including while
connecting. Draining completion is accepted only for the retiring generation.
When native retirement races the old-surface input socket, a revoked native
posting permit cannot make the client's exact terminal reset fatal. The same
release-only rule applies while native preparation has paused input and no
posting permit has been installed. The runtime
drains only that reset under the current or immediately retired surface fence,
without posting input or restoring native admission. Other input stays denied.

A connected callback is not a displayed frame. A first-frame callback must also
match the immutable capture dimensions. It can move local presentation to
`displaying`; it cannot satisfy the existing media clean-frame acknowledgement or
enable input. Input remains disabled until a separately specified and admitted
native presentation proof is connected to the host's input gate. This is explicit
in the owner API rather than inferred from a visible UIView.

The sole fixture index is `spec/fixtures/manifest.json`. Its native lifecycle
cases cover failure visibility, replacement after drain, callback retirement,
Stop races, expiry, revocation, dimension mismatch, and surface mismatch.
No new application-authentication or pairing cryptography is implemented here.

The optional native presentation acknowledgement seam requires an exact current
`displaying` owner, admitted encoded geometry, attached visible view hierarchy,
foreground-active window scene/application and a renderer-specific check that its
first frame is ready for display. An IDR enqueue or connected callback cannot
substitute for this renderer check. Default drivers report no readiness. Reserve
one acknowledgement task per renderer generation; revalidate all local conditions
and current binding after the correlated host receipt. Stop/retirement cancels
that task, and late completion cannot mark a replacement acknowledged. This
acknowledgement remains independent of a displayed frame; input requires the
affirmative correlated host receipt described below.

## Client input admission

The current foreground displaying owner may consume only its exact validated
primary presentation receipt. It requires inputAdmitted true, matching session,
epoch, surface/revisions, renderer generation and encoded dimensions, and logical
dimensions matching the admitted surface. It constructs native content geometry
from the receipt's trusted capture/encoded/logical dimensions. False receipts keep
video observation-only. Missing/mismatched/invalid geometry cannot enable input.

Revalidate renderer readiness, original deadline, current binding, visible attached
view and active application/window scene after the acknowledgement await. Stage
geometry into only that owner's native video view before publishing input admission.
Every emitted keyboard/pointer action checks this current local admission again;
foreground/readiness loss, Stop, expiry, revocation or renderer replacement disables
input and clears geometry. A stale completion cannot admit a replacement renderer.

Existing Control classes, focus checks, input sequence and host runtime posting
authority remain independent. Native input supports Desktop, App and Window with
direct keyboard, modifiers, shortcuts and pointer controls. Direct keyboard uses
the current acknowledged surface and existing secure-focus refusal; it does not
automatically change capture to an unsupported focused region. Native content
mapping excludes aspect-fit padding. Each App/Window transition requires its own
renderer enrollment and capture admission.

Entering application background synchronously retires the current native generation
and clears input admission before awaiting decoder/network drain. The owner must
observe the platform background event; periodic readiness polling alone is
insufficient because suspension can prevent it from running. Foreground return
cannot restore that generation's input admission; a fresh explicit Control/native
enrollment is required. Primary-channel background grace remains independent.

After the exact bootstrap surface's clean-frame acknowledgement commits, native
video construction suppresses further legacy decoding for that surface. The
media role continues full header, payload, sequence and authority validation;
suppression grants no native presentation or input authority. This prevents a
hidden legacy VideoToolbox decoder from failing a native session on background.
A fresh replacement surface remains eligible for its own bootstrap render and
acknowledgement. Role EOF and malformed media remain terminal. The indexed
`native-bootstrap-rendering-v0.1.json` fixture records these local rules.
