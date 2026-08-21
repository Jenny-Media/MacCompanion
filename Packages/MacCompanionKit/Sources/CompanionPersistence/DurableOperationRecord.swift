import CompanionDomain
import Foundation

public struct StoredDurableOperationRecord: Equatable, Sendable {
    public let operationID: UUID
    public let deviceID: UUID
    public let clientID: UUID
    public let requestDigest: Data
    public let state: OperationState
    public let capabilityID: String
    public let schemaVersion: UInt32
    public let providerID: String
    public let providerVersion: String
    public let providerGeneration: UUID
    public let executionRevision: UUID
    public let authorizationEpoch: UInt64
    public let grantRevision: UInt64
    public let policyRevision: UInt64
    public let requiredHostState: HostState
    public let expiresAtUnixMilliseconds: Int64
    public let createdAtUnixMilliseconds: Int64
    public let updatedAtUnixMilliseconds: Int64
    public let terminalAtUnixMilliseconds: Int64?
    public let terminalCode: String?

    public init(
        operationID: UUID,
        deviceID: UUID,
        clientID: UUID,
        requestDigest: Data,
        state: OperationState,
        capabilityID: String,
        schemaVersion: UInt32,
        providerID: String,
        providerVersion: String,
        providerGeneration: UUID,
        executionRevision: UUID,
        authorizationEpoch: UInt64,
        grantRevision: UInt64,
        policyRevision: UInt64,
        requiredHostState: HostState,
        expiresAtUnixMilliseconds: Int64,
        createdAtUnixMilliseconds: Int64,
        updatedAtUnixMilliseconds: Int64,
        terminalAtUnixMilliseconds: Int64? = nil,
        terminalCode: String? = nil
    ) throws {
        let maximum = MonotonicRevision<AuthorizationEpochTag>.maximumWireValue
        guard requestDigest.count == 32,
              Self.isIdentifier(capabilityID, maximum: 96),
              Self.isIdentifier(providerID, maximum: 96),
              Self.isIdentifier(providerVersion, maximum: 64),
              schemaVersion >= 1,
              (1...maximum).contains(authorizationEpoch),
              (1...maximum).contains(grantRevision),
              (1...maximum).contains(policyRevision),
              createdAtUnixMilliseconds >= 0,
              updatedAtUnixMilliseconds >= createdAtUnixMilliseconds,
              expiresAtUnixMilliseconds > createdAtUnixMilliseconds,
              UInt64(expiresAtUnixMilliseconds) <= maximum,
              state.isTerminal == (terminalAtUnixMilliseconds != nil),
              (terminalAtUnixMilliseconds.map {
                  $0 >= createdAtUnixMilliseconds && $0 <= updatedAtUnixMilliseconds
              } ?? true),
              (!state.isTerminal && terminalCode == nil) || state.isTerminal,
              (terminalCode.map { Self.isIdentifier($0, maximum: 96) } ?? true) else {
            throw SecurityStoreError.invalidRecord
        }
        self.operationID = operationID
        self.deviceID = deviceID
        self.clientID = clientID
        self.requestDigest = requestDigest
        self.state = state
        self.capabilityID = capabilityID
        self.schemaVersion = schemaVersion
        self.providerID = providerID
        self.providerVersion = providerVersion
        self.providerGeneration = providerGeneration
        self.executionRevision = executionRevision
        self.authorizationEpoch = authorizationEpoch
        self.grantRevision = grantRevision
        self.policyRevision = policyRevision
        self.requiredHostState = requiredHostState
        self.expiresAtUnixMilliseconds = expiresAtUnixMilliseconds
        self.createdAtUnixMilliseconds = createdAtUnixMilliseconds
        self.updatedAtUnixMilliseconds = updatedAtUnixMilliseconds
        self.terminalAtUnixMilliseconds = terminalAtUnixMilliseconds
        self.terminalCode = terminalCode
    }

    private static func isIdentifier(_ value: String, maximum: Int) -> Bool {
        guard !value.isEmpty, value.utf8.count <= maximum else { return false }
        return value.utf8.allSatisfy {
            (0x30...0x39).contains($0)
                || (0x41...0x5A).contains($0)
                || (0x61...0x7A).contains($0)
                || $0 == 0x2D || $0 == 0x2E || $0 == 0x5F
        }
    }
}

public enum DurableOperationAdmissionResult: Equatable, Sendable {
    case created(StoredDurableOperationRecord)
    case existing(StoredDurableOperationRecord)
}

public struct DurableOperationExecutionSnapshot: Equatable, Sendable {
    public let providerGeneration: UUID
    public let executionRevision: UUID
    public let hostState: HostState
    public let nowUnixMilliseconds: Int64

    public init(
        providerGeneration: UUID,
        executionRevision: UUID,
        hostState: HostState,
        nowUnixMilliseconds: Int64
    ) throws {
        guard nowUnixMilliseconds >= 0 else {
            throw SecurityStoreError.invalidRecord
        }
        self.providerGeneration = providerGeneration
        self.executionRevision = executionRevision
        self.hostState = hostState
        self.nowUnixMilliseconds = nowUnixMilliseconds
    }
}

public enum DurableOperationClaimResult: Equatable, Sendable {
    case claimed(StoredDurableOperationRecord)
    case failed(StoredDurableOperationRecord)
}

public struct DurableOperationStartupReconciliation: Equatable, Sendable {
    public let queuedFailed: Int
    public let inFlightOutcomeUnknown: Int

    public init(queuedFailed: Int, inFlightOutcomeUnknown: Int) {
        self.queuedFailed = queuedFailed
        self.inFlightOutcomeUnknown = inFlightOutcomeUnknown
    }

    public var totalReconciled: Int {
        queuedFailed + inFlightOutcomeUnknown
    }
}
