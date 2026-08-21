import CompanionDomain
import Foundation

public enum CapabilityDataAccessWireV1: String, Codable, Sendable {
    case none, publicData, privateData, credentials
}

public enum CapabilityLocalStateWireV1: String, Codable, Sendable {
    case none, reversible, irreversible
}

public enum CapabilityCancellationWireV1: String, Codable, Sendable {
    case notApplicable, bestEffort
}

public struct CapabilityEffectFactsWireV1: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case dataAccess, changesLocalState, mayDisruptUser
        case invokesExternalService, usesCredentials, destructive
        case requiresForegroundSession, allowedWhileLocked, cancellation
    }

    public let dataAccess: CapabilityDataAccessWireV1
    public let changesLocalState: CapabilityLocalStateWireV1
    public let mayDisruptUser: Bool
    public let invokesExternalService: Bool
    public let usesCredentials: Bool
    public let destructive: Bool
    public let requiresForegroundSession: Bool
    public let allowedWhileLocked: Bool
    public let cancellation: CapabilityCancellationWireV1

    public init(_ facts: CapabilityEffectFacts) {
        dataAccess = switch facts.dataAccess {
        case .none: .none
        case .publicData: .publicData
        case .privateData: .privateData
        case .credentials: .credentials
        }
        changesLocalState = switch facts.changesLocalState {
        case .none: .none
        case .reversible: .reversible
        case .irreversible: .irreversible
        }
        mayDisruptUser = facts.mayDisruptUser
        invokesExternalService = facts.invokesExternalService
        usesCredentials = facts.usesCredentials
        destructive = facts.destructive
        requiresForegroundSession = facts.requiresForegroundSession
        allowedWhileLocked = facts.allowedWhileLocked
        cancellation = switch facts.cancellation {
        case .notApplicable: .notApplicable
        case .bestEffort: .bestEffort
        }
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            decoder,
            [
                "dataAccess", "changesLocalState", "mayDisruptUser",
                "invokesExternalService", "usesCredentials", "destructive",
                "requiresForegroundSession", "allowedWhileLocked", "cancellation",
            ]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dataAccess = try container.decode(
            CapabilityDataAccessWireV1.self,
            forKey: .dataAccess
        )
        changesLocalState = try container.decode(
            CapabilityLocalStateWireV1.self,
            forKey: .changesLocalState
        )
        mayDisruptUser = try container.decode(Bool.self, forKey: .mayDisruptUser)
        invokesExternalService = try container.decode(
            Bool.self,
            forKey: .invokesExternalService
        )
        usesCredentials = try container.decode(Bool.self, forKey: .usesCredentials)
        destructive = try container.decode(Bool.self, forKey: .destructive)
        requiresForegroundSession = try container.decode(
            Bool.self,
            forKey: .requiresForegroundSession
        )
        allowedWhileLocked = try container.decode(
            Bool.self,
            forKey: .allowedWhileLocked
        )
        cancellation = try container.decode(
            CapabilityCancellationWireV1.self,
            forKey: .cancellation
        )
        _ = try domainValue()
    }

    public func domainValue() throws -> CapabilityEffectFacts {
        let domainDataAccess: CapabilityDataAccessEffect = switch dataAccess {
        case .none: .none
        case .publicData: .publicData
        case .privateData: .privateData
        case .credentials: .credentials
        }
        let domainLocalState: CapabilityLocalStateEffect = switch changesLocalState {
        case .none: .none
        case .reversible: .reversible
        case .irreversible: .irreversible
        }
        let domainCancellation: CapabilityCancellationEffect = switch cancellation {
        case .notApplicable: .notApplicable
        case .bestEffort: .bestEffort
        }
        return try CapabilityEffectFacts(
            dataAccess: domainDataAccess,
            changesLocalState: domainLocalState,
            mayDisruptUser: mayDisruptUser,
            invokesExternalService: invokesExternalService,
            usesCredentials: usesCredentials,
            destructive: destructive,
            requiresForegroundSession: requiresForegroundSession,
            allowedWhileLocked: allowedWhileLocked,
            cancellation: domainCancellation
        )
    }
}

public struct CapabilityDiscoveryDescriptorV1: Codable, Equatable, Sendable {
    public static let maximumEncodedBytes = 12_000
    private enum CodingKeys: String, CodingKey {
        case capabilityID, schemaVersion, englishTitle, englishSummary
        case parameterSchema, resultSchema, effects
    }

    public let capabilityID: String
    public let schemaVersion: UInt32
    public let englishTitle: String
    public let englishSummary: String
    public let parameterSchema: CanonicalJSONValue
    public let resultSchema: CanonicalJSONValue
    public let effects: CapabilityEffectFactsWireV1

    public init(_ descriptor: CapabilityDescriptorV1) throws {
        capabilityID = descriptor.capabilityID
        schemaVersion = descriptor.schemaVersion
        englishTitle = descriptor.englishTitle
        englishSummary = descriptor.englishSummary
        parameterSchema = try descriptor.parameterSchema.wireValue()
        resultSchema = try descriptor.resultSchema.wireValue()
        effects = CapabilityEffectFactsWireV1(descriptor.effects)
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            decoder,
            [
                "capabilityID", "schemaVersion", "englishTitle", "englishSummary",
                "parameterSchema", "resultSchema", "effects",
            ]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        capabilityID = try container.decode(String.self, forKey: .capabilityID)
        schemaVersion = try container.decode(UInt32.self, forKey: .schemaVersion)
        englishTitle = try container.decode(String.self, forKey: .englishTitle)
        englishSummary = try container.decode(String.self, forKey: .englishSummary)
        parameterSchema = try container.decode(
            CanonicalJSONValue.self,
            forKey: .parameterSchema
        )
        resultSchema = try container.decode(
            CanonicalJSONValue.self,
            forKey: .resultSchema
        )
        effects = try container.decode(
            CapabilityEffectFactsWireV1.self,
            forKey: .effects
        )
        try validate()
    }

    public func validate() throws {
        guard CapabilityDescriptorV1.isIdentifier(capabilityID, maximum: 96),
              schemaVersion >= 1,
              CapabilityDescriptorV1.isPresentationText(
                englishTitle,
                maximum: 128
              ),
              CapabilityDescriptorV1.isPresentationText(
                englishSummary,
                maximum: 512
              ),
              try CapabilitySchemaV1(wireValue: parameterSchema).isObject,
              try CapabilitySchemaV1(wireValue: resultSchema).isObject else {
            throw WireError.invalidFrame(reason: "invalid capability descriptor")
        }
        _ = try effects.domainValue()
        let encoded = try JSONEncoder().encode(self)
        guard encoded.count <= Self.maximumEncodedBytes else {
            throw WireError.boundsExceeded(
                field: "capabilityDescriptor",
                limit: Self.maximumEncodedBytes
            )
        }
    }
}

public struct CapabilityRegistryRequestBody: WireBody {
    private enum CodingKeys: String, CodingKey {
        case expectedRegistryGeneration, expectedGrantRevision, afterCapabilityID
    }

    public static let kind = WireMessageKind.capabilityRegistryRequest
    public let expectedRegistryGeneration: WireUUID?
    public let expectedGrantRevision: Int64?
    public let afterCapabilityID: String?

    public init(
        expectedRegistryGeneration: WireUUID? = nil,
        expectedGrantRevision: Int64? = nil,
        afterCapabilityID: String? = nil
    ) throws {
        self.expectedRegistryGeneration = expectedRegistryGeneration
        self.expectedGrantRevision = expectedGrantRevision
        self.afterCapabilityID = afterCapabilityID
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            decoder,
            [
                "expectedRegistryGeneration", "expectedGrantRevision",
                "afterCapabilityID",
            ]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        expectedRegistryGeneration = try container.decodeIfPresent(
            WireUUID.self,
            forKey: .expectedRegistryGeneration
        )
        expectedGrantRevision = try container.decodeIfPresent(
            Int64.self,
            forKey: .expectedGrantRevision
        )
        afterCapabilityID = try container.decodeIfPresent(
            String.self,
            forKey: .afterCapabilityID
        )
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(
            expectedRegistryGeneration,
            forKey: .expectedRegistryGeneration
        )
        if expectedRegistryGeneration == nil {
            try container.encodeNil(forKey: .expectedRegistryGeneration)
        }
        try container.encodeIfPresent(
            expectedGrantRevision,
            forKey: .expectedGrantRevision
        )
        if expectedGrantRevision == nil {
            try container.encodeNil(forKey: .expectedGrantRevision)
        }
        try container.encodeIfPresent(afterCapabilityID, forKey: .afterCapabilityID)
        if afterCapabilityID == nil {
            try container.encodeNil(forKey: .afterCapabilityID)
        }
    }

    public func validate() throws {
        let valuesPresent = [
            expectedRegistryGeneration != nil,
            expectedGrantRevision != nil,
            afterCapabilityID != nil,
        ]
        guard valuesPresent.allSatisfy({ $0 })
                || valuesPresent.allSatisfy({ !$0 }) else {
            throw WireError.invalidFrame(reason: "partial capability cursor")
        }
        if let expectedGrantRevision {
            guard (1...WireLimits.maximumSafeInteger).contains(
                expectedGrantRevision
            ) else {
                throw WireError.invalidFrame(reason: "invalid grant revision")
            }
        }
        if let afterCapabilityID {
            guard CapabilityDescriptorV1.isIdentifier(
                afterCapabilityID,
                maximum: 96
            ) else {
                throw WireError.invalidFrame(reason: "invalid capability cursor")
            }
        }
    }
}

public struct CapabilityRegistryResponseBody: WireBody {
    public static let maximumPageSize = 4

    private enum CodingKeys: String, CodingKey {
        case registryGeneration, grantRevision, policyRevision
        case capabilities, nextAfterCapabilityID
    }

    public static let kind = WireMessageKind.capabilityRegistryResponse
    public let registryGeneration: WireUUID
    public let grantRevision: Int64
    public let policyRevision: Int64
    public let capabilities: [CapabilityDiscoveryDescriptorV1]
    public let nextAfterCapabilityID: String?

    public init(
        registryGeneration: WireUUID,
        grantRevision: Int64,
        policyRevision: Int64,
        capabilities: [CapabilityDiscoveryDescriptorV1],
        nextAfterCapabilityID: String?
    ) throws {
        self.registryGeneration = registryGeneration
        self.grantRevision = grantRevision
        self.policyRevision = policyRevision
        self.capabilities = capabilities
        self.nextAfterCapabilityID = nextAfterCapabilityID
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            decoder,
            [
                "registryGeneration", "grantRevision", "policyRevision",
                "capabilities", "nextAfterCapabilityID",
            ]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        registryGeneration = try container.decode(
            WireUUID.self,
            forKey: .registryGeneration
        )
        grantRevision = try container.decode(Int64.self, forKey: .grantRevision)
        policyRevision = try container.decode(Int64.self, forKey: .policyRevision)
        capabilities = try container.decode(
            [CapabilityDiscoveryDescriptorV1].self,
            forKey: .capabilities
        )
        nextAfterCapabilityID = try container.decodeIfPresent(
            String.self,
            forKey: .nextAfterCapabilityID
        )
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(registryGeneration, forKey: .registryGeneration)
        try container.encode(grantRevision, forKey: .grantRevision)
        try container.encode(policyRevision, forKey: .policyRevision)
        try container.encode(capabilities, forKey: .capabilities)
        try container.encodeIfPresent(
            nextAfterCapabilityID,
            forKey: .nextAfterCapabilityID
        )
        if nextAfterCapabilityID == nil {
            try container.encodeNil(forKey: .nextAfterCapabilityID)
        }
    }

    public func validate() throws {
        guard (1...WireLimits.maximumSafeInteger).contains(grantRevision),
              (1...WireLimits.maximumSafeInteger).contains(policyRevision),
              capabilities.count <= Self.maximumPageSize,
              capabilities.map(\.capabilityID)
                == capabilities.map(\.capabilityID).sorted(),
              Set(capabilities.map(\.capabilityID)).count == capabilities.count else {
            throw WireError.invalidFrame(reason: "invalid capability page")
        }
        try capabilities.forEach { try $0.validate() }
        if let nextAfterCapabilityID {
            guard nextAfterCapabilityID == capabilities.last?.capabilityID else {
                throw WireError.invalidFrame(reason: "invalid next capability cursor")
            }
        }
    }
}
