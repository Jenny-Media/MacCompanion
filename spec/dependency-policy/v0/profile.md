# Swift dependency policy v1

Mac Companion's unsigned and release-shaped builds use a closed Swift package
graph. The authoritative machine-readable policy is `policy.json` in this
directory.

## Required boundary

- Every repository `Package.swift` outside build/cache directories is listed by
  repository-relative path, package name, SwiftPM identity, tools version, and
  exact local package dependencies.
- Unlisted remote source-control and registry packages are denied. The sole
  exception is Sparkle 2.9.6 for the Mac containing-app target, admitted only
  when its XcodeGen exact-version declaration, full resolved revision, upstream
  manifest, binary archive, license, binary target/product, and archive-build
  sanitizer all match the policy together.
- Local package dependencies must resolve inside the repository and match an
  explicitly listed package path.
- Unlisted binary targets and every build-tool plugin target are denied. The
  admitted Sparkle binary is never a general binary-target exception.
- Exactly one shared Xcode `Package.resolved` is required at the policy path;
  it contains exactly the Sparkle identity, repository, semantic version, and
  full revision. Every other lockfile or Xcode remote reference is denied.
- Only the Mac containing app consumes the Sparkle product. Its generated
  project keeps App Sandbox and Sparkle system profiling disabled and invokes
  the exact reviewed archive-build sanitizer after embedding dependencies.
- A newly discovered package, a missing package, or drift in any listed package
  identity, tools version, or local edge fails validation.

This profile does not claim that first-party or admitted third-party code is
trustworthy. It prevents a second dependency, floating requirement, substituted
revision/artifact/license, additional consumer, executable build extension, or
topology-sanitizer drift from entering without first changing the public policy
and its adversarial corpus.

## Disposable WebRTC probe admission — September 12, 2026

The user authorized the streaming reuse action plan on September 12. Its B1
package feasibility check may directly link the community `stasel/WebRTC`
153.0.0 Apple framework only from `Experiments/WebRTCProbe/`. This is an
experiment-specific compiler invocation, not an admission to any Swift package
or application target. The existing machine-readable package policy and its
negative fixtures remain unchanged and continue to deny additional package
dependencies, binary targets and remote Xcode references.

- Distributor repository: `https://github.com/stasel/WebRTC`
- Package revision: `4266157cd08f92115de885ab12d87196a8db87e1`
- Reported upstream revision: `9ea5afcad008b940468c2a15aec339592cf5a935`
- Artifact: `WebRTC-M153.xcframework.zip` from release `153.0.0`
- Required SHA-256: `3e3a8946f27510133e3feed04d05fa23505bbe366e977620503bfc7986c2b78f`
- Sole consumers: disposable probe executables/libraries built outside the
  repository by `Experiments/WebRTCProbe/build.py` and the same-directory
  `streaming_build.py` and `apps_build.py`. These extend the authorized
  experiment to synthetic H.264 round trips and disposable capture/receiver
  apps. Their peers use no external ICE/signaling servers. App connection
  files move through local or existing paired-device tooling, never a new
  unauthenticated network signaling listener. Generated projects and embedded
  framework copies remain in private temporary directories, outside the
  production target graph. Only experiment identities may be signed/installed
  for the explicitly authorized device tests; no permanent identifiers change.

The script rejects a different digest before extraction or compilation. It
downloads nothing and does not sign, install, register a service, or add a
release dependency. Source-to-binary reproducibility, complete third-party
notices, privacy and signing review remain prerequisites for any later
production admission. The framework's upstream license does not replace the
licenses of its included dependencies.
