import CompanionDomain
import CompanionHost
import Foundation
import Testing

private struct FixedClock: HostStatusClock {
    let value: Int64

    func nowUnixMilliseconds() -> Int64 { value }
}

private actor SampleSource: HostSystemSampling {
    private var shouldFail = false

    func failNext() {
        shouldFail = true
    }

    func sample() async throws -> HostSystemMeasurement {
        if shouldFail {
            shouldFail = false
            throw SampleError.expected
        }
        return try measurement()
    }
}

private enum SampleError: Error {
    case expected
}

private enum CommitError: Error {
    case conflict
    case expectedFailure
}

private actor InMemorySequenceCommitter: StatusSequenceCommitting {
    private var state: StatusSequenceState
    private let shouldFail: Bool

    init(state: StatusSequenceState, shouldFail: Bool = false) {
        self.state = state
        self.shouldFail = shouldFail
    }

    func commit(
        expected: StatusSequenceState,
        replacement: StatusSequenceState
    ) async throws {
        guard !shouldFail else { throw CommitError.expectedFailure }
        guard state == expected else { throw CommitError.conflict }
        state = replacement
    }
}

private func measurement() throws -> HostSystemMeasurement {
    try HostSystemMeasurement(
        osName: "macOS",
        osVersion: "26.6",
        osBuild: "25G100",
        uptimeSeconds: 86_400,
        cpuUtilizationBasisPoints: 1_250,
        memoryTotalBytes: 34_359_738_368,
        memoryUsedBytes: 12_884_901_888,
        storageTotalBytes: 994_662_584_320,
        storageAvailableBytes: 536_870_912_000,
        powerSource: .ac,
        batteryLevelPercent: nil
    )
}

private func authority(
    sampler: SampleSource,
    nextRevision: UInt64 = 0,
    exhausted: Bool = false,
    clock: Int64 = 1_787_198_400_900
) throws -> HostStatusAuthority {
    let sequence = try StatusSequenceState(
        generation: UUID(uuidString: "018f3000-0000-7000-8000-000000000001")!,
        nextRevision: nextRevision,
        exhausted: exhausted
    )
    return try HostStatusAuthority(
        hostID: UUID(uuidString: "018f1000-0000-7000-8000-000000000001")!,
        sequence: sequence,
        sampler: sampler,
        clock: FixedClock(value: clock),
        sequenceCommitter: InMemorySequenceCommitter(state: sequence)
    )
}

@Test func successfulSnapshotsAdvanceWithinOneGeneration() async throws {
    let sampler = SampleSource()
    let subject = try authority(sampler: sampler, nextRevision: 42)

    let first = try await subject.snapshot(hostState: .userSessionActive)
    let second = try await subject.snapshot(hostState: .userSessionLocked)

    #expect(first.resourceID == "host.status")
    #expect(first.revision == 42)
    #expect(second.revision == 43)
    #expect(first.generation == second.generation)
    #expect(second.hostState == .userSessionLocked)
}

@Test func failedSamplingDoesNotConsumeARevision() async throws {
    let sampler = SampleSource()
    let subject = try authority(sampler: sampler, nextRevision: 7)
    await sampler.failNext()

    await #expect(throws: SampleError.self) {
        _ = try await subject.snapshot(hostState: .userSessionActive)
    }
    let recovered = try await subject.snapshot(hostState: .userSessionActive)
    #expect(recovered.revision == 7)
}

@Test func maximumRevisionIsEmittedOnceThenFailsClosed() async throws {
    let maximum = MonotonicRevision<AuthorizationEpochTag>.maximumWireValue
    let sampler = SampleSource()
    let subject = try authority(sampler: sampler, nextRevision: maximum)

    #expect(try await subject.snapshot(hostState: .userSessionActive).revision == maximum)
    await #expect(throws: HostStatusError.revisionExhausted) {
        _ = try await subject.snapshot(hostState: .userSessionActive)
    }
}

@Test func invalidMeasurementsAndClocksFailClosed() async throws {
    #expect(throws: HostStatusError.invalidSystemMeasurement) {
        _ = try HostSystemMeasurement(
            osName: "macOS",
            osVersion: "26.6",
            osBuild: "25G100",
            uptimeSeconds: 1,
            cpuUtilizationBasisPoints: 10_001,
            memoryTotalBytes: 1,
            memoryUsedBytes: 0,
            storageTotalBytes: 1,
            storageAvailableBytes: 0,
            powerSource: .unknown,
            batteryLevelPercent: nil
        )
    }

    let subject = try authority(sampler: SampleSource(), clock: -1)
    await #expect(throws: HostStatusError.invalidClock) {
        _ = try await subject.snapshot(hostState: .userSessionActive)
    }
    #expect(await subject.sequenceState().nextRevision == 0)
}

@Test func failedSequenceCommitProducesNoRevisionAdvance() async throws {
    let sampler = SampleSource()
    let sequence = try StatusSequenceState(
        generation: UUID(uuidString: "018f3000-0000-7000-8000-000000000001")!,
        nextRevision: 9
    )
    let subject = try HostStatusAuthority(
        hostID: UUID(uuidString: "018f1000-0000-7000-8000-000000000001")!,
        sequence: sequence,
        sampler: sampler,
        clock: FixedClock(value: 1_787_198_400_900),
        sequenceCommitter: InMemorySequenceCommitter(
            state: sequence,
            shouldFail: true
        )
    )

    await #expect(throws: CommitError.expectedFailure) {
        _ = try await subject.snapshot(hostState: .userSessionActive)
    }
    #expect(await subject.sequenceState() == sequence)
}
