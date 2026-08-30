#if os(macOS)
@testable import CompanionHost
import Foundation
import Testing

@Test func cpuUtilizationUsesBoundedTickDelta() throws {
    let first = MacSystemStatusSampler.CPUTicks(user: 100, system: 100, idle: 100, nice: 0)
    let second = MacSystemStatusSampler.CPUTicks(user: 150, system: 125, idle: 125, nice: 0)

    #expect(try MacSystemStatusSampler.utilizationBasisPoints(from: first, to: second) == 7_500)
}

@Test func cpuTickWrapIsHandledAsUnsignedDelta() throws {
    let first = MacSystemStatusSampler.CPUTicks(
        user: UInt32.max - 4,
        system: 10,
        idle: 20,
        nice: 0
    )
    let second = MacSystemStatusSampler.CPUTicks(user: 5, system: 10, idle: 30, nice: 0)

    #expect(try MacSystemStatusSampler.utilizationBasisPoints(from: first, to: second) == 5_000)
}

@Test func realMacSamplerProducesAProtocolBoundedMeasurement() async throws {
    // Exercise shipping timing, including its bounded cached-counter retry.
    let sampler = MacSystemStatusSampler()
    let result = try await sampler.sample()

    #expect(result.osName == "macOS")
    #expect(!result.osVersion.isEmpty)
    #expect(!result.osBuild.isEmpty)
    #expect(result.cpuUtilizationBasisPoints <= 10_000)
    #expect(result.memoryUsedBytes <= result.memoryTotalBytes)
    #expect(result.storageAvailableBytes <= result.storageTotalBytes)
}

private final class CPUCounterFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var readings: [MacSystemStatusSampler.CPUTicks]
    private(set) var sleeps: [UInt64] = []
    private(set) var reads = 0

    init(_ readings: [MacSystemStatusSampler.CPUTicks]) { self.readings = readings }
    func read() throws -> MacSystemStatusSampler.CPUTicks {
        try lock.withLock {
            guard !readings.isEmpty else { throw MacSystemStatusSamplerError.invalidCounterDelta }
            reads += 1
            return readings.removeFirst()
        }
    }
    func sleep(_ nanoseconds: UInt64) { lock.withLock { sleeps.append(nanoseconds) } }
}

@Test func cachedCPUCountersExtendOneSampleWithoutInventingIdle() async throws {
    let first = MacSystemStatusSampler.CPUTicks(user: 10, system: 10, idle: 10, nice: 0)
    let last = MacSystemStatusSampler.CPUTicks(user: 15, system: 15, idle: 20, nice: 0)
    let fixture = CPUCounterFixture([first, first, last])
    let result = try await MacSystemStatusSampler.sampleCPUUtilization(
        initialIntervalNanoseconds: 100_000_000, readTicks: fixture.read,
        sleep: { fixture.sleep($0) })
    #expect(result == 5_000)
    #expect(fixture.reads == 3)
    #expect(fixture.sleeps == [100_000_000, 1_100_000_000])
}

@Test func movingCPUCountersDoNotAddBackoff() async throws {
    let first = MacSystemStatusSampler.CPUTicks(user: 10, system: 10, idle: 10, nice: 0)
    let last = MacSystemStatusSampler.CPUTicks(user: 15, system: 15, idle: 20, nice: 0)
    let fixture = CPUCounterFixture([first, last])
    let result = try await MacSystemStatusSampler.sampleCPUUtilization(
        initialIntervalNanoseconds: 100_000_000, readTicks: fixture.read,
        sleep: { fixture.sleep($0) })
    #expect(result == 5_000)
    #expect(fixture.reads == 2)
    #expect(fixture.sleeps == [100_000_000])
}

@Test func unchangedCPUCountersExhaustBoundedRetry() async throws {
    let first = MacSystemStatusSampler.CPUTicks(user: 10, system: 10, idle: 10, nice: 0)
    let fixture = CPUCounterFixture([first, first, first])
    await #expect(throws: MacSystemStatusSamplerError.invalidCounterDelta) {
        _ = try await MacSystemStatusSampler.sampleCPUUtilization(
            initialIntervalNanoseconds: 100_000_000, readTicks: fixture.read,
            sleep: { fixture.sleep($0) })
    }
    #expect(fixture.reads == 3)
    #expect(fixture.sleeps == [100_000_000, 1_100_000_000])
}

@Test func cancelledCPUSampleDoesNotReadOrRetryAfterWait() async throws {
    let first = MacSystemStatusSampler.CPUTicks(user: 10, system: 10, idle: 10, nice: 0)
    let fixture = CPUCounterFixture([first])
    await #expect(throws: CancellationError.self) {
        _ = try await MacSystemStatusSampler.sampleCPUUtilization(
            initialIntervalNanoseconds: 100_000_000, readTicks: fixture.read,
            sleep: { _ in throw CancellationError() })
    }
    #expect(fixture.reads == 1)
}

@Test func failedCPUReadDoesNotRetry() async throws {
    let fixture = CPUCounterFixture([])
    await #expect(throws: MacSystemStatusSamplerError.invalidCounterDelta) {
        _ = try await MacSystemStatusSampler.sampleCPUUtilization(
            initialIntervalNanoseconds: 100_000_000, readTicks: fixture.read,
            sleep: { fixture.sleep($0) })
    }
    #expect(fixture.sleeps.isEmpty)
}

@Test func unchangedCPUTicksAreNotReportedAsMeasuredIdle() {
    let ticks = MacSystemStatusSampler.CPUTicks(user: 10, system: 10, idle: 10, nice: 0)
    #expect(throws: MacSystemStatusSamplerError.invalidCounterDelta) {
        _ = try MacSystemStatusSampler.utilizationBasisPoints(from: ticks, to: ticks)
    }
}
#endif
