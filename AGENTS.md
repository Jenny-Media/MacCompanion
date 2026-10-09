# Mac Companion agent instructions

- Follow `docs/remote-desktop-mvp.md` and `docs/native-macos-client.md`: native iOS and macOS clients connect directly to built-in Screen Sharing and Remote Login, requiring no Mac Companion server or helper. Preserve the legacy protocol and recorded grants without starting them in either direct client.
- Treat `spec/capability-protocol/v0/` as normative for v0.1. Update the specification and authoritative fixtures before changing wire or security behavior.
- `spec/fixtures/manifest.json` is the only fixture index. Do not create a second mutable fixture corpus under package tests.
- Do not implement application-authentication, pairing, approval, or operation-signature semantics without matching golden cryptographic vectors.
- Permanent Apple target IDs, signing, Keychain groups, designated requirements, TCC attribution, and `SMAppService` labels wait for the gates in `docs/execution-status.md`.
- Disposable platform experiments stay under `Experiments/` and cannot be linked into release targets.
- Run `bash scripts/validate.sh` before handing off changes. Local beta-toolchain results are provisional until the stable Xcode lane also passes.
- Never commit certificates, provisioning profiles, notarization credentials, Sparkle private keys, App Store keys, pairing secrets, real audit databases, screenshots, or typed/input content.
