import Foundation

public enum ProtocolErrorRetry: String, Codable, Equatable, Sendable {
    case never
    case afterUserAction
    case afterReconnect
    case afterApproval
    case backoff
}

public struct ProtocolErrorResponseBody: WireBody {
    private enum CodingKeys: String, CodingKey {
        case code, retry, safeArguments
    }

    public static let kind = WireMessageKind.error
    public let code: String
    public let retry: ProtocolErrorRetry
    public let safeArguments: CanonicalJSONValue

    public init(
        code: String,
        retry: ProtocolErrorRetry,
        safeArguments: CanonicalJSONValue = .object([])
    ) throws {
        self.code = code
        self.retry = retry
        self.safeArguments = safeArguments
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["code", "retry", "safeArguments"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        retry = try container.decode(ProtocolErrorRetry.self, forKey: .retry)
        safeArguments = try container.decode(
            CanonicalJSONValue.self,
            forKey: .safeArguments
        )
        try validate()
    }

    public func validate() throws {
        guard let rules = Self.argumentRegistry[code] else {
            throw WireError.invalidFrame(reason: "unregistered error code")
        }
        guard case let .object(arguments) = safeArguments,
              arguments.count <= 16 else {
            throw WireError.invalidFrame(reason: "invalid error safeArguments")
        }
        try CanonicalJSON.validate(safeArguments)
        for argument in arguments {
            guard let rule = rules[argument.key] else {
                throw WireError.invalidFrame(reason: "unregistered safe argument")
            }
            try Self.validate(argument.value, rule: rule)
        }
    }

    private enum ArgumentRule: Sendable {
        case identifier(maximum: Int)
        case uuid
        case nonnegativeInteger
        case stringEnum(Set<String>)
    }

    private static let noArguments: [String: ArgumentRule] = [:]
    private static let argumentRegistry: [String: [String: ArgumentRule]] = [
        "protocol.invalidFrame": [
            "reasonCode": .stringEnum([
                "duplicateKey", "invalidBody", "invalidCorrelation",
                "invalidJSON", "invalidScalar", "unknownField",
            ]),
        ],
        "protocol.unsupportedVersion": [
            "supportedMajor": .nonnegativeInteger,
            "supportedMinor": .nonnegativeInteger,
        ],
        "protocol.unknownKind": ["kind": .identifier(maximum: 96)],
        "protocol.duplicateMessage": noArguments,
        "protocol.boundsExceeded": [
            "field": .identifier(maximum: 96),
            "limit": .nonnegativeInteger,
        ],
        "protocol.operationIDConflict": ["operationID": .uuid],
        "auth.unknownDevice": noArguments,
        "auth.invalidProof": noArguments,
        "auth.deviceSuspended": noArguments,
        "auth.deviceRevoked": noArguments,
        "auth.staleEpoch": noArguments,
        "pairing.expired": noArguments,
        "pairing.invalidProof": noArguments,
        "pairing.alreadyConsumed": noArguments,
        "policy.denied": ["capabilityID": .identifier(maximum: 96)],
        "policy.approvalRequired": [
            "capabilityID": .identifier(maximum: 96),
        ],
        "operation.authorizationRevoked": ["operationID": .uuid],
        "operation.hostRestarted": ["operationID": .uuid],
        "operation.outcomeUnknown": ["operationID": .uuid],
        "operation.notFound": ["operationID": .uuid],
        "operation.approvalNotFound": noArguments,
        "interactive.sessionActive": noArguments,
        "provider.unavailable": noArguments,
        "capability.registryChanged": noArguments,
        "storage.securityUnavailable": [
            "recovery": .stringEnum(["localRepair", "reenableService"]),
        ],
        "rateLimit.exceeded": [
            "retryAfterMilliseconds": .nonnegativeInteger,
        ],
    ]

    private static func validate(
        _ value: CanonicalJSONValue,
        rule: ArgumentRule
    ) throws {
        switch (rule, value) {
        case let (.identifier(maximum), .string(value)):
            guard isIdentifier(value, maximum: maximum) else {
                throw WireError.invalidFrame(reason: "invalid safe identifier")
            }
        case let (.uuid, .string(value)):
            guard value.utf8.count == 36,
                  value == value.lowercased(),
                  UUID(uuidString: value)?.uuidString.lowercased() == value else {
                throw WireError.invalidFrame(reason: "invalid safe UUID")
            }
        case let (.nonnegativeInteger, .integer(value)):
            guard value >= 0 else {
                throw WireError.invalidFrame(reason: "negative safe integer")
            }
        case let (.stringEnum(values), .string(value)):
            guard value.utf8.count <= 256, values.contains(value) else {
                throw WireError.invalidFrame(reason: "invalid safe enum")
            }
        default:
            throw WireError.invalidFrame(reason: "invalid safe argument type")
        }
    }

    private static func isIdentifier(_ value: String, maximum: Int) -> Bool {
        guard (1...maximum).contains(value.utf8.count) else { return false }
        return value.utf8.allSatisfy {
            (0x30...0x39).contains($0)
                || (0x41...0x5A).contains($0)
                || (0x61...0x7A).contains($0)
                || $0 == 0x2D || $0 == 0x2E || $0 == 0x5F
        }
    }
}
