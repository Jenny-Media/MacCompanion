#if os(macOS)
@testable import CompanionHost
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
    let sampler = MacSystemStatusSampler(cpuSampleIntervalNanoseconds: 10_000_000)
    let result = try await sampler.sample()

    #expect(result.osName == "macOS")
    #expect(!result.osVersion.isEmpty)
    #expect(!result.osBuild.isEmpty)
    #expect(result.cpuUtilizationBasisPoints <= 10_000)
    #expect(result.memoryUsedBytes <= result.memoryTotalBytes)
    #expect(result.storageAvailableBytes <= result.storageTotalBytes)
}
#endif
