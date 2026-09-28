# Native video owner and enrollment verifier checkpoint

Date: 2026-09-26. This is a component checkpoint, not completed normal-app
engine replacement, physical installation, or release acceptance.

## Implemented

- The normal UIKit surface has an exclusive native-video slot and the normal
  Desktop product has a native driver injection hook. The production native
  owner binds current Control identity, generation, immutable surface geometry,
  and original monotonic expiry. It blanks immediately on authority loss,
  rejects late callbacks, and awaits native teardown before releasing ownership.
- Failed/connecting native video covers old legacy video with an opaque view.
  Failure remains available as a typed status. Decoder visibility before
  connection admission cannot reveal a frame. A synchronous status consumer
  cannot recursively begin revocation teardown. Closed products cannot resume
  input through a late state refresh.
- The experimental Moonlight driver uses that production owner and surface.
  Frame dimensions come from the actual decoded Core Media format description.
  The H.264/HEVC component excludes the upstream AV1/FFmpeg parser and audio/input.
- The normative enrollment signing profile has an indexed P-256 golden vector.
  The production host challenge verifier binds the exact current primary,
  Control revisions, surface, session key, and certificate digests. Attempts
  consume the challenge once, even on rejection; its monotonic deadline cannot
  exceed the original Control deadline. It does not register certificates.
- The candidate inventory checks source fingerprints, post-test artifact
  hashes, defined/undefined parser symbols, and the complete native framework
  dependency graph. OpenSSL is included explicitly. A redundant test dependency
  was removed so testing does not introduce an unembedded package framework.

## Verified checks

Environment: Xcode 27.0 (27A266a), macOS 27.2 (26B5091g), dedicated iOS 27.0
Simulator `8FF65ABB-572E-4EE4-9A9F-F61AA302A586`. No physical device was used.

| Check | Result | Evidence boundary |
| --- | --- | --- |
| Native component XCTest | 12 passed, 0 failures | Four Objective-C engine tests and eight Swift normal-owner tests, including a real refused native connection |
| Local lifecycle XCTest | Four passed | Ten indexed transition scenarios plus admission/drain guards |
| Enrollment signing XCTest | Three passed | Exact golden bytes/hash/signature; every signed field mutation; invalid bounds |
| Enrollment admission XCTest | Four passed | Nine indexed rejection/replay scenarios, original deadline, nonce replacement, and 100 concurrent attempts accepting once |
| Existing full Simulator UI suite | 16 passed, 0 failures | Existing authenticated app/legacy video regression flow; not native approval/enrollment |
| Existing pairing reliability | Five passed | Durable recovery and exact attempt correlation; not native credential registration |
| Simulator and iPhone SDK native builds | Compiled | Unsigned components; no iPhone installation or device playback claim |

The full Simulator runner completed with exit 0 and a passed report under
`/private/tmp/maccompanion-feature-tests.qBhRFK`. Its disposable fixture,
journey directory, and Simulator lock were removed. The full suite preceded
the final closed-product/teardown refinements; focused final-source recovery
checks are recorded separately below.

Ten consecutive source-built Sunshine → native driver → normal UIKit surface
frame/Stop/drain sequences passed in the reference transport app, process 71692,
between 20:25:37 and 20:28:54. These preceded the final teardown and packaging
refinements. After those refinements, the exact inventoried frameworks embedded
in reference process 98635 passed this fresh sequence:

| Local time | Event |
| --- | --- |
| 20:48:45.945 | Normal UIKit surface selected; input disabled |
| 20:48:45.993 | Native connection started |
| 20:48:46.313 | First decoded frame displayed |
| 20:48:48.337 | Reference controller requested Stop |
| 20:48:48.440 | Native Stop drained |

This uses upstream reference pairing and explicitly synthetic local authority.
It proves neither the normal MacCompanion enrollment journey nor input
authorization. These startup events are not a LAN latency benchmark. The final
reference app and owned finite host supervisor were stopped afterward.

## Exact development artifacts

Candidate source input SHA-256:
`362992b01c60302a1a87385f19049d574894f96ba0d5ca45547edfb7d6e968cf`.
Source lock SHA-256:
`4b5c0ec979c5f7d58e11063a6135b1cf9ecb292e82639f66cabcd91a32abff54`.
The checkout remains dirty, including preserved earlier work. These are content
fingerprints, not a committed or signed release candidate.

| Platform | Framework | SHA-256 |
| --- | --- | --- |
| Simulator | Engine | `22d727409a557e713c06b9a25c84a0b295f3fd7ed5e3c914d671f832bf5777db` |
| Simulator | Adapter | `affbfc3a9702f497f8af44cb04d8d3cb9283eed4d03b71294e10aea9baea95a6` |
| Simulator | OpenSSL | `555ab83f8eb9819417261ce350de03991d43e673a9bdccf58795bd02d0d2460e` |
| iPhone SDK | Engine | `242694adea7eb64f32e767cbe9914af8f85975f653017bd689ee6facc8d09427` |
| iPhone SDK | Adapter | `9f20dbf398f344100f97cf3a08012888ea27e10fbec268d57f37a2c34fff1d1c` |
| iPhone SDK | OpenSSL | `06246a6b523db9be1d67a2bce1069cd7d9e7517fca33b4b74d57e8341a799188` |

All three embedded Simulator framework hashes matched the inventory before
the final live check. The inventory remains `releaseAdmitted: false` and
`correspondingSourceComplete: false`. The source-built host still depends on
Homebrew OpenSSL, ICU, and miniupnpc; its complete build provenance is not
claimed. Native OpenSSL is currently a pinned upstream binary, not our own
source build. Private test state, credentials, images, and raw logs stay outside
the repository.

## Still required for a usable installed replacement

1. Define and implement authenticated enrollment records, canonical certificate
   inspection, credential registration, and native session preparation on the
   normal primary channel. The local verifier is one prerequisite only.
2. Bind the managed Sunshine host to the normal Mac Control/capture owner and
   prove approval, revocation, deadline, permission, and process/TCC ownership.
3. Admit a native presentation receipt and connect it to existing input fences.
   Native video deliberately cannot enable pointer, text, modifiers, or shortcuts
   yet. Existing keyboard regression results do not prove native input.
4. Wire normal app startup/navigation to the native driver. The normal app does
   not yet select it automatically; the old media role remains in composition.
5. Prove repeated normal approved sessions, sustained use, reconnect/window
   transitions, and Stop-to-Observe/Act behavior; then produce and install exact
   signed normal Mac/iPhone builds and perform physical acceptance.
6. Complete dependency/source/license/SBOM/packaging admission and the existing
   release gates. Viewport capture and adaptive bitrate remain later work.

No installed production Mac app, existing Sunshine setup, or physical iPhone
was changed by this checkpoint. Installation is authorized by the owner but a
native normal-app candidate has not yet been produced.

## Final-source regression and repository validation

The final-source focused integration run passed all three recovery tests,
followed by all five pairing regressions. Its report under
`/private/tmp/maccompanion-feature-tests.xan88q` records exit 0, 176.247 seconds,
and verified runner cleanup. It covers background recovery, network loss and
cancelled dialing, and retired callbacks during replacement using the existing
production/legacy flow. It does not establish a native normal-app journey.

`bash scripts/validate.sh` exited 0 after the code, fixtures, build/inventory
changes, and this checkpoint were added. Evidence remains in
`/private/tmp/maccompanion-native-checkpoint-validation.log`. It validated 93
indexed JSON fixtures, repository material, dependency/target/privacy/signing
policies, and package tests. `git diff --check` also passed. These checks do not
admit the native dependency into permanent targets or satisfy signed physical
and final release-toolchain acceptance.
