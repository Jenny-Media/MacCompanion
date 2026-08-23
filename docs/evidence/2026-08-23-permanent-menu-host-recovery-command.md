# Permanent menu host-recovery command binding

Date: 2026-08-23

## Gap closed

The permanent menu application constructed the complete reviewed
host-identity recovery owner and received Agent-issued fresh-review and
durable-resume presentations, but its submission client always returned
`unavailable`. A user could therefore review or confirm the destructive scope
without the exact retained command ever reaching authenticated local XPC.

The permanent application now gives pairing, pairing-review, and recovery
owners one weak product proxy. `MacLocalXPCDashboardProductV1` forwards the
exact `LocalHostIdentityRecoveryCommandV0` to `MacLocalXPCClientV1`, decodes an
exact `LocalHostIdentityRecoveredReceiptV0`, and validates the receipt against
the complete submitted command before returning product success. The prior
unavailable recovery client no longer exists in the permanent composition.

## Closed transport

Recovery uses the distinct request/reply family:

- `command.host-identity.recover`
- `command.host-identity.recover.ack`
- `command.host-identity.recover.error`

The command and receipt use a dedicated canonical JSON codec with a 4,096-byte
maximum. The envelope shares the existing authenticated-generation
single-flight gate with the three secret-bearing pairing commands, but the
Agent receives a separate `MacLocalXPCHostIdentityRecoveryHandlingV1`
capability. Pairing authority cannot recover identity, and recovery authority
cannot create, dismiss, or decide pairing.

Handled Agent failure returns only the exact content-free error envelope.
Malformed, noncanonical, cross-kind, oversized, mismatched-receipt, timeout,
cancellation-after-send, replacement, and transport failures invalidate the
exact local-XPC generation. The application owner retains the exact command;
the transport never automatically retries a destructive operation or turns
delivery into product success.

The C exact-message self-test now covers the fourth command kind. The IPC test
covers canonical round trips, cross-kind rejection, noncanonical JSON, and the
encoded-size bound. The full Swift package catalog passed after the binding.

## Deliberately still open

This checkpoint closes the permanent menu submission path and freezes the
server-side typed handler seam. The permanent Agent still selects its closed
authentication-only profile when startup requires recovery, so it does not yet
publish the recovery review/resume surface or install the recovery handler.
That recovery-only Agent service composition is the next source-safe work item.

No signed process was launched, no Keychain identity was replaced, and no
pairing, grant, work, or audit data was mutated by this checkpoint. Stable
Xcode/signing custody and signed two-process recovery remain external proof
gates.
