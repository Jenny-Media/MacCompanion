import Foundation
import CompanionInteractiveShared
import CompanionInteractiveWire

/// Facts from the authenticated, acknowledged Desktop runtime. The display
/// token is the menu selection joined by admission, never a remote display ID.
public struct InteractiveNativeVideoRuntimeSnapshotV0: Equatable, Sendable {
    public let binding: InteractiveNativeVideoBindingV0
    public let surface: InteractiveNativeVideoSurfaceV0
    public let logicalWidthPoints: UInt32
    public let logicalHeightPoints: UInt32
    public let rotation: SurfaceRotation
    public let selectedDisplayID: UUID
    public let visibleMenuAppGeneration: UUID
    public let visibleMenuAppRevision: UInt64

    public init(binding: InteractiveNativeVideoBindingV0, surface: InteractiveNativeVideoSurfaceV0,
                logicalWidthPoints: UInt32, logicalHeightPoints: UInt32, rotation: SurfaceRotation,
                selectedDisplayID: UUID, visibleMenuAppGeneration: UUID, visibleMenuAppRevision: UInt64) {
        self.binding = binding
        self.surface = surface
        self.logicalWidthPoints = logicalWidthPoints
        self.logicalHeightPoints = logicalHeightPoints
        self.rotation = rotation
        self.selectedDisplayID = selectedDisplayID
        self.visibleMenuAppGeneration = visibleMenuAppGeneration
        self.visibleMenuAppRevision = visibleMenuAppRevision
    }
}

/// Platform composition supplies runtime measurements and an inert backend.
/// It does not supply the durable grant or registered signing key.
public protocol InteractiveNativeVideoRuntimeProvidingV0: Sendable {
    func snapshot(fence: InteractiveNativeVideoRequestFenceV0,
                  context: InteractiveSessionCommandContextV0) async throws -> InteractiveNativeVideoRuntimeSnapshotV0?
    func makeBackend(snapshot: InteractiveNativeVideoRuntimeSnapshotV0) async throws -> any InteractiveNativeVideoEnrollmentBackendV0
}

/// Binds every coordinator read to the same reconciled admission store used by
/// the primary dispatcher. A platform cannot replace that reader with its own.
public struct InteractiveNativeVideoRuntimeCompositionV0: Sendable {
    private let admission: any InteractiveSessionAdmissionReadingV0
    private let runtime: any InteractiveNativeVideoRuntimeProvidingV0
    private let monotonicMilliseconds: @Sendable () -> UInt64
    private let unixMilliseconds: @Sendable () -> UInt64

    public init(admission: any InteractiveSessionAdmissionReadingV0,
                runtime: any InteractiveNativeVideoRuntimeProvidingV0,
                monotonicMilliseconds: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds / 1_000_000 },
                unixMilliseconds: @escaping @Sendable () -> UInt64 = { UInt64(max(0, Date().timeIntervalSince1970 * 1000)) }) {
        self.admission = admission
        self.runtime = runtime
        self.monotonicMilliseconds = monotonicMilliseconds
        self.unixMilliseconds = unixMilliseconds
    }

    public func bridge() -> InteractiveNativeVideoPrimaryBridgeV0 {
        .init { fence, context, registeredKey in
            let expected = try await self.read(fence: fence, context: context, registeredKey: registeredKey)
            guard let expected else { throw InteractiveNativeVideoCoordinatorFailureV0.authorizationLost }
            let backend = try await self.runtime.makeBackend(snapshot: expected.runtime)
            // Backend construction must be inert. Recheck before any credential
            // preparation; cancellation during construction cannot leak it.
            guard !Task.isCancelled,
                  try await self.read(fence: fence, context: context, registeredKey: registeredKey) == expected else {
                // No prepare operation exists yet; the bridge creates no owner.
                throw InteractiveNativeVideoCoordinatorFailureV0.authorizationLost
            }
            return .init(authority: expected.authority, backend: backend,
                readAuthority: {
                    guard let current = try await self.read(fence: fence, context: context, registeredKey: registeredKey),
                          current == expected else { return nil }
                    return current.authority
                }, monotonicMilliseconds: self.monotonicMilliseconds, unixMilliseconds: self.unixMilliseconds,
                logicalWidthPoints: expected.runtime.logicalWidthPoints,
                logicalHeightPoints: expected.runtime.logicalHeightPoints)
        }
    }

    private struct Joined: Equatable, Sendable {
        let runtime: InteractiveNativeVideoRuntimeSnapshotV0
        let admission: InteractiveSessionAdmissionSnapshotV0
        let authority: InteractiveNativeVideoAuthorityV0
    }

    private func read(fence: InteractiveNativeVideoRequestFenceV0,
                      context: InteractiveSessionCommandContextV0, registeredKey: Data) async throws -> Joined? {
        guard !Task.isCancelled,
              let before = try await admission.snapshot(deviceID: context.deviceID),
              InteractiveSessionRuntimeRequirementV0(command: context, admission: before).isEligibleForInteractiveControl,
              before.sessionPublicKeyX963 == registeredKey,
              let current = try await runtime.snapshot(fence: fence, context: context),
              let after = try await admission.snapshot(deviceID: context.deviceID), before == after else { return nil }
        let b = current.binding, s = current.surface
        guard !Task.isCancelled, b.hostID == context.hostID, b.hostFingerprint == context.hostFingerprint,
              b.clientID == context.clientID, b.primaryConnectionID == context.primaryConnectionID,
              b.interactiveSessionID == fence.interactiveSessionID.rawValue,
              b.authorizationEpoch == context.authorizationEpoch.rawValue,
              b.grantRevision == context.grantRevision.rawValue, b.policyRevision == context.policyRevision.rawValue,
              fence.authorizationEpoch == context.authorizationEpoch,
              s.surfaceID == fence.surfaceID.rawValue, s.surfaceRevision == fence.surfaceRevision,
              s.coordinateSpaceRevision == fence.coordinateSpaceRevision,
              current.logicalWidthPoints > 0, current.logicalHeightPoints > 0,
              before.selectedDisplayID == current.selectedDisplayID,
              before.visibleMenuAppGeneration == current.visibleMenuAppGeneration,
              before.visibleMenuAppRevision == current.visibleMenuAppRevision,
              monotonicMilliseconds() < b.expiresAtMonotonicMilliseconds else { return nil }
        return try .init(runtime: current, admission: before,
            authority: .init(binding: b, surface: s, sessionPublicKeyX963: registeredKey))
    }
}
