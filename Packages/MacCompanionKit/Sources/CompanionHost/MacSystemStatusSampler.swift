#if os(macOS)
import Darwin
import Foundation
import IOKit.ps

public enum MacSystemStatusSamplerError: Error, Equatable, Sendable {
    case systemCall(name: String, code: Int32)
    case missingFilesystemMetric(String)
    case invalidCounterDelta
}

public struct SystemHostStatusClock: HostStatusClock {
    public init() {}

    public func nowUnixMilliseconds() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
    }
}

public struct MacSystemStatusSampler: HostSystemSampling {
    public let cpuSampleIntervalNanoseconds: UInt64

    public init(cpuSampleIntervalNanoseconds: UInt64 = 100_000_000) {
        self.cpuSampleIntervalNanoseconds = cpuSampleIntervalNanoseconds
    }

    public func sample() async throws -> HostSystemMeasurement {
        let cpu = try await Self.sampleCPUUtilization(
            initialIntervalNanoseconds: cpuSampleIntervalNanoseconds,
            readTicks: Self.readCPUTicks,
            sleep: { try await Task<Never, Never>.sleep(nanoseconds: $0) }
        )
        let memory = try Self.readMemory()
        let storage = try Self.readStorage()
        let power = Self.readPower()

        let version = ProcessInfo.processInfo.operatingSystemVersion
        let versionString = [version.majorVersion, version.minorVersion, version.patchVersion]
            .drop(while: { $0 == 0 })
            .map(String.init)
            .joined(separator: ".")

        return try HostSystemMeasurement(
            osName: "macOS",
            osVersion: versionString.isEmpty ? "0" : versionString,
            osBuild: try Self.readSysctlString("kern.osversion"),
            uptimeSeconds: UInt64(ProcessInfo.processInfo.systemUptime.rounded(.down)),
            cpuUtilizationBasisPoints: cpu,
            memoryTotalBytes: memory.total,
            memoryUsedBytes: memory.used,
            storageTotalBytes: storage.total,
            storageAvailableBytes: storage.available,
            powerSource: power.source,
            batteryLevelPercent: power.batteryLevelPercent
        )
    }

    struct CPUTicks: Equatable, Sendable {
        let user: UInt32
        let system: UInt32
        let idle: UInt32
        let nice: UInt32
    }

    static func sampleCPUUtilization(
        initialIntervalNanoseconds: UInt64,
        readTicks: @Sendable () throws -> CPUTicks,
        sleep: @Sendable (UInt64) async throws -> Void
    ) async throws -> UInt16 {
        try Task.checkCancellation()
        let first = try readTicks()
        try await sleep(initialIntervalNanoseconds)
        try Task.checkCancellation()
        var last = try readTicks()
        if last == first {
            // XNU rate-limits host_statistics with a shared one-second cache.
            // Identical counters are not a measured idle CPU. Extend this
            // sample once beyond that window instead of failing a healthy
            // Observe request or hammering the same cached counters.
            try await sleep(1_100_000_000)
            try Task.checkCancellation()
            last = try readTicks()
        }
        // Still unchanged: return the existing provider error, never invent
        // a utilization value or retry indefinitely.
        return try utilizationBasisPoints(from: first, to: last)
    }

    static func utilizationBasisPoints(
        from first: CPUTicks,
        to second: CPUTicks
    ) throws -> UInt16 {
        let user = UInt64(second.user &- first.user)
        let system = UInt64(second.system &- first.system)
        let idle = UInt64(second.idle &- first.idle)
        let nice = UInt64(second.nice &- first.nice)
        let total = user + system + idle + nice
        guard total > 0 else {
            throw MacSystemStatusSamplerError.invalidCounterDelta
        }
        let active = total - idle
        return UInt16(min(10_000, (active * 10_000 + total / 2) / total))
    }

    private static func readCPUTicks() throws -> CPUTicks {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) { rebound in
                host_statistics(
                    mach_host_self(),
                    HOST_CPU_LOAD_INFO,
                    rebound,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else {
            throw MacSystemStatusSamplerError.systemCall(
                name: "host_statistics(HOST_CPU_LOAD_INFO)",
                code: result
            )
        }
        return CPUTicks(
            user: info.cpu_ticks.0,
            system: info.cpu_ticks.1,
            idle: info.cpu_ticks.2,
            nice: info.cpu_ticks.3
        )
    }

    private static func readMemory() throws -> (total: UInt64, used: UInt64) {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) { rebound in
                host_statistics64(
                    mach_host_self(),
                    HOST_VM_INFO64,
                    rebound,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else {
            throw MacSystemStatusSamplerError.systemCall(
                name: "host_statistics64(HOST_VM_INFO64)",
                code: result
            )
        }

        var pageSize: vm_size_t = 0
        let pageResult = host_page_size(mach_host_self(), &pageSize)
        guard pageResult == KERN_SUCCESS else {
            throw MacSystemStatusSamplerError.systemCall(
                name: "host_page_size",
                code: pageResult
            )
        }

        let total = ProcessInfo.processInfo.physicalMemory
        let freeBytes = min(total, UInt64(stats.free_count) * UInt64(pageSize))
        return (total, total - freeBytes)
    }

    private static func readStorage() throws -> (total: UInt64, available: UInt64) {
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: "/")
        guard let total = (attributes[.systemSize] as? NSNumber)?.uint64Value else {
            throw MacSystemStatusSamplerError.missingFilesystemMetric("systemSize")
        }
        guard let available = (attributes[.systemFreeSize] as? NSNumber)?.uint64Value else {
            throw MacSystemStatusSamplerError.missingFilesystemMetric("systemFreeSize")
        }
        return (total, min(total, available))
    }

    private static func readPower() -> (source: HostPowerSource, batteryLevelPercent: UInt8?) {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let type = IOPSGetProvidingPowerSourceType(snapshot).takeUnretainedValue() as NSString
        let source: HostPowerSource
        switch type as String {
        case kIOPMACPowerKey, kIOPMUPSPowerKey:
            source = .ac
        case kIOPMBatteryPowerKey:
            source = .battery
        default:
            source = .unknown
        }

        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as NSArray
        for item in sources {
            let description = IOPSGetPowerSourceDescription(
                snapshot,
                item as CFTypeRef
            ).takeUnretainedValue() as NSDictionary
            guard (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let current = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue,
                  let maximum = (description[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue,
                  maximum > 0 else {
                continue
            }
            let percent = min(100, max(0, Int((current * 100 / maximum).rounded())))
            return (source, UInt8(percent))
        }
        return (source, nil)
    }

    private static func readSysctlString(_ name: String) throws -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0 else {
            throw MacSystemStatusSamplerError.systemCall(name: name, code: errno)
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            throw MacSystemStatusSamplerError.systemCall(name: name, code: errno)
        }
        let bytes = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
#endif
