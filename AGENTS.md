# Mac Companion agent instructions

- Follow `docs/remote-desktop-mvp.md` and `docs/native-macos-client.md`: native iOS and macOS clients connect directly to built-in Screen Sharing and Remote Login, requiring no Mac Companion server or helper. Preserve the legacy protocol and recorded grants without starting them in either direct client.
- Treat `spec/capability-protocol/v0/` as normative for v0.1. Update the specification and authoritative fixtures before changing wire or security behavior.
- `spec/fixtures/manifest.json` is the only fixture index. Do not create a second mutable fixture corpus under package tests.
- Do not implement application-authentication, pairing, approval, or operation-signature semantics without matching golden cryptographic vectors.
- Permanent Apple target IDs, signing, Keychain groups, designated requirements, TCC attribution, and `SMAppService` labels wait for the gates in `docs/execution-status.md`.
- Disposable platform experiments stay under `Experiments/` and cannot be linked into release targets.
- Use the managed native build/validation workflows in `docs/build-cache-workflow.md`. Keep compiler paths stable; dated output paths are evidence only. Use `--cold` only for an intentional fresh check, and obtain explicit approval before deleting caches or evidence.
- Run `bash scripts/validate.sh` before handing off changes. Local beta-toolchain results are provisional until the stable Xcode lane also passes.
- Never commit certificates, provisioning profiles, notarization credentials, Sparkle private keys, App Store keys, pairing secrets, real audit databases, raw captures, QA input fixtures, private typed/input content, or build/diagnostic logs.
- Reviewed, sanitized App Store release artwork may be committed only under `docs/app-store/<platform>/<version>/screenshots/`, with a versioned manifest recording each final export's path, dimensions, SHA-256 and capture/reuse provenance. This exception covers selected final JPEG/PNG artwork showing public or synthetic demo content. Keep raw screenshots, rejected attempts, capture fixtures and logs outside Git; all credential and private-data exclusions still apply.
