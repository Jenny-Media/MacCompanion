import CompanionDomain
import Foundation

public enum HostPowerSource: String, Equatable, Sendable {
    case ac
    case battery
    case unknown
}

public enum HostStatusError: Error, Equatable, Sendable {
    case invalidSystemMeasurement
    case invalidClock
    case invalidFreshness
    case revisionExhausted
}

public struct HostSystemMeasurement: Equatable, Sendable {
    public let osName: String
    public let osVersion: String
    public let osBuild: String
    public let uptimeSeconds: UInt64
    public let cpuUtilizationBasisPoints: UInt16
    public let memoryTotalBytes: UInt64
    public let memoryUsedBytes: UInt64
    public let storageTotalBytes: UInt64
    public let storageAvailableBytes: UInt64
    public let powerSource: HostPowerSource
    public let batteryLevelPercent: UInt8?

    public init(
        osName: String,
        osVersion: String,
        osBuild: String,
        uptimeSeconds: UInt64,
        cpuUtilizationBasisPoints: UInt16,
        memoryTotalBytes: UInt64,
        memoryUsedBytes: UInt64,
        storageTotalBytes: UInt64,
        storageAvailableBytes: UInt64,
        powerSource: HostPowerSource,
        batteryLevelPercent: UInt8?
    ) throws {
        let maximum = MonotonicRevision<AuthorizationEpochTag>.maximumWireValue
        guard osName == "macOS",
              (1...32).contains(osVersion.utf8.count),
              (1...32).contains(osBuild.utf8.count),
              uptimeSeconds <= maximum,
              cpuUtilizationBasisPoints <= 10_000,
              memoryTotalBytes > 0,
              memoryTotalBytes <= maximum,
              memoryUsedBytes <= memoryTotalBytes,
              storageTotalBytes > 0,
              storageTotalBytes <= maximum,
              storageAvailableBytes <= storageTotalBytes,
              batteryLevelPercent.map({ $0 <= 100 }) ?? true else {
            throw HostStatusError.invalidSystemMeasurement
        }
        self.osName = osName
        self.osVersion = osVersion
        self.osBuild = osBuild
        self.uptimeSeconds = uptimeSeconds
        self.cpuUtilizationBasisPoints = cpuUtilizationBasisPoints
        self.memoryTotalBytes = memoryTotalBytes
        self.memoryUsedBytes = memoryUsedBytes
        self.storageTotalBytes = storageTotalBytes
        self.storageAvailableBytes = storageAvailableBytes
        self.powerSource = powerSource
        self.batteryLevelPercent = batteryLevelPercent
    }
}

public struct HostStatusSnapshot: Equatable, Sendable {
    public let hostID: UUID
    public let generation: UUID
    public let revision: UInt64
    public let observedAtUnixMilliseconds: Int64
    public let validForMilliseconds: UInt32
    public let hostState: HostState
    public let system: HostSystemMeasurement

    public var resourceID: String { "host.status" }
}

public protocol HostSystemSampling: Sendable {
    func sample() async throws -> HostSystemMeasurement
}

public protocol HostStatusClock: Sendable {
    func nowUnixMilliseconds() -> Int64
}

public protocol StatusSequenceCommitting: Sendable {
    func commit(
        expected: StatusSequenceState,
        replacement: StatusSequenceState
    ) async throws
}

public struct StatusSequenceState: Equatable, Sendable {
    public let generation: UUID
    public let nextRevision: UInt64
    public let exhausted: Bool

    public init(
        generation: UUID,
        nextRevision: UInt64 = 0,
        exhausted: Bool = false
    ) throws {
        guard nextRevision <= MonotonicRevision<AuthorizationEpochTag>.maximumWireValue,
              !(exhausted && nextRevision < MonotonicRevision<AuthorizationEpochTag>.maximumWireValue) else {
            throw HostStatusError.revisionExhausted
        }
        self.generation = generation
        self.nextRevision = nextRevision
        self.exhausted = exhausted
    }
}

public actor HostStatusAuthority {
    private let hostID: UUID
    private let sampler: any HostSystemSampling
    private let clock: any HostStatusClock
    private let sequenceCommitter: any StatusSequenceCommitting
    private let validForMilliseconds: UInt32
    private var sequence: StatusSequenceState

    public init(
        hostID: UUID,
        sequence: StatusSequenceState,
        sampler: any HostSystemSampling,
        clock: any HostStatusClock,
        sequenceCommitter: any StatusSequenceCommitting,
        validForMilliseconds: UInt32 = 5_000
    ) throws {
        guard (1...60_000).contains(validForMilliseconds) else {
            throw HostStatusError.invalidFreshness
        }
        self.hostID = hostID
        self.sequence = sequence
        self.sampler = sampler
        self.clock = clock
        self.sequenceCommitter = sequenceCommitter
        self.validForMilliseconds = validForMilliseconds
    }

    public func snapshot(hostState: HostState) async throws -> HostStatusSnapshot {
        guard !sequence.exhausted else {
            throw HostStatusError.revisionExhausted
        }

        let measurement = try await sampler.sample()
        let observedAt = clock.nowUnixMilliseconds()
        guard observedAt >= 0,
              observedAt <= Int64(MonotonicRevision<AuthorizationEpochTag>.maximumWireValue) else {
            throw HostStatusError.invalidClock
        }

        let revision = sequence.nextRevision
        let snapshot = HostStatusSnapshot(
            hostID: hostID,
            generation: sequence.generation,
            revision: revision,
            observedAtUnixMilliseconds: observedAt,
            validForMilliseconds: validForMilliseconds,
            hostState: hostState,
            system: measurement
        )

        let replacement: StatusSequenceState
        if revision == MonotonicRevision<AuthorizationEpochTag>.maximumWireValue {
            replacement = try StatusSequenceState(
                generation: sequence.generation,
                nextRevision: revision,
                exhausted: true
            )
        } else {
            replacement = try StatusSequenceState(
                generation: sequence.generation,
                nextRevision: revision + 1
            )
        }
        try await sequenceCommitter.commit(
            expected: sequence,
            replacement: replacement
        )
        sequence = replacement
        return snapshot
    }

    public func sequenceState() -> StatusSequenceState {
        sequence
    }

    public func resetSequence(generation: UUID) async throws {
        let replacement = try StatusSequenceState(generation: generation)
        try await sequenceCommitter.commit(
            expected: sequence,
            replacement: replacement
        )
        sequence = replacement
    }
}
