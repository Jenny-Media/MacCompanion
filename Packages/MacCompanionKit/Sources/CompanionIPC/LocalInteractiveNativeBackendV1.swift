import CompanionInteractiveShared
import CompanionInteractiveWire
import Foundation

public enum LocalInteractiveNativeBackendErrorV1: Error, Equatable, Sendable {
    case invalidMaterial, bindingMismatch, unavailable
}
public enum LocalInteractiveNativeBackendOperationV1: String, Codable, Sendable {
    case prepare, activate, health, present, retire
}

/// Public primary/runtime scope supplied by the already admitted Agent owner.
/// Physical display mapping, credentials and process paths never cross XPC.
public struct LocalInteractiveNativeBackendScopeV1: Codable, Equatable, Sendable {
    public let hostID: UUID
    public let hostFingerprintBase64: String
    public let clientID: UUID
    public let primaryConnectionIDBase64: String
    public let interactiveSessionID: UUID
    public let authorizationEpoch: Int64
    public let grantRevision: Int64
    public let policyRevision: Int64
    public let controlGeneration: UUID
    public let expiresAtMonotonicMilliseconds: UInt64
    public let surfaceID: UUID
    public let surfaceRevision: Int64
    public let coordinateSpaceRevision: Int64
    public let encodedWidth: Int
    public let encodedHeight: Int
    public let logicalWidthPoints: UInt32
    public let logicalHeightPoints: UInt32
    public let rotation: SurfaceRotation
    public let selectedDisplayID: UUID
    public let menuAppGeneration: UUID
    public let menuAppRevision: UInt64
    public let sessionPublicKeyX963Base64: String

    public init(binding: InteractiveNativeVideoBindingV0, surface: InteractiveNativeVideoSurfaceV0,
        logicalWidthPoints: UInt32, logicalHeightPoints: UInt32, rotation: SurfaceRotation,
        selectedDisplayID: UUID, menuAppGeneration: UUID, menuAppRevision: UInt64, sessionPublicKeyX963: Data) throws {
        hostID = binding.hostID; hostFingerprintBase64 = binding.hostFingerprint.base64EncodedString()
        clientID = binding.clientID; primaryConnectionIDBase64 = binding.primaryConnectionID.base64EncodedString()
        interactiveSessionID = binding.interactiveSessionID; authorizationEpoch = binding.authorizationEpoch
        grantRevision = binding.grantRevision; policyRevision = binding.policyRevision; controlGeneration = binding.controlGeneration
        expiresAtMonotonicMilliseconds = binding.expiresAtMonotonicMilliseconds
        surfaceID = surface.surfaceID; surfaceRevision = surface.surfaceRevision; coordinateSpaceRevision = surface.coordinateSpaceRevision
        encodedWidth = surface.encodedWidth; encodedHeight = surface.encodedHeight
        self.logicalWidthPoints = logicalWidthPoints; self.logicalHeightPoints = logicalHeightPoints; self.rotation = rotation
        self.selectedDisplayID = selectedDisplayID; self.menuAppGeneration = menuAppGeneration; self.menuAppRevision = menuAppRevision
        sessionPublicKeyX963Base64 = sessionPublicKeyX963.base64EncodedString()
        try validate()
    }
    public func binding() throws -> InteractiveNativeVideoBindingV0 {
        try .init(hostID: hostID, hostFingerprint: Self.bytes(hostFingerprintBase64, count: 32...32),
            clientID: clientID, primaryConnectionID: Self.bytes(primaryConnectionIDBase64, count: 16...16),
            interactiveSessionID: interactiveSessionID, authorizationEpoch: authorizationEpoch,
            grantRevision: grantRevision, policyRevision: policyRevision, controlGeneration: controlGeneration,
            expiresAtMonotonicMilliseconds: expiresAtMonotonicMilliseconds)
    }
    public func surface() throws -> InteractiveNativeVideoSurfaceV0 {
        try .init(surfaceID: surfaceID, surfaceRevision: surfaceRevision, coordinateSpaceRevision: coordinateSpaceRevision,
            encodedWidth: encodedWidth, encodedHeight: encodedHeight)
    }
    public func sessionPublicKeyX963() throws -> Data { try Self.bytes(sessionPublicKeyX963Base64, count: 65...65) }
    public func validate() throws {
        _ = try binding(); _ = try surface()
        guard try sessionPublicKeyX963().first == 4, menuAppRevision > 0, menuAppRevision <= 9_007_199_254_740_991,
              logicalWidthPoints > 0, logicalHeightPoints > 0,
              expiresAtMonotonicMilliseconds <= 9_007_199_254_740_991 else { throw LocalInteractiveNativeBackendErrorV1.invalidMaterial }
    }
    public func runtimeFence(backendID: UUID) throws -> InteractiveNativeVideoRequestFenceV0 {
        try validate()
        return try .init(interactiveSessionID: .init(interactiveSessionID), authorizationEpoch: .init(rawValue: UInt64(authorizationEpoch)),
            negotiationID: .init(backendID), peerGeneration: 1, surfaceID: .init(surfaceID),
            surfaceRevision: surfaceRevision, coordinateSpaceRevision: coordinateSpaceRevision)
    }
    public func matches(_ snapshot: LocalInteractiveNativeRuntimeSnapshotV1) -> Bool {
        guard authorizationEpoch > 0 else { return false }
        return snapshot.hostID == hostID && snapshot.fence.interactiveSessionID.rawValue == interactiveSessionID
            && snapshot.fence.authorizationEpoch.rawValue == UInt64(authorizationEpoch)
            && snapshot.fence.surfaceID.rawValue == surfaceID && snapshot.fence.surfaceRevision == surfaceRevision
            && snapshot.fence.coordinateSpaceRevision == coordinateSpaceRevision
            && snapshot.encodedWidth == encodedWidth && snapshot.encodedHeight == encodedHeight
            && snapshot.logicalWidthPoints == logicalWidthPoints && snapshot.logicalHeightPoints == logicalHeightPoints
            && snapshot.rotation == rotation
            && snapshot.selectedDisplayID == selectedDisplayID && snapshot.controlGeneration == controlGeneration
            && snapshot.menuAppGeneration == menuAppGeneration && snapshot.menuAppRevision == menuAppRevision
            && snapshot.sessionDeadlineMonotonicNanoseconds / 1_000_000 == expiresAtMonotonicMilliseconds
    }
    public static func bytes(_ value: String, count: ClosedRange<Int>) throws -> Data {
        guard value.utf8.count <= ((count.upperBound + 2) / 3) * 4,
              let data = Data(base64Encoded: value), count.contains(data.count), data.base64EncodedString() == value else {
            throw LocalInteractiveNativeBackendErrorV1.invalidMaterial
        }
        return data
    }
}

public struct LocalInteractiveNativeBackendCommandV1: Codable, Equatable, Sendable {
    public let commandID: UUID
    public let backendID: UUID
    public let operationID: UUID
    public let operation: LocalInteractiveNativeBackendOperationV1
    public let scope: LocalInteractiveNativeBackendScopeV1
    public let clientCertificateDERBase64: String?
    public let nativeGeneration: Int64?
    public let presentationID: UUID?
    public init(commandID: UUID, backendID: UUID, operationID: UUID, operation: LocalInteractiveNativeBackendOperationV1,
        scope: LocalInteractiveNativeBackendScopeV1, clientCertificateDER: Data? = nil, nativeGeneration: Int64? = nil, presentationID: UUID? = nil) throws {
        self.commandID = commandID; self.backendID = backendID; self.operationID = operationID; self.operation = operation
        self.scope = scope; clientCertificateDERBase64 = clientCertificateDER?.base64EncodedString()
        self.nativeGeneration = nativeGeneration; self.presentationID = presentationID
        try validate()
    }
    public func validate() throws {
        try scope.validate()
        if operation == .present {
            guard let nativeGeneration, (1...9_007_199_254_740_991).contains(nativeGeneration), presentationID != nil else {
                throw LocalInteractiveNativeBackendErrorV1.invalidMaterial
            }
        } else if nativeGeneration != nil || presentationID != nil { throw LocalInteractiveNativeBackendErrorV1.invalidMaterial }
        if operation == .prepare {
            guard let clientCertificateDERBase64 else { throw LocalInteractiveNativeBackendErrorV1.invalidMaterial }
            _ = try LocalInteractiveNativeBackendScopeV1.bytes(clientCertificateDERBase64, count: 1...4096)
        } else if clientCertificateDERBase64 != nil { throw LocalInteractiveNativeBackendErrorV1.invalidMaterial }
    }
}

public struct LocalInteractiveNativeBackendReceiptV1: Codable, Equatable, Sendable {
    public let correlationID: UUID
    public let backendID: UUID
    public let operationID: UUID
    public let operation: LocalInteractiveNativeBackendOperationV1
    public let hostCertificateDERBase64: String?
    public let portBase: UInt16?
    public let active: Bool?
    public let captureEvidence: InteractiveNativeVideoCaptureEvidenceV0?
    public let inputAdmitted: Bool?
    public let nativeGeneration: Int64?
    public let presentationID: UUID?
    public init(command: LocalInteractiveNativeBackendCommandV1, hostCertificateDER: Data? = nil,
        portBase: UInt16? = nil, active: Bool? = nil, captureEvidence: InteractiveNativeVideoCaptureEvidenceV0? = nil, inputAdmitted: Bool? = nil) throws {
        correlationID = command.commandID; backendID = command.backendID; operationID = command.operationID; operation = command.operation
        hostCertificateDERBase64 = hostCertificateDER?.base64EncodedString(); self.portBase = portBase; self.active = active; self.captureEvidence = captureEvidence
        self.inputAdmitted = inputAdmitted; nativeGeneration = command.nativeGeneration; presentationID = command.presentationID
        try validate(against: command)
    }
    public func validate() throws {
        if let captureEvidence {
            try captureEvidence.validateShape()
            guard (operation == .health || operation == .present), active == true, captureEvidence.operationID == operationID else {
                throw LocalInteractiveNativeBackendErrorV1.bindingMismatch
            }
        }
        if operation != .present, inputAdmitted != nil || nativeGeneration != nil || presentationID != nil {
            throw LocalInteractiveNativeBackendErrorV1.invalidMaterial
        }
        switch operation {
        case .present:
            guard hostCertificateDERBase64 == nil, portBase == nil, active == true,
                  inputAdmitted == true, captureEvidence != nil,
                  let nativeGeneration, (1...9_007_199_254_740_991).contains(nativeGeneration), presentationID != nil else {
                throw LocalInteractiveNativeBackendErrorV1.invalidMaterial
            }
        case .prepare:
            guard let hostCertificateDERBase64, portBase == nil, active == nil else { throw LocalInteractiveNativeBackendErrorV1.invalidMaterial }
            _ = try LocalInteractiveNativeBackendScopeV1.bytes(hostCertificateDERBase64, count: 1...4096)
        case .activate:
            guard hostCertificateDERBase64 == nil, let portBase, portBase > 1029, portBase < 65500, active == nil else {
                throw LocalInteractiveNativeBackendErrorV1.invalidMaterial
            }
        case .health:
            guard hostCertificateDERBase64 == nil, portBase == nil, active != nil else { throw LocalInteractiveNativeBackendErrorV1.invalidMaterial }
        case .retire:
            guard hostCertificateDERBase64 == nil, portBase == nil, active == nil else { throw LocalInteractiveNativeBackendErrorV1.invalidMaterial }
        }
    }
    public func validate(against command: LocalInteractiveNativeBackendCommandV1) throws {
        try command.validate(); try validate()
        guard correlationID == command.commandID, backendID == command.backendID, operationID == command.operationID,
              operation == command.operation, nativeGeneration == command.nativeGeneration, presentationID == command.presentationID else { throw LocalInteractiveNativeBackendErrorV1.bindingMismatch }
        try captureEvidence?.validate(operationID: command.operationID, encodedWidth: command.scope.encodedWidth,
            encodedHeight: command.scope.encodedHeight, nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
    }
}
