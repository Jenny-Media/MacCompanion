# Swift dependency policy v0

Mac Companion's unsigned and release-shaped builds use a closed Swift package
graph. The authoritative machine-readable policy is `policy.json` in this
directory.

## Required boundary

- Every repository `Package.swift` outside build/cache directories is listed by
  repository-relative path, package name, SwiftPM identity, tools version, and
  exact local package dependencies.
- Remote source-control and registry packages are denied.
- Local package dependencies must resolve inside the repository and match an
  explicitly listed package path.
- Binary targets and build-tool plugin targets are denied. Adding either is a
  supply-chain decision even when its bytes are checked into the repository.
- `Package.resolved` and Xcode remote Swift package references are denied while
  remote dependencies remain disabled.
- A newly discovered package, a missing package, or drift in any listed package
  identity, tools version, or local edge fails validation.

This profile does not claim that first-party source is trustworthy. It prevents
an unreviewed dependency acquisition or executable build extension from being
introduced without first changing the public policy and its adversarial corpus.
