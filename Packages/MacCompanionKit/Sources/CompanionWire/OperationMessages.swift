import CompanionDomain
import Foundation

public struct OperationInvokeRequestBody: WireBody {
    private enum CodingKeys: String, CodingKey {
        case operationID, capabilityID, parameters
    }

    public static let kind = WireMessageKind.operationInvoke
    public let operationID: WireUUID
    public let capabilityID: String
    public let parameters: CanonicalJSONValue

    public init(
        operationID: WireUUID,
        capabilityID: String,
        parameters: CanonicalJSONValue
    ) throws {
        self.operationID = operationID
        self.capabilityID = capabilityID
        self.parameters = parameters
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["operationID", "capabilityID", "parameters"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        operationID = try container.decode(WireUUID.self, forKey: .operationID)
        capabilityID = try container.decode(String.self, forKey: .capabilityID)
        parameters = try container.decode(CanonicalJSONValue.self, forKey: .parameters)
        try validate()
    }

    public func validate() throws {
        guard isWireIdentifier(capabilityID, maximum: 96) else {
            throw WireError.invalidFrame(reason: "invalid capabilityID")
        }
        guard case .object = parameters else {
            throw WireError.invalidFrame(reason: "operation parameters must be an object")
        }
        try CanonicalJSON.validate(parameters)
    }
}

public struct OperationApprovalRequiredBody: WireBody {
    private enum CodingKeys: String, CodingKey {
        case operationID, approvalID, operationDigest, serverChallenge
        case issuedAtUnixMilliseconds, expiresAtUnixMilliseconds
    }

    public static let kind = WireMessageKind.operationApprovalRequired
    public let operationID: WireUUID
    public let approvalID: WireUUID
    public let operationDigest: WireBytes32
    public let serverChallenge: WireBytes32
    public let issuedAtUnixMilliseconds: Int64
    public let expiresAtUnixMilliseconds: Int64

    public init(
        operationID: WireUUID,
        approvalID: WireUUID,
        operationDigest: WireBytes32,
        serverChallenge: WireBytes32,
        issuedAtUnixMilliseconds: Int64,
        expiresAtUnixMilliseconds: Int64
    ) throws {
        self.operationID = operationID
        self.approvalID = approvalID
        self.operationDigest = operationDigest
        self.serverChallenge = serverChallenge
        self.issuedAtUnixMilliseconds = issuedAtUnixMilliseconds
        self.expiresAtUnixMilliseconds = expiresAtUnixMilliseconds
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, [
            "operationID", "approvalID", "operationDigest", "serverChallenge",
            "issuedAtUnixMilliseconds", "expiresAtUnixMilliseconds",
        ])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        operationID = try c.decode(WireUUID.self, forKey: .operationID)
        approvalID = try c.decode(WireUUID.self, forKey: .approvalID)
        operationDigest = try c.decode(WireBytes32.self, forKey: .operationDigest)
        serverChallenge = try c.decode(WireBytes32.self, forKey: .serverChallenge)
        issuedAtUnixMilliseconds = try c.decode(Int64.self, forKey: .issuedAtUnixMilliseconds)
        expiresAtUnixMilliseconds = try c.decode(Int64.self, forKey: .expiresAtUnixMilliseconds)
        try validate()
    }

    public func validate() throws {
        guard issuedAtUnixMilliseconds >= 1,
              expiresAtUnixMilliseconds > issuedAtUnixMilliseconds,
              expiresAtUnixMilliseconds <= WireLimits.maximumSafeInteger,
              expiresAtUnixMilliseconds - issuedAtUnixMilliseconds <= 60_000 else {
            throw WireError.invalidFrame(reason: "invalid operation approval lifetime")
        }
    }
}

public struct OperationApproveRequestBody: WireBody {
    private enum CodingKeys: String, CodingKey { case approvalID, signature }
    public static let kind = WireMessageKind.operationApprove
    public let approvalID: WireUUID
    public let signature: WireBytes64

    public init(approvalID: WireUUID, signature: WireBytes64) {
        self.approvalID = approvalID
        self.signature = signature
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["approvalID", "signature"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        approvalID = try c.decode(WireUUID.self, forKey: .approvalID)
        signature = try c.decode(WireBytes64.self, forKey: .signature)
    }

    public func validate() throws {}
}

public struct OperationStatusRequestBody: WireBody {
    private enum CodingKeys: String, CodingKey { case operationID }
    public static let kind = WireMessageKind.operationStatusRequest
    public let operationID: WireUUID

    public init(operationID: WireUUID) { self.operationID = operationID }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["operationID"])
        operationID = try decoder.container(keyedBy: CodingKeys.self)
            .decode(WireUUID.self, forKey: .operationID)
    }

    public func validate() throws {}
}

public struct OperationCancelRequestBody: WireBody {
    private enum CodingKeys: String, CodingKey { case operationID }
    public static let kind = WireMessageKind.operationCancel
    public let operationID: WireUUID

    public init(operationID: WireUUID) { self.operationID = operationID }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["operationID"])
        operationID = try decoder.container(keyedBy: CodingKeys.self)
            .decode(WireUUID.self, forKey: .operationID)
    }

    public func validate() throws {}
}

public struct OperationStatusResponseBody: WireBody {
    private enum CodingKeys: String, CodingKey {
        case operationID, state, terminalCode, result
    }

    public static let kind = WireMessageKind.operationStatusResponse
    public let operationID: WireUUID
    public let state: OperationState
    public let terminalCode: String?
    public let result: CanonicalJSONValue?

    public init(
        operationID: WireUUID,
        state: OperationState,
        terminalCode: String?,
        result: CanonicalJSONValue?
    ) throws {
        self.operationID = operationID
        self.state = state
        self.terminalCode = terminalCode
        self.result = result
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(operationID, forKey: .operationID)
        try c.encode(state, forKey: .state)
        if let terminalCode { try c.encode(terminalCode, forKey: .terminalCode) }
        else { try c.encodeNil(forKey: .terminalCode) }
        if let result { try c.encode(result, forKey: .result) }
        else { try c.encodeNil(forKey: .result) }
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["operationID", "state", "terminalCode", "result"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        operationID = try c.decode(WireUUID.self, forKey: .operationID)
        state = try c.decode(OperationState.self, forKey: .state)
        terminalCode = try c.decodeIfPresent(String.self, forKey: .terminalCode)
        result = try c.decodeIfPresent(CanonicalJSONValue.self, forKey: .result)
        try validate()
    }

    public func validate() throws {
        guard terminalCode.map({ isWireIdentifier($0, maximum: 96) }) ?? true else {
            throw WireError.invalidFrame(reason: "invalid operation terminal code")
        }
        guard state.isTerminal || terminalCode == nil else {
            throw WireError.invalidFrame(reason: "nonterminal operation has terminal code")
        }
        guard result == nil || state == .succeeded else {
            throw WireError.invalidFrame(reason: "only succeeded operation may carry result")
        }
        if let result, case .object = result {} else if result != nil {
            throw WireError.invalidFrame(reason: "operation result must be an object")
        }
        if let result {
            try CanonicalJSON.validate(result)
        }
    }
}

private func isWireIdentifier(_ value: String, maximum: Int) -> Bool {
    guard (1...maximum).contains(value.utf8.count) else { return false }
    return value.utf8.allSatisfy {
        (0x30...0x39).contains($0)
            || (0x41...0x5A).contains($0)
            || (0x61...0x7A).contains($0)
            || $0 == 0x2D || $0 == 0x2E || $0 == 0x5F
    }
}
