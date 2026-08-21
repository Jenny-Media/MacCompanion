import CompanionDomain
import CompanionWire
import Foundation

public enum CapabilityCatalogAssemblyStateV1: String, Equatable, Sendable {
    case idle
    case loading
    case complete
    case invalidated
}

public enum CapabilityCatalogAssemblyErrorV1: Error, Equatable, Sendable {
    case invalidState(CapabilityCatalogAssemblyStateV1)
    case fenceChanged
    case unexpectedCursor
    case invalidOrder
    case tooManyCapabilities
}

public struct GrantedCapabilityCatalogV1: Equatable, Sendable {
    public let registryGeneration: WireUUID
    public let grantRevision: Int64
    public let policyRevision: Int64
    public let capabilities: [CapabilityDiscoveryDescriptorV1]

    public init(
        registryGeneration: WireUUID,
        grantRevision: Int64,
        policyRevision: Int64,
        capabilities: [CapabilityDiscoveryDescriptorV1]
    ) {
        self.registryGeneration = registryGeneration
        self.grantRevision = grantRevision
        self.policyRevision = policyRevision
        self.capabilities = capabilities
    }

    public func capability(
        _ capabilityID: String
    ) -> CapabilityDiscoveryDescriptorV1? {
        capabilities.first { $0.capabilityID == capabilityID }
    }
}

/// Builds one catalog from a single registry/grant/policy fence. Any mismatch
/// invalidates the partial result; callers must discard it and begin again.
public struct CapabilityCatalogAssemblerV1: Sendable {
    public static let maximumCapabilityCount = CapabilityGrantSet.maximumCount

    public private(set) var state: CapabilityCatalogAssemblyStateV1 = .idle
    public private(set) var catalog: GrantedCapabilityCatalogV1?

    private var generation: WireUUID?
    private var grantRevision: Int64?
    private var policyRevision: Int64?
    private var expectedAfterCapabilityID: String?
    private var capabilities: [CapabilityDiscoveryDescriptorV1] = []

    public init() {}

    public mutating func begin() throws -> CapabilityRegistryRequestBody {
        guard state == .idle || state == .invalidated else {
            throw CapabilityCatalogAssemblyErrorV1.invalidState(state)
        }
        generation = nil
        grantRevision = nil
        policyRevision = nil
        expectedAfterCapabilityID = nil
        capabilities = []
        catalog = nil
        state = .loading
        return try CapabilityRegistryRequestBody()
    }

    /// Accepts one validated page and returns the exact continuation request,
    /// or nil after atomically publishing the complete catalog.
    public mutating func accept(
        _ page: CapabilityRegistryResponseBody
    ) throws -> CapabilityRegistryRequestBody? {
        guard state == .loading else {
            throw CapabilityCatalogAssemblyErrorV1.invalidState(state)
        }
        do {
            if let generation {
                guard page.registryGeneration == generation,
                      page.grantRevision == grantRevision,
                      page.policyRevision == policyRevision else {
                    throw CapabilityCatalogAssemblyErrorV1.fenceChanged
                }
            } else {
                generation = page.registryGeneration
                grantRevision = page.grantRevision
                policyRevision = page.policyRevision
            }

            if expectedAfterCapabilityID != nil {
                guard let first = page.capabilities.first?.capabilityID,
                      let expectedAfterCapabilityID,
                      first > expectedAfterCapabilityID else {
                    throw CapabilityCatalogAssemblyErrorV1.unexpectedCursor
                }
            }
            if let last = capabilities.last?.capabilityID,
               page.capabilities.contains(where: { $0.capabilityID <= last }) {
                throw CapabilityCatalogAssemblyErrorV1.invalidOrder
            }
            guard capabilities.count + page.capabilities.count
                    <= Self.maximumCapabilityCount else {
                throw CapabilityCatalogAssemblyErrorV1.tooManyCapabilities
            }
            capabilities.append(contentsOf: page.capabilities)

            if let next = page.nextAfterCapabilityID {
                expectedAfterCapabilityID = next
                return try CapabilityRegistryRequestBody(
                    expectedRegistryGeneration: page.registryGeneration,
                    expectedGrantRevision: page.grantRevision,
                    afterCapabilityID: next
                )
            }

            guard let generation, let grantRevision, let policyRevision else {
                throw CapabilityCatalogAssemblyErrorV1.fenceChanged
            }
            catalog = GrantedCapabilityCatalogV1(
                registryGeneration: generation,
                grantRevision: grantRevision,
                policyRevision: policyRevision,
                capabilities: capabilities
            )
            state = .complete
            return nil
        } catch {
            invalidate()
            throw error
        }
    }

    public mutating func invalidate() {
        generation = nil
        grantRevision = nil
        policyRevision = nil
        expectedAfterCapabilityID = nil
        capabilities = []
        catalog = nil
        state = .invalidated
    }
}
