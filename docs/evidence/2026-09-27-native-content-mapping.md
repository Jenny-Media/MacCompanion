# Native source content mapping

## Change

Native input must distinguish Mac logical points, capture-mode pixels, encoded
pixels and client viewport points. A wide Desktop can have padding inside the
encoded frame as well as padding around that frame in a phone viewport. Treating
the entire encoded frame as source content can turn a padding touch into a Mac
click.

The new shared geometry value retains the separate dimensions and computes a
centered aspect-fit source rectangle. The client projection fits the encoded
frame into the viewport, then projects its inner source rectangle. Existing
direct-touch and trackpad mapping use that rectangle; padding and the exact
right/bottom edges remain outside valid input. Malformed dimensions are rejected.
The primitive covers unrotated aspect-fit Desktop geometry only and grants no
presentation or input authority.

The normative local geometry document and authoritative fixture were created
and indexed before implementation. The sole fixture index is still
`spec/fixtures/manifest.json`. No new presentation wire record, signing
transcript, grant or pairing behavior was introduced.

## Verification

Stable Xcode 27.0 (27A266a). Final `bash scripts/validate.sh` passed, including
`nativeContentGeometryUsesAuthoritativeCasesAndRejectsPadding`; all 105 indexed
JSON fixtures validate. The geometry cases cover full-frame content, encoded
horizontal/vertical padding, nested viewport padding, Retina/chroma rounding,
and offset viewports. Each case checks the source rectangle, normalized center,
trackpad displacement and rejection of all four padding/half-open edges. Eight
malformed dimension combinations are rejected. `git diff --check` passed.

Private validation log:
`/private/tmp/maccompanion-native-content-validation.log`.

Both unsigned SDK component builds passed and match candidate input SHA-256
`64099ecdf14bd011f79c48bb3d980acaf1184c36d9cb420a6e3a94b359ad1c38`.
The source inventory now explicitly binds the new normative geometry document
and its indexed fixture. All six framework binaries match their SDK provenance
records. The inventory retains `releaseAdmitted: false`.

This checkpoint tests local geometry and compilation. It does not claim a new
Simulator video/input acceptance run. The preceding [host input pause checkpoint](2026-09-27-native-host-input-pause.md)
retains its live two-cycle video/Stop/restart and fifteen component-test evidence
at its own source hash. The new mapping API is not yet connected to native input.

## Next step

The native runtime snapshot currently projects encoded size but does not carry
the logical Desktop dimensions or trusted capture-mode dimensions needed by a
presentation receipt. The host must project and revalidate those fields under
the existing current Control/backend/surface fences. Backend clean-aperture
metadata must agree with the mathematical content rectangle; geometry alone
cannot prove a backend's actual image placement.

The native presentation acknowledgement must then release the host pause only
for the exact current presented generation and matching geometry. The client
must connect the admitted inner source rectangle to its normal controls and
disable input on native loss/Stop. Keyboard/modifier/shortcut/pointer and focus
acceptance remain pending. Both input gates remain closed for native video.
Permanent packaging/TCC admission, normal target composition, installation and
physical iPhone acceptance remain open.
