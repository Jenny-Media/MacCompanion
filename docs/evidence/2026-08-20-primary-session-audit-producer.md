# Primary-session audit producer evidence

Date: 2026-08-20

## Claim

The host primary-session owner now produces bounded authentication and
connection-lifecycle history without changing authentication authority or
placing audit storage ahead of teardown.

## Construction boundary

- A verified proof emits subject-device `auth.succeeded` and
  `connection.opened` records bound to current policy, authorization epoch, and
  grant revision.
- Stable event IDs derive from the opaque 16-byte connection credential and
  closed event code, but that credential, proof, signature, and nonce material
  are never stored.
- A rejected cryptographic proof emits only a local Agent
  `auth.rejected` record correlated to the proof message. It assigns no subject
  device and cannot appear in `audit.readSelf`.
- Session close clears authority and completes Interactive teardown before the
  writer attempts `connection.closed` using an injected wall clock.
- A thrown write or durable rate/quota drop degrades audit health but cannot
  delay or reopen the session or Interactive authority.
- `AgentRequiredAuditCompositionV0` constructs this writer alongside operation
  and lifecycle writers from the same separately bounded detailed store.

## Tests

Four focused tests prove successful open/close scoping and ordering,
privacy-safe rejected-proof recording, and teardown completion under a durable
close-row drop, plus distinct local-only protocol rejection. The current full
repository gate passed with 54 indexed fixtures and
652 Swift tests, both UI compile gates, three no-prompt/no-network probes, and
`git diff --check`.

## Boundary not claimed

This is an identity-neutral package construction. It does not claim a signed
listener, physical route, authenticated XPC health surface, real disk-full
behavior, or a permanent Agent target. Protocol framing/correlation rejection
and provider-registry generation events remain separate producer work.
