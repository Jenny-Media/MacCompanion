# VNC prototype evidence — 2026-10-04

## Verified

- Stable Xcode 27.0 (27A266a): separate Simulator and physical iOS application
  builds succeeded. Dependencies are pinned LibVNCClient 0.9.15 and the existing
  SDK-specific, source-built OpenSSL 3.5.8 frameworks, checked against provenance.
- The existing macOS Screen Sharing service responds on port 5900 with RFB
  3.889 and advertises ARD security type 30. No Sharing settings were changed.
- A Simulator probe completed upstream ARD key setup and reached the credential
  callback. It intentionally returned no credential and sent no login attempt.
- The synthetic framebuffer exercise completed 50 local viewport changes and
  two server-driven framebuffer resizes with **one connection**. The reviewed
  drag stress retained its original button-down location while coalescing 200
  motion events. Its peer reported three pointer messages, six key-down and six
  key-up messages, zero held keys, and released buttons. No input values were
  retained in the evidence report.
- `VNCLifecycleTests.testViewsKeyboardAndBackgroundRecovery` passed on an
  isolated iOS Simulator: ten actual view-menu selections retained connection
  1; the native onscreen keyboard worked; OS Home/background and foreground
  recovery reached connection 2; manual Disconnect completed. This test used
  synthetic content only. The subsequent coalescing correction was verified
  by the separate drag stress rather than inferred from this keyboard test.
- The separate **VNC Prototype** app was development-signed, signature-verified,
  installed alongside Mac Companion, and launched on the connected iPhone
  18 Pro Max. The normal app was not replaced.
- After an initial user-reported login failure, the diagnostic build connected.
  The user confirmed the Mac desktop was visible. Device counters independently
  recorded one credential request, one connection start, one framebuffer
  allocation, handshake stage 5, no failure stage, and desktop updates increasing
  from 3,840 to 5,328 rectangles between reads. Credentials, pixels, and typed
  content were not copied from the phone.
- `bash scripts/validate.sh` passed with the stable Xcode toolchain, including
  normative fixtures and existing native/policy checks. The prototype adds no
  capability-protocol wire kinds, golden authentication behavior, or dependencies
  to production targets.

## Limits and follow-up

- The first physical login failure predates precise diagnostic counters. It is
  **not root-caused** by the subsequent successful connection. ARD cryptography
  and server configuration were unchanged between the attempts.
- Physical repeated display changes, input, Mac Space changes, and background
  recovery were requested from the user; those results remain pending. A passed
  synthetic test does not establish their physical acceptance or latency.
- The phone currently runs the diagnostic candidate that established the real
  desktop connection. The later drag transition correction has been built for
  iPhone and verified on the synthetic peer; its next physical installation/test
  is separate. Keep the current phone connection available during the user's
  comparison rather than restarting it mid-test.
- Bonjour prefills the first responding host. Several Macs are present, so the
  selected host must be confirmed before logging in. Host-selection UI should
  become explicit before expanding this prototype to multiple Macs.
- Display navigation is local zoom/crop of the shared desktop, not isolated
  application/window capture. Layout crops appear only when the framebuffer
  aspect ratio matches the optional private generated display layout.
- Native Screen Sharing login and LAN-only RFB transport are a prototype setup.
  Production requires an encrypted transport, a pair-once design compatible
  with recorded grants, and reviewed specification/cryptographic vectors for
  any new application security behavior.
- Bandwidth, end-to-end input latency, frame rate, long-session stability,
  network loss, and Mac sleep/wake are not yet measured. JPEG/Tight, audio,
  clipboard, and WAN support are excluded from this baseline.

## Private evidence locations

All device identities, signing material, generated projects, geometry, logs,
receipts, and test artifacts remain outside Git. Content-free raw counters are
in `/private/tmp/maccompanion-vnc-prototype-*20261004*`. Simulator UI results are
under the MacCompanion XcodeBuildMCP workspace. No screen captures or credentials
are part of this checked-in summary.
