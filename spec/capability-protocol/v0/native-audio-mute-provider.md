# Native default-output mute provider v0.1

Status: bounded macOS provider candidate. Building or registering this provider
does not grant it to a device. Enabling it in a signed product still requires
the Stage 1 permission/session/physical evidence gates.

## Capability

The registered capability ID is
`maccompanion.system.setAudioMuted`. Its parameter and result schemas are both
the closed object `{ "muted": boolean }`. It is desired-state, not a toggle.
Its effect facts declare reversible local state change, no data access, no
credential/external/destructive effect, no cancellation, and no foreground
session requirement. Locked-session eligibility remains disabled until signed
physical evidence proves it reliably.

## Core Audio boundary

The adapter uses the current Core Audio `AudioObject` API, not deprecated
`AudioDeviceSetProperty` functions:

1. read `kAudioHardwarePropertyDefaultOutputDevice` from the system object;
2. require the default device to expose `kAudioDevicePropertyMute` in output
   scope on the main element;
3. require `AudioObjectIsPropertySettable` to succeed and return true;
4. read the current `UInt32` mute value and avoid a redundant write;
5. otherwise set exactly `0` or `1` with `AudioObjectSetPropertyData`;
6. re-read the default device, require that it did not change, and read back
   the mute property;
7. report success only when read-back equals the requested state.

A missing device/property, non-settable property, or device switch is
`provider.unavailable`. A completed set whose read-back differs is
`provider.rejected`. Other host API failures become
`provider.executionFailed`; raw `OSStatus`, device names, and driver text do
not cross the provider boundary or enter durable events.

The provider performs no enumeration and exposes no device name, UID, volume,
route, or audio content. Validation builds the adapter but never changes audio;
manual mutation evidence must use an explicit disposable probe on a test Mac.

## Product composition

The first-party Agent product constructs the reviewed descriptor and its live
provider reference through one `AgentNativeMVPProviderCompositionV1`. The
composition accepts one caller-owned registry generation, creates exactly the
single native mute descriptor, and creates exactly the matching provider
identity. `AgentNetworkProductStartupInputsV0` consumes that composition as one
value; the release target does not independently assemble the descriptor list
and provider loader.

The macOS `systemDefault` construction binds
`CoreAudioDefaultOutputMuteControllerV1` but performs no Core Audio read or
mutation. The provider remains inert until the startup-reconciled authenticated
operation authority admits and executes a request. The ordinary registry
publication validator remains the final missing/extra/identity-mismatch fence.
