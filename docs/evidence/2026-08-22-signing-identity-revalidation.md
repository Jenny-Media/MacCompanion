# Signing identity and permanent Debug revalidation

Date: 2026-08-22

## Claim

The development Mac currently has valid Jenny Media LLC Apple Development and
Developer ID Application identities in the login Keychain. The earlier
zero-identity result was produced inside the restricted workspace sandbox,
which could not read the login Keychain; it was not evidence that certificates
needed to be replaced.

No certificate was created, revoked, downloaded, or changed for this
checkpoint.

## Signed construction evidence

With `DEVELOPER_DIR` selecting the installed Xcode 27 beta, the checked-in
`MacCompanion` scheme completed an Apple Development Debug build while the
development team was supplied only to the local build invocation. Neither the
team, certificate selector, profile, nor credential was written to the project
or repository.

Independent inspection outside the restricted sandbox proved:

- strict deep signature verification accepted the complete containing app;
- the outer designated identifier is exactly `media.jenny.maccompanion`;
- the embedded Agent identifier is exactly
  `media.jenny.maccompanion.agent`;
- both signatures use the same Jenny Media LLC team and the valid Apple
  Development chain; and
- both executables carry the hardened runtime.

The built app contains the signed Agent executable and exact LaunchAgent
property list. This reopens signed development and physical-runtime work on
the beta toolchain. Stable Xcode 26.6 remains required for final release
evidence, and Developer ID custody, notarization, stapling, packaging, and
promotion remain controlled release gates.

The complete repository gate then passed with 64 indexed protocol/product
fixtures, 935 repository files, 1,176 historical blob paths, 304 production
Swift source files, 1,348 package tests, every supported cross-build, and all 8
platform-probe tests.

## Non-claims and next gate

This checkpoint did not launch the containing app or Agent, register either
login role, mutate durable enabled intent, accept an XPC peer, exchange
readiness or status, open network ingress, or exercise Observe, Act, or
Control. Signed construction is not signed runtime acceptance.

The next implementation gate is a durable, explicit user enablement path that
can register and start the Agent without deriving readiness from
`SMAppService` status. Once that path is complete, the signed permanent
processes must prove reciprocal same-team exact-identifier authentication, the
closed hello/readiness exchange, and one content-free status reply before any
presentation or network-ingress profile is enabled.
