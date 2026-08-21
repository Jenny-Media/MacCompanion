import CompanionAuthentication
import CompanionPersistence
import CompanionWire
import Foundation

public enum CapabilityDiscoveryErrorV1: Error, Equatable, Sendable {
    case invalidCursor
    case registryChanged
    case authorizationChanged
}

/// Produces a privacy-limited view containing only capabilities that are both
/// installed in the current host registry and durably granted to this device.
public actor CapabilityDiscoveryAuthorityV1 {
    private let store: SQLiteSecurityStore
    private let registryReader: any CapabilityRegistrySnapshotReadingV1

    public init(
        store: SQLiteSecurityStore,
        registry: CapabilityRegistrySnapshotV1
    ) {
        self.store = store
        registryReader = FixedCapabilityRegistrySnapshotReaderV1(registry)
    }

    public init(
        store: SQLiteSecurityStore,
        registryReader: any CapabilityRegistrySnapshotReadingV1
    ) {
        self.store = store
        self.registryReader = registryReader
    }

    public func page(
        _ request: CapabilityRegistryRequestBody,
        principal: AuthenticatedDevicePrincipal
    ) async throws -> CapabilityRegistryResponseBody {
        let registry = await registryReader.registrySnapshot()
        let snapshot = try await store.deviceGrantSnapshot(principal.deviceID)
        let device = snapshot.device
        guard device.clientID == principal.clientID,
              device.authorization.state.canAuthenticate,
              device.authorization.state == principal.deviceState,
              device.authorization.authorizationEpoch == principal.authorizationEpoch,
              device.authorization.grantRevision == principal.grantRevision,
              device.policyRevision == principal.policyRevision else {
            throw CapabilityDiscoveryErrorV1.authorizationChanged
        }

        if let expectedGeneration = request.expectedRegistryGeneration,
           expectedGeneration.rawValue != registry.generation {
            throw CapabilityDiscoveryErrorV1.registryChanged
        }
        if let expectedGrantRevision = request.expectedGrantRevision,
           UInt64(expectedGrantRevision) != principal.grantRevision.rawValue {
            throw CapabilityDiscoveryErrorV1.registryChanged
        }

        let granted = Set(snapshot.grants.capabilityIDs)
        let visible = registry.capabilities.filter {
            granted.contains($0.capabilityID)
        }
        let start: Int
        if let after = request.afterCapabilityID {
            guard let index = visible.firstIndex(where: {
                $0.capabilityID == after
            }) else {
                throw CapabilityDiscoveryErrorV1.invalidCursor
            }
            start = visible.index(after: index)
        } else {
            start = visible.startIndex
        }
        let remaining = visible[start...]
        let page = Array(remaining.prefix(
            CapabilityRegistryResponseBody.maximumPageSize
        ))
        let hasMore = remaining.count > page.count
        let descriptors = try page.map(CapabilityDiscoveryDescriptorV1.init)
        return try CapabilityRegistryResponseBody(
            registryGeneration: WireUUID(registry.generation),
            grantRevision: Int64(principal.grantRevision.rawValue),
            policyRevision: Int64(principal.policyRevision.rawValue),
            capabilities: descriptors,
            nextAfterCapabilityID: hasMore ? descriptors.last?.capabilityID : nil
        )
    }
}

public actor CapabilityRegistryWireDispatcherV1 {
    private let authority: CapabilityDiscoveryAuthorityV1

    public init(authority: CapabilityDiscoveryAuthorityV1) {
        self.authority = authority
    }

    public func dispatch(
        requestJSON: Data,
        principal: AuthenticatedDevicePrincipal,
        responseMessageID: WireUUID,
        sentAtUnixMilliseconds: Int64
    ) async throws -> Data {
        let request = try WireCodec.decode(
            WireEnvelope<CapabilityRegistryRequestBody>.self,
            from: requestJSON
        )
        do {
            let page = try await authority.page(request.body, principal: principal)
            return try WireCodec.encode(WireEnvelope(
                messageID: responseMessageID,
                correlationID: request.messageID,
                sentAtUnixMilliseconds: sentAtUnixMilliseconds,
                body: page
            ))
        } catch CapabilityDiscoveryErrorV1.registryChanged {
            return try error(
                code: "capability.registryChanged",
                retry: .afterReconnect,
                request: request,
                responseMessageID: responseMessageID,
                sentAtUnixMilliseconds: sentAtUnixMilliseconds
            )
        } catch CapabilityDiscoveryErrorV1.invalidCursor {
            return try error(
                code: "protocol.invalidFrame",
                retry: .never,
                reasonCode: "invalidBody",
                request: request,
                responseMessageID: responseMessageID,
                sentAtUnixMilliseconds: sentAtUnixMilliseconds
            )
        }
    }

    private func error(
        code: String,
        retry: ProtocolErrorRetry,
        reasonCode: String? = nil,
        request: WireEnvelope<CapabilityRegistryRequestBody>,
        responseMessageID: WireUUID,
        sentAtUnixMilliseconds: Int64
    ) throws -> Data {
        let arguments: CanonicalJSONValue = reasonCode.map {
            .object([.init(key: "reasonCode", value: .string($0))])
        } ?? .object([])
        return try WireCodec.encode(WireEnvelope(
            messageID: responseMessageID,
            correlationID: request.messageID,
            sentAtUnixMilliseconds: sentAtUnixMilliseconds,
            body: ProtocolErrorResponseBody(
                code: code,
                retry: retry,
                safeArguments: arguments
            )
        ))
    }
}
