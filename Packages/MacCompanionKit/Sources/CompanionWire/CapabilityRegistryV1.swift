import CompanionDomain
import Foundation

public enum CapabilityRegistryError: Error, Equatable, Sendable {
    case invalidDescriptor(field: String)
    case tooManyProviders
    case tooManyCapabilities
    case duplicateCapabilityID(String)
    case inconsistentProvider(String)
}

public struct CapabilityDescriptorV1: Equatable, Sendable {
    public let capabilityID: String
    public let schemaVersion: UInt32
    public let providerID: String
    public let providerVersion: String
    public let providerGeneration: UUID
    public let executionRevision: UUID
    public let englishTitle: String
    public let englishSummary: String
    public let parameterSchema: CapabilitySchemaV1
    public let resultSchema: CapabilitySchemaV1
    public let effects: CapabilityEffectFacts

    public init(
        capabilityID: String,
        schemaVersion: UInt32,
        providerID: String,
        providerVersion: String,
        providerGeneration: UUID,
        executionRevision: UUID,
        englishTitle: String,
        englishSummary: String,
        parameterSchema: CapabilitySchemaV1,
        resultSchema: CapabilitySchemaV1,
        effects: CapabilityEffectFacts
    ) throws {
        guard Self.isIdentifier(capabilityID, maximum: 96) else {
            throw CapabilityRegistryError.invalidDescriptor(field: "capabilityID")
        }
        guard schemaVersion >= 1 else {
            throw CapabilityRegistryError.invalidDescriptor(field: "schemaVersion")
        }
        guard Self.isIdentifier(providerID, maximum: 96) else {
            throw CapabilityRegistryError.invalidDescriptor(field: "providerID")
        }
        guard Self.isIdentifier(providerVersion, maximum: 64) else {
            throw CapabilityRegistryError.invalidDescriptor(field: "providerVersion")
        }
        guard Self.isPresentationText(englishTitle, maximum: 128) else {
            throw CapabilityRegistryError.invalidDescriptor(field: "englishTitle")
        }
        guard Self.isPresentationText(englishSummary, maximum: 512) else {
            throw CapabilityRegistryError.invalidDescriptor(field: "englishSummary")
        }
        guard parameterSchema.isObject else {
            throw CapabilityRegistryError.invalidDescriptor(field: "parameterSchema")
        }
        guard resultSchema.isObject else {
            throw CapabilityRegistryError.invalidDescriptor(field: "resultSchema")
        }
        self.capabilityID = capabilityID
        self.schemaVersion = schemaVersion
        self.providerID = providerID
        self.providerVersion = providerVersion
        self.providerGeneration = providerGeneration
        self.executionRevision = executionRevision
        self.englishTitle = englishTitle
        self.englishSummary = englishSummary
        self.parameterSchema = parameterSchema
        self.resultSchema = resultSchema
        self.effects = effects
    }

    static func isIdentifier(_ value: String, maximum: Int) -> Bool {
        guard (1...maximum).contains(value.utf8.count) else { return false }
        return value.utf8.allSatisfy {
            (0x30...0x39).contains($0)
                || (0x41...0x5A).contains($0)
                || (0x61...0x7A).contains($0)
                || $0 == 0x2D || $0 == 0x2E || $0 == 0x5F
        }
    }

    static func isPresentationText(
        _ value: String,
        maximum: Int
    ) -> Bool {
        guard !value.isEmpty, value.utf8.count <= maximum else { return false }
        return !value.unicodeScalars.contains {
            $0.value < 0x20 && $0.value != 0x09
        }
    }
}

public struct CapabilityRegistrySnapshotV1: Equatable, Sendable {
    public static let maximumProviderCount = 128
    public static let maximumCapabilityCount = 512

    public let generation: UUID
    public let capabilities: [CapabilityDescriptorV1]

    public init(
        generation: UUID,
        capabilities: [CapabilityDescriptorV1]
    ) throws {
        guard capabilities.count <= Self.maximumCapabilityCount else {
            throw CapabilityRegistryError.tooManyCapabilities
        }
        var capabilityIDs: Set<String> = []
        var providers: [String: ProviderIdentity] = [:]
        for capability in capabilities {
            guard capabilityIDs.insert(capability.capabilityID).inserted else {
                throw CapabilityRegistryError.duplicateCapabilityID(
                    capability.capabilityID
                )
            }
            let identity = ProviderIdentity(capability)
            if let existing = providers[capability.providerID],
               existing != identity {
                throw CapabilityRegistryError.inconsistentProvider(
                    capability.providerID
                )
            }
            providers[capability.providerID] = identity
        }
        guard providers.count <= Self.maximumProviderCount else {
            throw CapabilityRegistryError.tooManyProviders
        }
        self.generation = generation
        self.capabilities = capabilities.sorted {
            $0.capabilityID < $1.capabilityID
        }
    }

    public func capability(_ capabilityID: String) -> CapabilityDescriptorV1? {
        capabilities.first { $0.capabilityID == capabilityID }
    }

    private struct ProviderIdentity: Equatable {
        let version: String
        let generation: UUID
        let executionRevision: UUID

        init(_ capability: CapabilityDescriptorV1) {
            version = capability.providerVersion
            generation = capability.providerGeneration
            executionRevision = capability.executionRevision
        }
    }
}
