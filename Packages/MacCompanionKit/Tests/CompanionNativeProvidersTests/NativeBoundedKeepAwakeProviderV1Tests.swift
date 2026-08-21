import CompanionNativeProviders
import CompanionOperations
import CompanionWire
import Foundation
import Testing

private struct KeepAwakeTestClockV1: NativeKeepAwakeWallClockV1 {
    let now: Int64
    func nowUnixMilliseconds() -> Int64 { now }
}

private final class KeepAwakeTestBackendV1:
    KeepAwakeAssertionBackendV1,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var nextAssertionID: UInt32 = 41
    private var createFailure: BoundedKeepAwakeErrorV1?
    private var releaseFailure: BoundedKeepAwakeErrorV1?
    private var createdTimeouts: [TimeInterval] = []
    private var releasedIDs: [UInt32] = []

    func failCreate(with error: BoundedKeepAwakeErrorV1?) {
        lock.withLock { createFailure = error }
    }

    func failRelease(with error: BoundedKeepAwakeErrorV1?) {
        lock.withLock { releaseFailure = error }
    }

    func createAssertion(timeoutSeconds: TimeInterval) throws -> UInt32 {
        try lock.withLock {
            if let createFailure { throw createFailure }
            createdTimeouts.append(timeoutSeconds)
            defer { nextAssertionID += 1 }
            return nextAssertionID
        }
    }

    func releaseAssertion(_ assertionID: UInt32) throws {
        try lock.withLock {
            if let releaseFailure { throw releaseFailure }
            releasedIDs.append(assertionID)
        }
    }

    func snapshot() -> (created: [TimeInterval], released: [UInt32]) {
        lock.withLock { (createdTimeouts, releasedIDs) }
    }
}

private func keepAwakeProviderV1(
    now: Int64 = 1_787_198_400_000,
    backend: KeepAwakeTestBackendV1 = KeepAwakeTestBackendV1()
) -> (
    provider: NativeBoundedKeepAwakeProviderV1,
    controller: BoundedKeepAwakeControllerV1,
    backend: KeepAwakeTestBackendV1,
    now: Int64
) {
    let controller = BoundedKeepAwakeControllerV1(backend: backend)
    return (
        NativeBoundedKeepAwakeProviderV1(
            controller: controller,
            wallClock: KeepAwakeTestClockV1(now: now)
        ),
        controller,
        backend,
        now
    )
}

private func keepAwakeRequestV1(
    capabilityID: String,
    parameters: CanonicalJSONValue,
    now: Int64 = 1_787_198_400_000,
    expiresAt: Int64? = nil
) -> CapabilityProviderRequestV1 {
    CapabilityProviderRequestV1(
        operationID: UUID(),
        capabilityID: capabilityID,
        parameters: parameters,
        expiresAtUnixMilliseconds: expiresAt ?? now + 30_000
    )
}

@Test func boundedKeepAwakeDescriptorsAreClosedExpiringAndConservative()
    throws
{
    let descriptors = try NativeBoundedKeepAwakeCapabilityV1.descriptors()
    #expect(descriptors.map(\.capabilityID) == [
        "maccompanion.system.startKeepAwake",
        "maccompanion.system.stopKeepAwake",
    ])
    for descriptor in descriptors {
        #expect(descriptor.providerID == "maccompanion.native.power")
        #expect(descriptor.effects.changesLocalState == .reversible)
        #expect(descriptor.effects.mayDisruptUser)
        #expect(!descriptor.effects.allowedWhileLocked)
        #expect(descriptor.effects.cancellation == .notApplicable)
    }
    try descriptors[0].parameterSchema.validate(.object([
        .init(key: "untilUnixMilliseconds", value: .integer(60_000)),
    ]))
    try descriptors[1].parameterSchema.validate(.object([]))
    #expect(throws: (any Error).self) {
        try descriptors[1].parameterSchema.validate(.object([
            .init(key: "toggle", value: .boolean(true)),
        ]))
    }
}

@Test func boundedKeepAwakeStartAndStopReturnOnlyCanonicalVerifiedFacts()
    async
{
    let product = keepAwakeProviderV1()
    let until = product.now + 60_000
    let start = await product.provider.execute(keepAwakeRequestV1(
        capabilityID:
            NativeBoundedKeepAwakeCapabilityV1.startCapabilityID,
        parameters: .object([
            .init(key: "untilUnixMilliseconds", value: .integer(until)),
        ])
    ))
    #expect(start == .succeeded(resultJSON: Data(
        "{\"untilUnixMilliseconds\":\(until)}".utf8
    )))
    #expect(product.backend.snapshot().created == [60])

    let stop = await product.provider.execute(keepAwakeRequestV1(
        capabilityID: NativeBoundedKeepAwakeCapabilityV1.stopCapabilityID,
        parameters: .object([])
    ))
    #expect(stop == .succeeded(resultJSON: Data("{\"stopped\":true}".utf8)))
    #expect(product.backend.snapshot().released == [41])
}

@Test func boundedKeepAwakeRejectsExpiredMalformedAndOutOfRangeRequests()
    async
{
    let product = keepAwakeProviderV1()
    let startID = NativeBoundedKeepAwakeCapabilityV1.startCapabilityID
    #expect(await product.provider.execute(keepAwakeRequestV1(
        capabilityID: startID,
        parameters: .object([
            .init(
                key: "untilUnixMilliseconds",
                value: .integer(product.now + 59_999)
            ),
        ])
    )) == .failed(.rejected))
    #expect(await product.provider.execute(keepAwakeRequestV1(
        capabilityID: startID,
        parameters: .object([
            .init(
                key: "untilUnixMilliseconds",
                value: .integer(product.now + 14_400_001)
            ),
        ])
    )) == .failed(.rejected))
    #expect(await product.provider.execute(keepAwakeRequestV1(
        capabilityID: startID,
        parameters: .object([
            .init(key: "until", value: .integer(product.now + 60_000)),
        ])
    )) == .failed(.rejected))
    #expect(await product.provider.execute(keepAwakeRequestV1(
        capabilityID: startID,
        parameters: .object([
            .init(
                key: "untilUnixMilliseconds",
                value: .integer(product.now + 60_000)
            ),
        ]),
        expiresAt: product.now
    )) == .failed(.timedOut))
    #expect(product.backend.snapshot().created.isEmpty)
}

@Test func boundedKeepAwakeControllerIsIdempotentAndReplacesExactly()
    async throws
{
    let product = keepAwakeProviderV1()
    let firstUntil = product.now + 60_000
    let secondUntil = product.now + 120_000
    #expect(try await product.controller.start(
        untilUnixMilliseconds: firstUntil,
        nowUnixMilliseconds: product.now
    ) == firstUntil)
    #expect(try await product.controller.start(
        untilUnixMilliseconds: firstUntil,
        nowUnixMilliseconds: product.now + 1
    ) == firstUntil)
    #expect(try await product.controller.start(
        untilUnixMilliseconds: secondUntil,
        nowUnixMilliseconds: product.now + 2
    ) == secondUntil)
    let calls = product.backend.snapshot()
    #expect(calls.created == [60, 119.998])
    #expect(calls.released == [41])
}

@Test func expiredAssertionStateDoesNotReleaseAnAlreadyTimedOutHandle()
    async throws
{
    let product = keepAwakeProviderV1()
    let until = product.now + 60_000
    _ = try await product.controller.start(
        untilUnixMilliseconds: until,
        nowUnixMilliseconds: product.now
    )
    try await product.controller.stop(nowUnixMilliseconds: until)
    #expect(product.backend.snapshot().released.isEmpty)
}

@Test func releaseAmbiguityDoesNotCreateOrClaimReplacementState()
    async throws
{
    let backend = KeepAwakeTestBackendV1()
    let product = keepAwakeProviderV1(backend: backend)
    _ = try await product.controller.start(
        untilUnixMilliseconds: product.now + 60_000,
        nowUnixMilliseconds: product.now
    )
    backend.failRelease(with: .outcomeUnknown)
    await #expect(throws: BoundedKeepAwakeErrorV1.outcomeUnknown) {
        _ = try await product.controller.start(
            untilUnixMilliseconds: product.now + 120_000,
            nowUnixMilliseconds: product.now + 1
        )
    }
    #expect(backend.snapshot().created.count == 1)
}

@Test func providerMapsReleaseAmbiguityAndCreateFailureWithoutDetails()
    async
{
    let backend = KeepAwakeTestBackendV1()
    let product = keepAwakeProviderV1(backend: backend)
    let until = product.now + 60_000
    _ = await product.provider.execute(keepAwakeRequestV1(
        capabilityID:
            NativeBoundedKeepAwakeCapabilityV1.startCapabilityID,
        parameters: .object([
            .init(key: "untilUnixMilliseconds", value: .integer(until)),
        ])
    ))
    backend.failRelease(with: .outcomeUnknown)
    #expect(await product.provider.execute(keepAwakeRequestV1(
        capabilityID: NativeBoundedKeepAwakeCapabilityV1.stopCapabilityID,
        parameters: .object([])
    )) == .outcomeUnknown)

    let createBackend = KeepAwakeTestBackendV1()
    createBackend.failCreate(with: .executionFailed)
    let failed = keepAwakeProviderV1(backend: createBackend)
    #expect(await failed.provider.execute(keepAwakeRequestV1(
        capabilityID:
            NativeBoundedKeepAwakeCapabilityV1.startCapabilityID,
        parameters: .object([
            .init(
                key: "untilUnixMilliseconds",
                value: .integer(failed.now + 60_000)
            ),
        ])
    )) == .failed(.executionFailed))
}

@Test func stopIsIdempotentWhenNoAssertionIsOwned() async {
    let product = keepAwakeProviderV1()
    #expect(await product.provider.execute(keepAwakeRequestV1(
        capabilityID: NativeBoundedKeepAwakeCapabilityV1.stopCapabilityID,
        parameters: .object([])
    )) == .succeeded(resultJSON: Data("{\"stopped\":true}".utf8)))
    #expect(product.backend.snapshot().created.isEmpty)
    #expect(product.backend.snapshot().released.isEmpty)
}
