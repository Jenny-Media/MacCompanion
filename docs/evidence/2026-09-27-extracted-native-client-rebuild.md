# Client engine rebuilt from the retained source packet

Date: 2026-09-27. Historical source-reconstruction evidence; no release admission.

`scripts/rebuild_native_source_client.py` rebuilt the retained iPhone and Simulator
client snapshot with its frozen engine builder and the previously rebuilt OpenSSL
libraries. It requires explicit source/dependency report pins, verifies archive
and extracted file maps, checks the active native source component revisions,
and validates every dependency file. Each XCFramework slice must exactly match
its pinned source-built framework's complete file map.

The frozen builder runs in a separate Python process. An explicit archive source
provider replaces its Git-checkout verifier with pinned file/revision verification;
an explicit dependency provider supplies the already verified source-built OpenSSL
XCFramework. The frozen builder and first-party snapshot are not rewritten, and
no Git history is fabricated. Provider/runner hashes and source bindings are
recorded. Bytecode creation is disabled so the retained payload stays unchanged.

The packet's prebuilt FFmpeg/SDL/Opus archives remain excluded. The active
moonlight-common-c and ENet components are complete, and the selected H.264/HEVC
engine references no FFmpeg parser symbols. This is not a rebuild of the complete
upstream reference application or an assertion that every unused vendor component
has a corresponding-source closure.

## Evidence

- Source packet: `/private/tmp/maccompanion-native-source-inputs-20260927-v2`.
  Manifest SHA256:
  `146be6eecba35e73aa7ff5d585cabfb4343fa6d2442fea6ae74a012424ee8216`.
- Historical native first-party input SHA256:
  `3d88c40f461e57dbbe2ac2daae5aa92b15aa396639a3cff2c7e003d76ba1a0e7`.
- Rebuilt dependency report SHA256:
  `ad949c6d1b2d4809a3469f811580710694cc76b23f9de971fa0748ee9747c9c9`.
- Final output: `/private/tmp/maccompanion-source-client-rebuild-20260927-v2`.
  Report: `rebuild-report.json`, SHA256
  `a44f4fac2c0f6808bb3897862e4cd28ead94a92670ad032e0d24a4663f1ef5ff`.
- Rebuild builder SHA256:
  `6f377e723c418666653733615b45a7bc73ec30d24bdc1cba982af6905012b91e`.
- Frozen engine builder SHA256:
  `4a46787520943672d8c853e64753a42de584a69f817bb5ce8a31493416f6fbc3`.
- Both SDK builds passed, producing engine, adapter and OpenSSL frameworks for
  each SDK. Twelve native component tests passed with zero failures in dedicated
  Simulator `8FF65ABB-572E-4EE4-9A9F-F61AA302A586` (iPhone 17, iOS 27.0).
- Frozen inventory-tool functions checked all six arm64 frameworks against their
  rebuild binary records, closed dynamic dependencies and parser-symbol rules.
  Inventory: `framework-inventory.json`, SHA256
  `2d970ad65e190e8268daae4aa9e393a9424349929a6113e7c7da66993db3e4be`.
- The first complete run passed; the final fresh run adds a full-file XCFramework
  slice-to-source-build check. Both outputs are retained. The final report proves
  immutable source payload and dependency readback.

- Required stable Xcode repository validation passed with 109 indexed fixtures:
  `/private/tmp/maccompanion-source-client-rebuild-final-validation.log`.

## Historical profile and remaining scope

The frozen snapshot includes `ReferenceNativeSurfaceProbe` in its adapter, as its
original builder did. These frameworks are not admitted as the newer normal-app
candidate and did not replace its artifacts. Current normal development inventory
still requires that reference implementation to be absent. The packet predates
the latest adapter promotion and production root selection.

No bit-identical reproduction or fresh playback through these historical client
frameworks is claimed. The earlier archive-host live tests used the separate
current client candidate. Current source snapshot assembly, rebuilt current
host/client acceptance, corresponding-source completion and permanent release
admission remain open. Normal paired Control, signed Mac GUI/TCC continuity,
physical installation, LAN/real input, App/Window capture and visible-area bitrate
remain open. No physical device or installed Mac application was modified.
