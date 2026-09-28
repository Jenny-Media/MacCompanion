# Sunshine / Moonlight source and engine foundation

Date: 2026-09-26. Status: local foundation verified; normal-app integration pending.

## Source boundary

The owner approved the migration of both apps and GPL licensing. The previous
WebRTC/focus work was preserved as an ignored patch/tar checkpoint, without reset.
The source baseline is Sunshine stable `v2026.914.233613` at
`63d35f702ee9e362e43263742981836ec0710384` and Moonlight iOS 9.0.2 at
`85af0f75622bb2636481afda8b0fc5cc33d5956e`. OpenSSL package source is pinned at
`b9eb055fdf73e595cb4b9f665d13dc85975bf80a`. These are our recorded source versions;
the user described their working installation as “the latest one,” without exact
installed versions or network/settings measurements.

[Source lock](../../Experiments/SunshineMoonlightIntegration/source-lock.json)
records gitlinks, patch and license hashes, and selected binary artifact checksums.
[Build instructions](../../Experiments/SunshineMoonlightIntegration/README.md)
reproduce the experiment. The combined product license changed to GPL-3.0; original
Apache text and prior permissions are retained. Release dependency admission,
transitive notices, SBOM, and complete corresponding source remain open.

## Actual video baseline

On macOS 27.2 `26B5091g`, Xcode 27.0 `27A266a`, the source-built Sunshine helper
found the H.264 VideoToolbox encoder and served only loopback ports from a private,
isolated directory. Mouse, keyboard, controllers, UPnP, and audio capture were
explicitly disabled. It did not use the separately installed host's state.

The source-built Moonlight app installed and launched on dedicated iOS 27.0
Simulator `8FF65ABB-572E-4EE4-9A9F-F61AA302A586`. Normal upstream PIN pairing
completed and the Desktop profile appeared. Its first audio attempt failed with
CoreAudio `AudioQueueStart` error `-66680`; an explicit silent reference mode was
added. At 15:38:32 local time the native renderer then emitted:

```text
MacCompanion reference: first decoded video frame displayed
```

This is first-frame evidence for the patched reference client, not a latency
measurement, sustained playback acceptance, or proof of the extracted engine's
live decoding. The helper was explicitly terminated after this test and its
supervisor reaped it (exit 143). The reference client was stopped. No physical
phone installation, Wi-Fi test, input acceptance, or normal-app playback occurred.

## Embedded components

The experimental video-only framework builds for arm64 Simulator and arm64 iPhone
(unsigned). It retains native Moonlight transport and the VideoToolbox renderer,
excludes discovery/pairing/launch/input, discards audio, and advertises H.264/HEVC.
Its native Simulator XCTest suite passed four tests on the final source:

- Invalid endpoint substitution, missing host, and malformed key are rejected.
- Stop during startup drains before replacement and suppresses retired callbacks.
- Stop before startup is terminal.
- An actual native failed connection drains and permits a new session.

Result: `Test-CompanionMoonlightEngine-2026.09.26_15-51-51--0400.xcresult`
under the private experiment build root. The four real-process supervisor tests
also passed: finite deadline, requested Stop, parent death, and malformed deadline.
The Swift process owner compiled with strict Swift 6 and passed a real-process
probe for denied/expired admission, live authorization loss, terminal ownership,
and concurrent Stop. Production Control composition is not connected and is not
established by these component tests.

Artifact SHA-256 at this checkpoint (not signed distribution manifests):

| Artifact | SHA-256 |
| --- | --- |
| Sunshine helper after final documentation patch | `e03e5015c9fd1c8f70c5d0c4078cb2e4f8516cc4c928276c78d14e0c8fa19dcf` |
| Reference Moonlight code dylib | `46d047ab39a5704f2a2d34bc4d552f4c85f8a6545189cd019acc66a63c3f866d` |
| Simulator engine framework | `f70dcdc3d6b6f36323c9014e11addd15268387793c39b57e4b42906833ad642b` |
| iPhone engine framework | `197dcb41fc56b2a083946d0e16a9101544965cd6af6ec22fcf462f6c5b1821d4` |

The live baseline preceded a documentation-only host patch rebuild; the compiled
helper hash above belongs to that final rebuild. The source-built references use
pinned prebuilt FFmpeg/OpenSSL libraries and local Homebrew dependencies. This is
not a claim that every transitive dependency was built from source.

## Repository validation and remaining integration

Source revision/submodule/artifact/patch/license verification, the updated license
policy check, and `git diff --check` passed. Required `bash scripts/validate.sh`
initially stopped because two validators selected a missing `Xcode-beta.app`.
They now prefer the already policy-approved stable `Xcode.app` tools and retain
fixed-file identity checks. A subsequent run exposed missing WebRTC forwarding
methods in the pre-existing disposable Agent/XPC probe; those were added. The
next run passed 1,834 Swift Testing tests across 41 runners, then exhausted disk
space while building NetworkTLSProbe. Generated intermediates from this experiment
were removed while preserving sources, binaries, and test evidence; that probe
then built successfully. The final complete `bash scripts/validate.sh` run passed on installed Xcode 27.0: 
1,842 Swift Testing tests across 42 runners, repository policies and fixtures,
platform builds, and C syntax checks. Hosted CI remains a separate gate.

Next work: admit exact dependencies and process/TCC ownership, define the
credential/enrollment bridge with matching golden vectors, bind engine launch to
the current authenticated Control owner, connect both normal apps, and test live
engine decoding, Stop/revocation, surface geometry, failure UI, and real devices.
Existing Observe, Act, and Control grants and normative wire behavior remain
unchanged. Phase 0 measurements and Phase 1 admission are not marked complete.
