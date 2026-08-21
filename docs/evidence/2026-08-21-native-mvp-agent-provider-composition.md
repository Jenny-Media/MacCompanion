# Native MVP Agent provider composition evidence — 2026-08-21

## Claim

The bundle-independent Agent network product now has a first-party construction
path for the MVP Act provider. One
`AgentNativeMVPProviderCompositionV1` creates both the reviewed
`maccompanion.system.setAudioMuted` descriptor and the exact matching live
provider reference. `AgentNetworkProductStartupInputsV0` accepts that pair as a
single value, so a release target cannot accidentally advertise the native
capability while loading another provider identity, or load the provider
without its reviewed descriptor.

On macOS, `systemDefault` binds the existing Core Audio controller. Construction
and provider loading are inert: neither reads nor mutates audio. A Core Audio
call remains possible only after host identity startup, publication validation,
durable operation reconciliation, authentication, grant and policy admission,
and the ordinary operation execution claim.

## Automated evidence

Four focused tests prove:

- the composition emits exactly one descriptor and exact provider identity;
- publication validation accepts that internally consistent pair;
- the retained provider executes only the closed desired-state mute shape and
  returns the verified canonical result;
- macOS system-default construction loads one inert native provider; and
- a complete ready Agent network startup publishes that exact registry
  generation, capability, and one-provider count through the production
  startup graph.

The focused test command passed on Xcode 27 beta. The final hardened unsigned
gate then passed with 63 indexed JSON fixtures, 768 repository files, 34
historical blob paths, 14 repository-material fixtures, 4 manifests, 12
dependency fixtures, 3 privacy manifests, 12 privacy fixtures, 9
required-reason source records, 10 SBOM fixtures, 16 release-evidence fixtures,
1,038 listed Swift tests, both platform cross-compiles, and all three
construction probes. Only the expected read-only user SwiftPM cache warnings
appeared.

## Deliberate limits

This proves identity-neutral construction and startup publication only. It does
not mutate the current Mac's audio, authenticate a physical connection, execute
under a final signed Agent identity, or prove behavior across real audio
devices, device changes, lock, logout, or third-party drivers. Those remain
explicit signed clean-device evidence gates.
