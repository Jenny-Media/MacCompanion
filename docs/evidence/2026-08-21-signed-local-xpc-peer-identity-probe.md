# Signed local XPC peer-identity probe

Date: 2026-08-21

Status: provisional signed platform evidence on macOS 27/Xcode 27 beta;
production IPC remains absent

## Decision tested

Mac Companion's macOS 26 local IPC will use the XPC peer-requirement family
instead of caller-supplied roles, PID lookups, or a tracked Team ID.

The Agent listener creates a team-identity requirement for the exact
`media.jenny.maccompanion` signing identifier. It installs that requirement
on the inactive listener and on every incoming peer session before activation.

The menu-side session creates and installs a team-identity requirement for the
exact `media.jenny.maccompanion.agent` signing identifier before activation.
The API requires the peer to have both that signing identifier and the same
Apple-issued signing team as the calling process. This works for the local
Apple Development and Developer ID forms without embedding the private Team ID
in source or configuration.

## Pre-authentication message boundary

XPC peer requirements enforce received messages. A substituted server can
therefore receive the client's first outgoing request before its reply is
rejected. The accepted design permits exactly one pre-authentication message:

```json
{"kind":"hello","version":1}
```

It is constant and contains no role, identifier, credential, token, endpoint,
path, capability, device data, user data, or authority. No status, lifecycle,
pairing, diagnostic, lease, media, or input message may be sent until the
client receives the exact `hello.ack` shape through a session whose Agent peer
requirement remains installed.

The listener requirement rejects an invalid client before its request reaches
the Agent handler. The per-peer session repeats that requirement so later
messages remain checked.

## Executed matrix

`Experiments/LocalXPCIdentityProbe/run.sh` built temporary hardened-runtime
binaries and signed them with the local Developer ID Application identity. It
then bootstrapped a non-production per-user launchd label, executed the matrix,
and removed all probe state.

| Client | Server | Result |
| --- | --- | --- |
| correct same-team menu identifier | correct Agent identifier | accepted |
| correct menu identifier, unsupported version | correct Agent identifier | rejected |
| correct menu identifier, extra hello field | correct Agent identifier | rejected |
| same-team wrong menu identifier | correct Agent identifier | rejected |
| ad-hoc same menu identifier | correct Agent identifier | rejected |
| correct menu identifier | same-team wrong Agent identifier | rejected by client |

Both protocol-negative cases cancelled the peer without an acknowledgement.
The final case returned the platform error `Peer forbidden (code signing)`.
The wrong Agent log proved it received only the constant hello. The correct
Agent handler saw no request from either invalid client.

After the run:

- `launchctl print gui/<uid>/media.jenny.maccompanion.identity-probe`
  reported no service;
- the temporary directory was absent; and
- no probe Agent or client process remained.

## Primary-source basis

Apple's macOS 26 SDK documents
`xpc_peer_requirement_create_team_identity` as requiring the specified signing
identifier and the same Apple-issued signing team as the current process.
`xpc_listener_set_peer_requirement` and
`xpc_session_set_peer_requirement` install the validated requirement before
activation. Listener requests that fail are dropped; a session expecting a
reply is cancelled with a rich peer-code-signing error when the remote peer
fails.

The installed SDK is authoritative for this beta-toolchain construction.
Stable macOS 26/Xcode 26.6 must repeat the matrix before release acceptance.

## Boundary and next proof

This experiment is not linked into a release target and does not define
production serialization. Production work still must:

- add the final Mach service to the permanent LaunchAgent topology;
- wrap the C-only peer-requirement APIs behind a narrow Swift-safe adapter;
- keep the listener and every peer session inactive until requirements,
  handlers, cancellation, and version negotiation are installed;
- issue a closed authenticated role only after the exact hello exchange;
- invalidate all role capabilities and lifecycle observation on interruption,
  mismatch, replacement, or process loss;
- carry the proven version and malformed-hello rejection into production, then
  prove replay/replacement and late-message behavior; and
- expose only the existing `CompanionIPC` method matrix after authentication.
