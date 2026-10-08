# Normal iPhone native composition hook

Date: 2026-09-27. Normal first-party wiring; experimental engine admission remains separate.

## Changes

The normal iPhone workspace now forwards its optional initial Desktop product factory into the existing Control coordinator. `IOSClientReleaseApplicationV1` accepts an optional native adapter constructor and resolves its signer from the sole durable paired host and existing protected custody. The factory is scoped to that workspace's primary state and interactive-role owner; its route reader checks the selected authenticated connection each time rather than retaining an IP address.

`UIKitClientNativeVideoCompositionV1` constructs a new normal Desktop product and native preparer for each Control request. Constructor/configuration failure closes the preparer and product. Observe and Act retain their existing owners and grants. The default app supplies no native adapter, so no additional signer is resolved on that path.

The signed Simulator harness now uses this shared normal composition instead of its duplicate product construction. It still supplies the experimental adapter outside permanent targets. No experiment is linked into the normal app and no target identifiers, signing, Keychain groups, permissions, wire records or grant semantics changed.

## Retirement regression

The first live attempt displayed video and admitted input, then failed its background assertion because the primary connection was unexpectedly replaced. Its evidence is `/private/tmp/maccompanion-agent-xpc-evidence.zelfuc2n`.

The first extraction had also forwarded terminal native notifications to the whole Control coordinator. That differed from the existing owner's typed failure and joined blank/drain behavior, and could start competing product retirement during background teardown. This extra callback was removed. Native phase notification remains observational; preparation/construction errors still follow the existing product failure path. The repeat run's acceptance is recorded below. The initial attempt is retained as a failed run rather than included in passing counts.

## Build and component evidence

- Final normal iPhone Simulator build: `/private/tmp/maccompanion-normal-native-composition-build-final-v2.log`, stable Xcode, `BUILD SUCCEEDED`; unsigned development build, no installation claim.
- Both native SDK builds, component tests and six-framework inventory: `/private/tmp/maccompanion-native-normal-hook-final-components.log`, exited zero. Twelve component tests passed.
- Final native source-input SHA-256: `7c73601ea632c247fdf7b0a34f876584a0603887bf481ed91096bbe8d65de5e4`.
- Shared composition SHA-256: `78d99e73e0df4453c5fbcbdc33a9542be62a3ab9281668d8321fa990625451c7`.
- Stable repository validation: `/private/tmp/maccompanion-normal-native-hook-handoff-validation.log`, exited zero with 109 indexed fixtures.

The earlier source-delivery archive binds the earlier tested snapshot. It has not been silently relabeled as the source packet for these new native artifacts.

## Final live acceptance

The corrected run passed: `/private/tmp/maccompanion-agent-xpc-evidence.8vwd45fw/signed-simulator-report.json` (report SHA-256 `4dd9cddca39064349c08b2bd809f03219b4e8e1593a40a3b26c355e5f7e60afb`). One XCTest completed with zero failures across four visible native sessions, in 235.954 seconds including setup and cleanup.

Actual managed-host video, current capture geometry, correlated presentation receipt and native input permit passed. Pointer, direct iOS typing, Shift+Tab and Copy reached the synthetic posting sink behind the real host permit. Background blanking/keyboard retirement retained the primary; route loss drained Control and required a fresh primary and explicit Control request. Stop preserved Observe, restart passed, and owned-process cleanup was verified.

The source-built portable host package was verified before and after the run (manifest SHA-256 `57c2da8f82672ff585f2c541a5f21414c9e7c618ccd32632ee311bb633ed0056`). Capture was 5120×2134 pixels, logical bounds 2560×1067 points and encoded video 1920×800 in all four sessions. The combined live-test source SHA-256 is `038e7ff4a83a1f82c7123f3118628f3583b0c1ffafcdfa601c1cd744f09ebdbd`.

This is a generated signed test composition using the shared normal code. Test key custody/local consent, finite bootstrap, indicator and final input effects remain substitutes. Real system input, normal installed apps, LAN and physical-device behavior are unproved.

## Remaining product work

The normal app's adapter and Mac host factories remain unset. Next is admitting the production managed host's code identity and actual capture/TCC ownership, promoting reviewed native components into the production dependency/build graph, then selecting them in both normal apps. Complete source assembly/rebuild and release evidence remain independent open work. Development-only work can continue where the actual dependency/process gates allow it.

Signed normal-app installation, actual system input, LAN and physical iPhone acceptance, focused native App/Window capture and visible-area bitrate remain open. This hook does not claim the usable engine replacement is finished.
