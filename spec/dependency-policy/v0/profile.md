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
