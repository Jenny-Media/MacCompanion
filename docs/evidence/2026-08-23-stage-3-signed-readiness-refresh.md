# Stage 3 exact-source signed readiness refresh

Date: 2026-08-23
Source revision: `349706d4f597bf55d3c1bb2eeabc28e98aebc38d`
Toolchain: Xcode 27 beta (`27A5218g`), provisional pending stable Xcode 26.6

## Outcome

The exact clean source revision above now has fresh Apple Development-signed
Mac and iOS Debug constructions. Signing authority was supplied only to the
local build invocations; no development team, identity selector, profile, or
credential was added to the project or repository.

Strict inspection accepted the Mac containing app and its embedded Agent. The
two executables retain the expected `media.jenny.maccompanion` and
`media.jenny.maccompanion.agent` identifiers, share the expected Jenny Media
development team, and carry hardened runtime. The persistent Agent launch
service remained absent after construction and inspection.

The iOS construction retains `media.jenny.maccompanion.ios`, the expected
Jenny Media development team, and the installed wildcard development profile.
It installed successfully over the existing development app on the already
paired physical iPhone. The install did not launch the app or claim a fresh
container, explicit App ID, distribution profile, or release candidate.

## Safety boundary

The Mac app was not launched. No Remote Access action ran, no `SMAppService`
registration was requested, and no Agent process, listener, product-data
owner, or Keychain identity owner was started. The iOS app was not launched.
No camera, Local Network, Screen Recording, Accessibility, or other privacy
prompt was shown or accepted.

No QR or SAS pairing, host trust, Observe, `setAudioMuted`, Control, pixels,
input, Smart Zoom, lock/reconnect, study enrollment, report capture/export,
notarization, TestFlight, App Store, or publication action ran. These builds
are development evidence only and cannot satisfy the signed external-beta or
market-MVP gate.

## Verification

- Fresh permanent Mac and iOS target builds completed successfully from the
  exact source revision with invocation-only signing authority.
- `codesign --verify --deep --strict` accepted both application bundles.
- Direct strict verification accepted the embedded Agent.
- Signature inspection confirmed every expected bundle identifier, one common
  nonempty team for the Mac app and Agent, and hardened runtime.
- Physical-device inspection found the paired iPhone available before build;
  installation of the exact iOS app then completed successfully.
- A post-build launch-service read found no registered persistent Agent.
- The repository remained clean throughout construction and installation.
- The complete repository gate then passed 1,642 MacCompanionKit Swift tests,
  eight platform-probe tests, every policy/release fixture and supported
  cross-build, 1,223 current repository files, and 2,297 historical blob paths.

## Next gate

The next physical sequence begins with an action-time decision to launch the
exact Mac app and choose **Enable Mac Companion**. That first choice registers
the setup-only Agent before the app presents the second, exact enable consent;
declining the second consent compensates by unregistering the setup-only
Agent. Because the first choice changes persistent login-item state, it remains
an explicit human-confirmed action rather than an automatic test step.

After confirmed enablement and reciprocal signed local-XPC readiness, the
ordered dogfood path is same-LAN QR/SAS pairing, fresh Observe, separately
approved and visibly verified `setAudioMuted`, Desktop pixels and input, Smart
Zoom, Stop, lock/reconnect, then local Stage 3 report review and export. Each
privacy permission and the mute-state mutation remains separately consented at
the moment it is needed.
