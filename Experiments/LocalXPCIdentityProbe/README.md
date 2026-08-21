# Local XPC identity probe

Status: disposable macOS 26 signed experiment; never linked into a release
target.

This probe tests the final Mac and Agent code-signing identifiers without
tracking the private Team ID. It uses
`xpc_peer_requirement_create_team_identity` on both listener and session,
then applies the requirement to the inactive listener and every accepted peer
session before activation.

The listener accepts only the same Apple-issued signing team plus
`media.jenny.maccompanion`. The client accepts only the same team plus
`media.jenny.maccompanion.agent`.

The first client message is the constant dictionary
`{"kind":"hello","version":1}`. It contains no role, credential, token,
identifier, device data, path, capability, or authority. No other message may
be sent until its reply passes the session peer requirement and exact closed
shape. This matters because XPC peer requirements enforce received messages:
a substituted server can receive the initial request before its reply is
rejected.

## Matrix

`run.sh` builds and signs temporary binaries, bootstraps a temporary per-user
launchd job, runs the closed-handshake and identity matrix, then removes the
job and temporary directory:

- correct same-team menu identifier to correct Agent: accepted;
- unsupported hello version from the correct menu identity: rejected;
- extra hello field from the correct menu identity: rejected;
- same-team wrong menu identifier: rejected by the listener;
- ad-hoc same menu identifier: rejected by the listener;
- correct menu identifier to same-team wrong Agent identifier: reply rejected
  by the client, while the wrong Agent sees only the constant hello.

No production service label, LaunchAgent plist, app bundle, Keychain item,
permission, user data, or durable product state is changed.

Run explicitly on a development Mac with the local signing identity:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
MACCOMPANION_XPC_PROBE_SIGNING_IDENTITY="Developer ID Application" \
Experiments/LocalXPCIdentityProbe/run.sh
```

The result is provisional on Xcode 27 beta. Stable macOS 26/Xcode 26.6 and the
final controlled release identity remain required for release evidence.
