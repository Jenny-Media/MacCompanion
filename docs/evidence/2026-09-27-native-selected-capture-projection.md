# Selected App/Window native capture prerequisite

## Implemented

The normative managed-host contract and sole fixture manifest were updated
before implementation. The menu can now project native content geometry from a
retained App/Window ScreenCaptureKit selection, using its logical bounds and
backing scale rather than the initial Desktop display's full pixel mode.

Projection requires the exact session, epoch, surface and coordinate revisions,
encoded/logical dimensions and unrotated descriptor. Window selection requires
a valid local window/process/bundle identity and matching retained bounds;
application selection requires its local process/bundle identity. Invalid,
nonfinite, changed or oversized geometry is rejected. Physical identities and
ScreenCaptureKit objects remain local and are not added to IPC or remote fields.

The surface owner retains the selected capture object only when the existing
surface transition commits. Its native accessor rejects a pending/taken
selection, missing retained selection, mismatched descriptor/scope or expired
lease/Control deadline. Invalidation removes the active selection.

## Verification

Stable Xcode focused tests pass: four test functions, including four App/Window
and 1x/2x scale combinations. They check source dimensions, negative display
origins, exact descriptor binding, wrong owner kinds/identities, changed bounds,
invalid scales and oversized source pixels. The unbound/invalidated accessor
returns unavailable. Successful committed ScreenCaptureKit object access and
each live transition/expiry branch have not been exercised by these tests.
An initial test used an incorrect dictionary encoding for revision wrappers;
it was corrected to their canonical scalar encoding before the passing run.

The existing Desktop mode-pixel regression also passes. Required stable
`bash scripts/validate.sh` passes with 113 indexed JSON fixtures, package/lab
tests and platform builds. No new physical or normal Simulator playback result
is claimed for this source revision; these changes concern a menu-local Mac
prerequisite and have not been wired into normal native playback.

Private focused log:
`/private/tmp/maccompanion-selected-capture-tests-20260927.log`, SHA-256
`5089548a8528295526d3fa9296f108119ebcd5c7df335d476227ced1f14f6f61`.

Private code validation log:
`/private/tmp/maccompanion-selected-capture-validation-20260927.log`, SHA-256
`57cc1c78b81276107bc960d8f3987b4fc424276ba7300579dc5c6c74f3fb2bec`.

Tested geometry source SHA-256:
`affec641f625dc1883f88f246052cb0042ff8a199e73d5a79df9bb4241640f3b`.
Tested surface-owner source SHA-256:
`10d7c863d29093cd81c25d3dd21e90ce376473038e7ac7f8aca084bee76575c7`.

## Next integration

Native App/Window streaming remains unavailable. Sunshine currently captures
the whole display through AVFoundation; the managed backend factory still takes
a physical display, and native runtime/client enrollment remains Desktop-only.
The retained filter and projected dimensions do not prove actual captured pixels
or grant input. The previous normal three-session Simulator result is historical
and does not establish App/Window capture or validate this new source revision.

Next: implement isolated selected-surface capture in the managed host, bind its
private local selection to the exact current operation, and preserve drain,
revocation and encryption. Revalidate window/process identity and bounds during
capture and before input; movement, resize, close or replacement must not reuse
old input geometry. Application capture must exclude other applications rather
than merely cropping the Desktop. Verify actual sample dimensions and placement
before updating the normative enrollment/admission contract and opening the
existing native runtime/client gates. Rebuild pinned artifacts before the next
normal Simulator journey.

Visible-area bitrate, current corresponding-source assembly, installed normal
Mac GUI/TCC and paired LAN/physical acceptance remain separate pending work.
