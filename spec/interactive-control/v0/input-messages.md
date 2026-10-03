# Interactive Control reliable input profile v0.1

Status: normative JSON schema and stream-state rules. Channel authentication, session approval, platform input injection, and surface-authority composition are separate prerequisites.

Each input message is a strict UTF-8 JSON object no larger than 65,536 bytes. Duplicate keys, floating-point numbers, unknown or missing fields, noncanonical UUIDs, unsafe integers, and unknown enum cases fail closed. The canonical encoder sorts keys and emits no insignificant whitespace.

## Envelope

Every message contains exactly:

| Field | Rule |
| --- | --- |
| `version` | `{ "major": 0, "minor": 1 }` |
| `messageID` | Lowercase canonical UUID; diagnostic correlation only, not replay authority |
| `interactiveSessionID` | Exact active session UUID |
| `authorizationEpoch` | Current value, at least 1 |
| `sequence` | Safe integer starting at 1 and increasing by exactly one |
| `clientMonotonicMilliseconds` | Nondecreasing safe integer; never compared with the host clock |
| `surfaceID` | Exact current session-scoped surface UUID |
| `surfaceRevision` | Exact current revision, at least 1 |
| `coordinateSpaceRevision` | Exact current revision, at least 1 |
| `focusToken`, `focusRevision` | Both null or both current. They fence an already selected focused-region surface when present; ordinary keyboard text does not require Accessibility focus discovery. |
| `input` | One closed tagged payload below |

The host revalidates the session, epoch, descriptor half-open lifetime, and complete surface/coordinate/focus fence immediately before execution. A valid JSON message alone never authorizes input.

## Payload union

`input.kind` selects the exact remaining keys:

- `pointerMove`: `x` and `y`, unsigned normalized 0–65,535.
- `button`: `button` is `primary` or `secondary`; `transition` is `down` or `up`.
- `scroll`: `unit` is `pixel` or `line`; signed integer `deltaX` and `deltaY` are each -4,096–4,096 and not both zero.
- `physicalKey`: USB HID keyboard-page `usage` 0x04–0xE7, `transition`, and an eight-bit `modifierMask` snapshot.
- `modifiers`: one eight-bit `modifierMask` ordered left Control, Shift, Option, Command, then the right variants from least to most significant bit.
- `text`: nonempty UTF-8 `text` of at most 4,096 bytes, without NUL. The host must be unlocked and the active descriptor must advertise both Keyboard and Text authority. Missing or ambiguous Accessibility focus does not disable ordinary keyboard entry; a positively identified secure focus still denies text. This never uses the clipboard.
- `reset`: no other payload keys; releases all remotely held buttons, keys, and modifiers.

Pointer motion may be coalesced before sequence assignment. Once assigned, reliable transport preserves every message. Button and key transitions are never coalesced. Repeated down, unmatched up, backward client time, a gap/duplicate sequence, invalid body, or stale fence is a protocol violation: no partial state is applied and the input channel closes after all held input is released.

The client dispatches input through one ordered worker with at most 256 pending
unsequenced payloads. Only adjacent pending absolute pointer moves may collapse
to their latest position; buttons, keys, modifiers, scroll and reset are ordering
barriers. On a surface fence, pending unsequenced input is discarded and the
already dispatched send is joined before assigning the old-surface reset.
Queued gestures from an earlier surface cannot enter the replacement. Overflow
fails closed. Ordinary pointer moves are paced locally before sequence assignment;
this does not change either host rate limit.

## Sliding rates and state

Using host monotonic receipt time, the host admits at most 240 total messages and 120 pointer moves in `(now - 1000 ms, now]`. The limits are independent. A rate rejection does not execute input; the channel is closed rather than permitting the sender to retry an ambiguous transition.

The host owns the pressed-button, pressed-key, and modifier sets. `reset`, channel loss, foreground-lease loss, IPC loss, lock, suspension, epoch change, session end, or any protocol violation releases all state. Text is denied while locked even if public APIs later prove ordinary physical-key operation on the genuine macOS lock surface.

The host data-plane owner starts only after the authenticated input and media
connections form one exact role pair. It reads the four-byte input length and
then exactly the declared body, rechecks the pair's session and authorization
epoch against every strict envelope, and forwards it only through the current
generation-bound menu route. It never treats network receipt as execution.
Failure or ambiguity cancels both role connections and requests exact session
termination; role bytes cannot install, renew, or broaden a lease.

`spec/fixtures/valid/interactive-input-physical-key.json` is the canonical envelope fixture. Invalid fixtures cover cross-field rules; implementation tests cover every union member, exact round trips, transition balance, rate boundaries, sequencing, and locked-text denial.
