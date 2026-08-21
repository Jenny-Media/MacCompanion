# Capability registry publication v0.1

Status: normative bundle-independent composition profile.

## 1. Problem and authority

Capability descriptors, provider identities, local grant reviews, discovery,
admission, and execution must not maintain independently replaceable registry
copies in a release composition. Sequentially updating several actors creates
an interval in which one request can observe a mixture of generations; that is
not an auditable registry commit.

The Agent owns one `CapabilityRegistryPublicationV1` through one actor. The
publication contains:

- one already-validated `CapabilityRegistrySnapshotV1`;
- exactly one live provider reference for every provider identity named by the
  registry and no extra provider;
- an exact mapping from each capability descriptor to that provider identity;
  and
- the registry generation as the publication fence.

Provider ID, version, provider generation, and execution revision must match
exactly. Duplicate, missing, extra, or inconsistent providers reject the
candidate before mutation. Provider references are process-local authority and
never enter wire, persistence, diagnostics, or audit payloads.

## 2. Snapshot semantics

Discovery, admission, approval completion, and execution obtain one immutable
publication snapshot for each command. They do not reread a mutable registry
mid-command. Every durable operation and pending local review retains the
generation and exact descriptor/effect bindings already required by their
profiles.

A provider call that was durably claimed under an old publication may complete
through the provider reference captured by that command. Replacement neither
widens nor silently retargets it. A queued operation that has not been claimed
must match the current publication at claim time or fail before provider
effect. A pending review under an old generation is stale and cannot expand a
grant; presentation invalidation is best effort, while commit-time generation
revalidation is authoritative.

## 3. Replacement

Replacement is:

1. construct and fully validate a candidate publication without mutation;
2. atomically swap the authority's single current publication;
3. make new snapshots observe only the complete old or complete new
   publication;
4. invalidate visible stale reviews without relying on that notification for
   grant safety; and
5. attempt best-effort local `capability.registryChanged` detail only after the
   swap.

The new registry generation is the stable audit event UUID. The row uses the
Agent actor, `localOnly` visibility, closed succeeded outcome, and no provider,
capability, device, correlation, operation, session, route, surface, or
arbitrary detail. A detailed-store failure or durable drop degrades audit
health but does not roll back the already-published registry.

Replacement with the current generation is an exact idempotent replay only if
the complete registry descriptors and provider identities are identical;
otherwise it is rejected as a generation collision. A genuinely new
publication must use a new random generation UUID.

## 4. Evidence

Bundle-independent tests must prove:

- provider-loader failure returns no product bootstrap value;
- missing, extra, duplicate, and identity-mismatched providers cannot publish;
- a generation collision with changed content cannot publish;
- concurrent readers observe complete old or new publications, never a mix;
- a command snapshot retains its old provider while later commands use new;
- stale reviews and queued operations cannot cross the generation fence;
- audit happens after publication and is idempotent; and
- audit failure/drop preserves the new publication and degrades health.

The product bootstrap must also reconcile durable operations after loading and
validating the initial publication. An atomic reconciliation failure returns no
registry mutation authority or primary ingress and preserves every pre-startup
operation state for a later explicit retry.

After startup, a provider supervisor may report only the exact currently
published provider identity as unavailable. The authority constructs the
replacement itself by removing every descriptor for that provider, retaining
every unrelated descriptor and exact live-provider reference, assigning the
caller-provided new registry generation, and committing through the ordinary
review-invalidation and audit path. An identity mismatch or already-absent
provider under a different generation fails without mutation. Exact replay of
the completed removal generation is idempotent. Recovery or upgrade is a full
validated publication replacement; an upgrade changes the provider generation
or execution revision according to the provider contract.

Signed provider-process lifetime, provider crash/upgrade races, authenticated
XPC invalidation, and physical native/MacTools replacement remain release
evidence.
