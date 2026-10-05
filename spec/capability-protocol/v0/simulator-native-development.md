# Normal native Simulator development v0.1

An explicitly admitted normal-app Debug Simulator build may select an isolated
Simulator bootstrap. This selector is compiled only for Debug iOS Simulator;
physical devices and Release have only the protected-device bootstrap.

Simulator state uses a separate application-support subtree and Keychain tag
prefix. It requires regular files/directories, no symlinks, exact private POSIX
permissions, backup exclusion, canonical installation identity and existing
single-host/route consistency checks. It does not claim hardware file protection.
Security.framework keys may be software-backed in this mode; existing approval
profile-selected session-signature requirements remain. Normal trusted-device
Control starts use the protected paired session key without a presence prompt;
legacy fresh-presence composition remains available. No signature is simulated or automatically
accepted by this bootstrap. Existing pairing, signature, certificate, route and
independent Observe/Act/Control semantics and golden cryptographic vectors apply.
The normal UI identifies this development mode. No experiment implementation is
linked, and this mode is never evidence of physical key custody or device safety.

The generated Debug Simulator project supplies a development-only application
identifier and one isolated Keychain access group through Xcode's simulated
entitlement packaging. Xcode signs the Simulator app ad hoc. These identifiers
are not permanent Apple target or Keychain-group allocations. The physical-device
and Release projects cannot select this entitlement file. The exact generated
entitlements, packaged simulated entitlements and executable signature are checked
before installation or test admission; native framework bytes remain pinned.
