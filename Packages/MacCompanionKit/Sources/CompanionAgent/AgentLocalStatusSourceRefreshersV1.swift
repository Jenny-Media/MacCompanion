import CompanionIPC
import CompanionPersistence
import Foundation

public enum AgentLocalStatusSourceRefreshErrorV1:
    Error,
    Equatable,
    Sendable
{
    case boundsExceeded
    case storageUnavailable
}

/// Narrow read facets prevent local diagnostics from receiving device or
/// provider identities when only bounded counts are required.
public protocol AgentActivePairedDeviceCountReadingV1: Sendable {
    func activePairedDeviceCount() async throws -> Int
    func interactiveControlGranted() async throws -> Bool
}

public extension AgentActivePairedDeviceCountReadingV1 {
    func interactiveControlGranted() async throws -> Bool { false }
}

public protocol AgentActiveProviderCountReadingV1: Sendable {
    func activeProviderCount() async -> Int
}

extension SQLiteSecurityStore: AgentActivePairedDeviceCountReadingV1 {
    public func interactiveControlGranted() async throws -> Bool {
        let snapshots = try activeDeviceGrantIdentitySnapshots()
        return !snapshots.isEmpty && snapshots.allSatisfy {
            $0.grants.capabilityIDs.contains(
                InteractiveControlDurableGrantV0.identifier
            )
        }
    }
}
extension AgentCapabilityAuthorityV1: AgentActiveProviderCountReadingV1 {}

/// Reads the product's durable paired-device authority and immutable live
/// provider publication, then commits one content-free inventory version.
/// Route kinds are supplied by a platform route monitor; transport routing is
/// deliberately not inferred from paired identities or listener addresses.
public struct AgentLocalStatusInventoryRefresherV1: Sendable {
    private let pairedDevices: any AgentActivePairedDeviceCountReadingV1
    private let capabilities: any AgentActiveProviderCountReadingV1
    private let localStatus: AgentLocalStatusAuthorityV1

    public init(
        pairedDevices: any AgentActivePairedDeviceCountReadingV1,
        capabilities: any AgentActiveProviderCountReadingV1,
        localStatus: AgentLocalStatusAuthorityV1
    ) {
        self.pairedDevices = pairedDevices
        self.capabilities = capabilities
        self.localStatus = localStatus
    }

    public func refresh() async throws {
        let pairedCount: Int
        let interactiveControlGranted: Bool
        do {
            pairedCount = try await pairedDevices.activePairedDeviceCount()
            interactiveControlGranted = try await pairedDevices
                .interactiveControlGranted()
        } catch {
            await localStatus.updateSecurityPosture(.storageUnavailable)
            throw AgentLocalStatusSourceRefreshErrorV1.storageUnavailable
        }
        let providerCount = await capabilities.activeProviderCount()
        guard let paired = UInt16(exactly: pairedCount),
              let providers = UInt16(exactly: providerCount),
              paired <= AgentLocalStatusAuthorityV1.maximumPairedDeviceCount,
              providers <= AgentLocalStatusAuthorityV1.maximumProviderCount else {
            throw AgentLocalStatusSourceRefreshErrorV1.boundsExceeded
        }
        do {
            try await localStatus.updateInventory(
                pairedDeviceCount: paired,
                providerCount: providers,
                interactiveControlGranted: interactiveControlGranted
            )
        } catch {
            throw AgentLocalStatusSourceRefreshErrorV1.boundsExceeded
        }
    }
}

#if os(macOS)
/// Projects the emergency deny latch into the closed local security posture.
/// Corrupt or unreadable latch state is fail-closed and never exposes a path,
/// POSIX code, pending device identifier, or raw persistence error.
public struct AgentLocalStatusSecurityRefresherV1: Sendable {
    private let denyLatch: EmergencyDenyLatch
    private let localStatus: AgentLocalStatusAuthorityV1

    public init(
        denyLatch: EmergencyDenyLatch,
        localStatus: AgentLocalStatusAuthorityV1
    ) {
        self.denyLatch = denyLatch
        self.localStatus = localStatus
    }

    @discardableResult
    public func refresh() async -> LocalSecurityPosture {
        let posture: LocalSecurityPosture
        do {
            let snapshot = try await denyLatch.snapshot()
            switch snapshot.health {
            case .clear:
                posture = .nominal
            case .active:
                posture = .denyLatched
            case .corrupt:
                posture = .storageUnavailable
            }
        } catch {
            posture = .storageUnavailable
        }
        await localStatus.updateSecurityPosture(posture)
        return posture
    }
}
#endif
