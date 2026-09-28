# Managed native IPv4 listener

Date: 2026-09-27

## Product change

The production managed backend accepts a closed, trusted local listener scope:
loopback or IPv4 interfaces. Its component default remains loopback. The normal
Mac Debug bundled-host composition now explicitly selects IPv4 interfaces,
allowing its Control-enrolled client to reach the native host using the current
verified primary route address. Remote requests cannot select the listener scope.

All reachable IPv4 interfaces use the existing exact admitted TLS certificate,
mandatory LAN/WAN stream encryption, sealed routes, Desktop/capture geometry,
original Control deadline and process/credential retirement. Input, audio, UPnP
and the native pairing/Web-management paths stay disabled. IPv4 reachability
is not a route classification or release approval; no signing/authentication/key
construction changed. The normative profile and its existing indexed fixture
were updated before implementation. Existing golden enrollment vectors remain
normative for certificate/signature admission.

## Live non-loopback host evidence

The live probe accepts only a concrete IPv4 address owned by this Mac, verified
against `getifaddrs`. It connected through the active network interface rather
than loopback, using the production enrollment backend. It passed:

- Exact attested certificate admission and another certificate's rejection.
- Server inventory and approved encrypted launch returning that same address.
- Rejection of absent/zero encrypted RTSP support and plaintext RTSP.
- Absence of plaintext HTTP/Web-management listeners and forbidden native routes.
- Port conflict, malformed certificate and invalid proof rejection.
- Original Control/revocation handling, removal of private state and refusal of
  fresh network connections to HTTPS/RTSP after retirement.

This component probe uses substituted runtime effects and does not decode a phone
frame or prove the normal paired primary/XPC application journey.

Retained report: `/private/tmp/maccompanion-ipv4-network-probe-report-20260927.json`

Report SHA-256: `a519cc9215966a8803ae0f6b44186e49ff7015453c302e84ee6beb73ffdb2a7b`

Combined native source inputs: `491232e6c28d712af792163c96b5ed16747def12e1368f386a4d4498a933d9f9`

Historical host executable: `c48a6824dea93f0157bc1bcbd3819201da671610895a2c5c7885173c9044582d`

## Normal Mac construction

The normal Mac Debug build passed on stable Xcode 27.0. A fresh containing-app
signature and exact admitted native-host catalog were verified in the staged app:
`/private/tmp/maccompanion-ipv4-normal-mac-stage-20260927.app`.

Containing executable SHA-256: `872f3a560e7f195f0e89d06ef5a5dbc9c58ebf8e4e499fd30c96857c4d0d8285`

Compiled catalog: `ec578d38801443a6e78d938a4b8de0c6d7be510d8b9afe8fee5810d2a48ebf5d`.

Logs: `/private/tmp/maccompanion-ipv4-normal-mac-build.log` and
`/private/tmp/maccompanion-ipv4-normal-mac-stage.log`.

The staged app has not been launched or installed. The running installed app and
its registered Agent were not replaced. Release still refuses development host
selection. Stable `bash scripts/validate.sh` passed with all 109 indexed fixtures;
log: `/private/tmp/maccompanion-ipv4-listener-validation.log`.

## Rebuilt-host Simulator acceptance

The dedicated Simulator `8FF65ABB-572E-4EE4-9A9F-F61AA302A586` passed four
visible native sessions with `--native-ipv4-interfaces` and the rebuilt portable
host. Decoded presentation, correlated input admission, keyboard, modifiers,
shortcuts, pointer, background/route-loss recovery, Stop, fresh Observe and cleanup
pass. One UI test passed, zero failed. The host listens on IPv4 interfaces; this
Simulator journey uses its isolated loopback primary address. It does not prove
normal paired LAN acceptance, and final input still uses a synthetic host sink.

Report: `/private/tmp/maccompanion-agent-xpc-evidence.zifmmtqr/signed-simulator-report.json`

Report SHA-256: `cd01ac97f852c67b61a7960ecfff1d9d0b676e43e21ee3f3dd80e1eaa9d5a674`

Combined source SHA-256: `6fdf65580b3e0f04bbe2cbfb1a696114fefb958ba25e6349f873f620dc6ef48e`

Native source input SHA-256: `491232e6c28d712af792163c96b5ed16747def12e1368f386a4d4498a933d9f9`

Portable host manifest SHA-256: `1ee79a835e04c12b3c6a4a3a64e5b07d99455f3122a65ec28f96e2435bc55492`

Elapsed: 236.239 seconds. The unchanged package was reverified
after execution. Disposable Agent/credentials/Simulator fixture cleanup passed.

## Remaining acceptance

The network listener prerequisite is implemented. Full normal paired Control over
a non-loopback primary route, normal GUI/TCC continuity, physical iPhone installation
and actual input still need acceptance. The normal Simulator app's required file
protection remains unavailable before pairing; the dedicated harness substitutes
key custody/consent and input effects explicitly. App/Window native capture,
visible-area bitrate and current corresponding-source assembly also remain open.
