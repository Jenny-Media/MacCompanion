# Shared Display native video recovery

Date: 2026-10-02 UTC (2026-10-01 local). This follows the
[enrollment ownership checkpoint](2026-10-01-native-owner-usability-and-source-preparation.md).

## Reproduced failures and repairs

The user reports that the installed iPhone 18 Pro Max briefly displays video,
then shows "Remote Control needs to restart" after changing Shared Display.
The investigation reproduced two failures in the normal client Simulator journey:

1. Opening the full-screen Shared Display picker could retire the admitted native
   renderer before a display change was sent. The baseline UI test failed while
   opening the picker and showed the same restart banner. Shared Display now uses
   a sheet, preserving the renderer's visible window hierarchy. Foreground,
   visibility, deadline, authority, and input admission checks remain enforced.
2. After that repair, selecting another display reached the acknowledged runtime,
   but fresh native enrollment was rejected. Content-free host diagnostics showed
   matching display, generation and deadline, with only the revision ordering
   failing. Authenticated menu publication advances on display changes; visible
   Control activity advances on show/clear. These are independent counters.

The normative specifications and two manifest-indexed fixtures were updated
before correcting the runtime receipt and native snapshot guards. Both counters
must remain positive and current within their own authority. Exact menu generation,
installed command, lease, session, display, acknowledged surface, primary, key,
deadline, and stable joined-snapshot checks remain required. Wire messages,
cryptographic material, signatures, pairing, and independent grants are unchanged.

The indexed cases cover activity ahead of publication, activity behind publication,
multiple display publications, zero activity, and another menu generation. Both
targeted regressions fail before the guard correction and pass afterwards. Existing
golden cryptographic vectors and native revocation/drain tests continue to pass.

Native owner diagnostics now retain only closed phase/presentation failure codes,
and native driver diagnostics retain numeric failure codes. They record no pixels,
input, keys, identities, or display geometry.

## Verification

- Full `bash scripts/validate.sh` passes on stable Xcode 27.0, with 118 indexed
  fixtures. The final run also covers the corrected QA presentation count.
- The native bridge suite passes 11 tests; both targeted runtime authority tests
  pass, including denial of zero activity and another generation.
- Both native client SDKs rebuild with input fingerprint
  `ef312f747c88b09fc6b17b1e207982acf8e8556f5100095027360c54038718af`.
  The embedded native lifecycle suite passes all 16 tests.
- The complete normal-client Simulator journey passes opening/closing Shared
  Display, switching to another physical display and back, selecting the searched
  real Window, keyboard/pointer/modifier/shortcut delivery, Stop and a new session.
  Five fresh native presentations, exact test-key deletion, managed-host cleanup,
  and restoration of the original Simulator app/data are verified.
- The disposable signed QA menu now publishes the same authenticated display
  admission update used by the normal Mac menu. Its earlier no-op callback could
  not exercise that production transition faithfully.

Simulator evidence substitutes human Mac consent and final input effects. It
does not establish acceptance on the user's physical phone. The first expanded
passing UI run retained an obsolete three-presentation assertion in its report;
the final rerun corrects that count and passes all evidence checks.

## Installed development apps

The normal signed development iOS app is installed and launched on the freshly
verified physical iPhone 18 Pro Max. Its application identity, signed entitlements,
and provisioning support are verified. Signed executable SHA-256:
`c6faf64daea26eb5c2f79202058177eb0f06bf68ca69602f573627b9975f4d87`.

The repaired normal Mac app is installed at
`/Users/yihong/Applications/Mac Companion.app`. Its existing Agent service is
restarted with the new executable. Strict containing signature verification,
existing Agent Keychain groups, and all 119 bundled host files are verified.
The host's existing catalog remains
`e6a46019ecbd18104400ef5a1891f05691029c1cb547bbcb44def70c7a67bb8f`;
the Sunshine implementation did not need modification for these Agent/client
repairs. The previous signed app is recoverable at
`/private/tmp/maccompanion-mac-pre-shared-display-fix-20261002.app`.

The restarted Agent's listener becomes ready, and two saved-pair authentications
succeed after installation. On 2026-10-02 local, the user reports "it works now"
in response to the requested physical iPhone 18 Pro Max Shared Display retry.
This records user confirmation of the repaired display flow; it does not establish
additional physical input, recovery, or elapsed-soak acceptance. Existing pairing
data is retained. Production release admission, physical
recovery/elapsed soak, signing/notarization and source-delivery review remain open.
The prior frozen source archive documents the earlier checkpoint and does not
contain these new repairs.

## Private evidence

Reports, device identifiers and runtime logs remain outside the repository:

- Baseline picker failure: `/private/tmp/maccompanion-native-display-switch-before-20261002-v4/report.json`.
- Revision rejection after the picker repair: `/private/tmp/maccompanion-native-shared-display-fixed-20261002/report.json`.
- Deterministic regression before/after: `/private/tmp/maccompanion-display-counter-regression-before-20261002.log` and `/private/tmp/maccompanion-display-counter-regression-after-20261002.log`.
- Complete passing journey: `/private/tmp/maccompanion-native-shared-display-fixed-20261002-v3/report.json`.
- Final full validation: `/private/tmp/maccompanion-shared-display-installed-validation-20261002.log`.
- Both native SDKs and lifecycle tests: `/private/tmp/maccompanion-native-view-diagnostics-20261002/native-video-candidate-inventory.json` and its `logs/embedded-lifecycle-tests.log`.
- Verified Mac installation: `/private/tmp/maccompanion-mac-shared-display-installed-20261002.json`.
- iPhone signature, installation and launch: `/private/tmp/maccompanion-iphone18-shared-display-signature-20261002.json`, `/private/tmp/maccompanion-iphone18-shared-display-install-20261002.json`, and `/private/tmp/maccompanion-iphone18-shared-display-launch-20261002.json`.
