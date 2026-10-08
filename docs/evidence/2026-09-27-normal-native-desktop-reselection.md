# Normal iOS native Desktop reselection in Simulator

## Verified result

The normal iOS Debug app completes live pairing, restores its saved route, and
opens Control against the signed disposable Mac Agent/menu and source-built
Sunshine host. Within the first native Control session, the user selects a new
Desktop surface. The client drains the old renderer and enrollment, sends the
reliable input reset, accepts the host's replacement surface, and enrolls and
presents a fresh Moonlight stream. The host records a second native presentation
with current input admission. Keyboard, pointer, Shift+Tab and Copy are delivered
after the switch. Stop retires capture and input, and a later explicit Control
request presents a third native stream without pairing again.

The one normal-app UI journey and the exact owned-key cleanup test pass. The
runner verifies Agent/menu/host cleanup and restores the dedicated QA
Simulator's original app and data. The final input sink is synthetic and Mac
human consent is substituted by the separate signed test process. This is not
an installed Mac GUI/TCC, paired LAN, physical iPhone or App/Window playback
result. No screenshot or typed content is retained in source.

## Failure and repair

The first reselection attempt closed Control because native backend retirement
revoked the old input permit before the reliable reset reached the menu on its
independent socket. The runtime now drains only the exact current reset under
that revoked permit, advances reliability bookkeeping and releases input without
posting through the revoked permit. Other input stays denied. The normative
runtime contract and indexed fixture describe the drain. The client also stops
submitting old-surface pixels to the renderer while keeping media validation
active during native replacement.

The disposable Desktop target initially used a 64×48 encoded size, below native
enrollment's 320×240 minimum. A second attempt used 320×240 logical dimensions,
which did not match the Mac display's measured bounds. The test target now uses
the same measured display layout and capture profile as initial Desktop
preparation. Neither failure justified relaxing production snapshot or geometry
checks. The UI test scrolls back to the modifier row after tapping Tab, because
that row can leave the visible sheet during shortcut testing.

## Evidence boundary

Stable Xcode 27.0, iOS 27.0 QA Simulator
`8FF65ABB-572E-4EE4-9A9F-F61AA302A586`.

- Normal UI journey: one passed, zero failed; three current native presentation
  and input-admission receipts, including the replacement stream.
- Exact owned pair-key cleanup: one passed, zero failed.
- Indexed fixture validator: 115 passed; `git diff --check` passed.
- Stable `bash scripts/validate.sh` passed. The first sandboxed attempt could
  not write Swift's external compiler cache; the rerun with normal cache access
  completed. Validation log:
  `/private/tmp/maccompanion-native-surface-final-validation-escalated-20260927.log`,
  SHA-256 `30ded03d587213b23665f44222cbf9ccf6886bb9cd0fedc195e73a0e8f68681b`.
- Source-built iOS application SHA-256:
  `b86bef8638b6282c36b6573c8b6567d935e142102795963a1c2d4da81e9f386a`.
- Normal source-input SHA-256:
  `8eee684ce294e6509cbdec4c56ff688bfd0b35efc9f2cc8920ddd3d83c63ecec`.
- Disposable host source SHA-256:
  `5131d1f7d27e0d6595ffac5fd1e16cdc10a9627a4692e9aa88e0fe265338286b`.
- Verified native host package manifest SHA-256:
  `c05935f56240b4ab42af893ac4b9b54f09f798feb1028417f5c5b6ddd3c862e7`.

Private local report: `/private/tmp/maccompanion-native-surface-final-simulator-20260927/report.json`,
SHA-256 `e7924905c60699aa97f74389f843485393164eefd8d999938a8cfa88f2569862`.
Its UI result and host records are in that directory and
`/private/tmp/maccompanion-agent-xpc-evidence.uz1skaa_`. These are test-only
evidence and must not be committed.

The remaining work is normal App/Window selection with actual selected capture
and a fresh native presentation; viewport bitrate; current corresponding-source
assembly; installed Mac GUI/TCC and paired LAN/physical acceptance. Desktop
reselection does not satisfy those gates.
