import CompanionPersistence
import Foundation

/// Authenticated visible-menu-app facts that must remain stable around the
/// Agent's durable device/grant read. The concrete source is a platform IPC
/// adapter; it is not allowed to provide durable security state.
public struct VisibleInteractiveAdmissionStateV0: Equatable, Sendable {
    public let generation: UUID
    public let revision: UInt64
    public let visibleMenuAppAvailable: Bool
    public let selectedDisplayID: UUID?

    public init(
        generation: UUID,
        revision: UInt64,
        visibleMenuAppAvailable: Bool,
        selectedDisplayID: UUID?
    ) {
        self.generation = generation
        self.revision = revision
        self.visibleMenuAppAvailable = visibleMenuAppAvailable
        self.selectedDisplayID = selectedDisplayID
    }
}

public protocol VisibleInteractiveAdmissionReadingV0: Sendable {
    func snapshot() async throws -> VisibleInteractiveAdmissionStateV0
}

/// Conservatively joins the product root's durable device/grant authority
/// with the visible menu app's display-selection revision. A changing IPC
/// snapshot yields no admission instead of combining different moments.
public struct SQLiteInteractiveSessionAdmissionReaderV0:
    InteractiveSessionAdmissionReadingV0,
    Sendable
{
    private let store: SQLiteSecurityStore
    private let visible: any VisibleInteractiveAdmissionReadingV0

    package init(
        store: SQLiteSecurityStore,
        visible: any VisibleInteractiveAdmissionReadingV0
    ) {
        self.store = store
        self.visible = visible
    }

    public func snapshot(deviceID: UUID) async throws
        -> InteractiveSessionAdmissionSnapshotV0? {
        let before = try await visible.snapshot()
        let durable = try await store.deviceGrantIdentitySnapshot(deviceID)
        let after = try await visible.snapshot()
        guard before == after, let displayName = durable.displayName else {
            return nil
        }
        return try InteractiveSessionAdmissionSnapshotV0(
            deviceID: durable.device.deviceID,
            clientID: durable.device.clientID,
            deviceState: durable.device.authorization.state,
            authorizationEpoch: durable.device.authorization.authorizationEpoch,
            grantRevision: durable.device.authorization.grantRevision,
            policyRevision: durable.device.policyRevision,
            approvalPublicKeyX963: durable.device.approvalPublicKeyX963,
            grants: durable.grants,
            deviceDisplayName: displayName,
            visibleMenuAppAvailable: before.visibleMenuAppAvailable,
            visibleMenuAppGeneration: before.generation,
            visibleMenuAppRevision: before.revision,
            selectedDisplayID: before.selectedDisplayID
        )
    }
}
