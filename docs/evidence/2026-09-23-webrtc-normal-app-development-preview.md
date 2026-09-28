# WebRTC in the normal apps: development preview

Date: 2026-09-23

## Implemented boundary

The normal iOS Remote Control product can construct a WebRTC receive peer,
show decoded frames on its live surface, and exchange a complete-gathering
offer and answer over its authenticated primary session. The normal Mac
menu process can construct a send-only peer, capture the selected Desktop
through ScreenCaptureKit, and provide the offer through the existing
authenticated, generation-bound Agent-to-menu XPC route. The Agent and menu
both recheck the active Control session and surface before and after
negotiation; Stop, expiry, surface replacement, authority invalidation, and
peer closure stop the separate WebRTC capture.

These concrete peers compile only with `MACCOMPANION_WEBRTC_DEVELOPMENT` and a
locally supplied WebRTC framework. The tracked Xcode and Swift package
dependency graph does not admit the binary into permanent release targets.
For this development build, Xcode linked the previously pinned local
WebRTC 153.0.0 framework through invocation-only flags. Both the Mac app and
its embedded Agent needed their own signed copy of that framework; the iOS
app needed one signed copy. The first Mac package omitted the Agent copy,
causing a loader exit. Repackaging and re-signing the Agent and containing
app corrected that failure.

The development overlay starts after the existing H.264 initial Desktop
activation. The old media role remains active beneath it, and input plus
surface-changing actions remain gated while the WebRTC overlay is present.
There is not yet an authenticated, exact-peer rendered-frame receipt that
can replace the current H.264 clean-frame acknowledgement. This is a
normal-app video preview, not a completed video-engine cutover or release
dependency admission.

## Local and device evidence

- Standard package compilation and the focused WebRTC negotiation and local
  XPC codec tests passed. The local XPC offer, answer, and close command
  shapes use the single indexed fixture corpus.
- Development Mac and iOS app builds compiled. Both staged bundles passed
  strict deep signature verification with their embedded WebRTC framework.
- The normal `media.jenny.maccompanion.ios` application installed on the
  connected physical iPhone 18 Pro Max. CoreDevice refused two initial launch
  attempts because the phone was locked. After the phone was unlocked,
  CoreDevice launched it successfully and its process remained running.
  Launch is not playback proof.
- The same normal iOS target built, installed, and launched on an iPhone 18
  Pro Max simulator with the simulator WebRTC slice embedded. Its app UI
  appeared behind a simulator Apple Account system prompt. This proves a
  launchable development bundle, not a WebRTC media session.
- The signed Mac containing app and its registered Agent are running from
  the updated development installation after the packaging repair. A live
  Control session and first WebRTC frame have not been observed.
- On 2026-09-23, the signed development builds were installed into the normal
  `~/Applications/Mac Companion.app` bundle and the connected physical iPhone
  18 Pro Max (`media.jenny.maccompanion.ios`, version 0.1.0, build 1). Both
  builds used the pinned local WebRTC 153.0.0 framework and Apple Development
  team `5736QK4NZX`. Strict deep signature verification passed for the staged
  iOS and Mac bundles and the installed Mac bundle. The installed Mac app and
  its registered Agent are running, and each loaded its embedded WebRTC
  framework. The iPhone installation was confirmed through CoreDevice's app
  list; the iPhone app was not launched during this installation pass. The
  user's new phone is not yet paired through the app, so this pass provides no
  Control-session or video-frame result.
- `bash scripts/validate.sh` checked the indexed fixtures and early policy
  gates, then stopped at the fixed missing
  `/Applications/Xcode-beta.app/Contents/Developer/usr/bin/stapler` path.
  That external tool gate was not changed.

## Remaining acceptance

Open the installed iPhone app in the foreground, connect it to the running
Mac app, grant Control through the normal UI, and verify a decoded
WebRTC frame plus Stop/revocation behavior. A full replacement then needs
the fixture-backed rendered-frame proof and a cutover from the H.264 media
role. Production admission additionally needs the source-to-binary,
license, privacy, and signing review in the dependency policy.
