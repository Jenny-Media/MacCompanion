import CompanionDomain
import CompanionInteractiveShared
import Foundation

public enum LocalInteractiveInitialDesktopPreparationErrorV1:
    Error,
    Equatable,
    Sendable
{
    case invalidVersion
    case invalidRequest
    case bindingMismatch
}

/// Closed Agent-to-menu request for a display-derived Desktop descriptor.
/// The selected display remains an opaque menu-generation-scoped UUID.
public struct LocalInteractiveInitialDesktopPreparationCommandV1:
    Codable,
    Equatable,
    Sendable
{
    public let protocolVersion: LocalIPCProtocolVersion
    public let commandID: UUID
    public let interactiveSessionID: UUID
    public let authorizationEpoch: AuthorizationEpoch
    public let selectedDisplayID: UUID
    public let interactionClasses: [SurfaceInteractionClass]

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        commandID: UUID,
        interactiveSessionID: UUID,
        authorizationEpoch: AuthorizationEpoch,
        selectedDisplayID: UUID,
        interactionClasses: Set<SurfaceInteractionClass>
    ) throws {
        let classes = interactionClasses.sorted { $0.rawValue < $1.rawValue }
        guard protocolVersion == .init() else {
            throw LocalInteractiveInitialDesktopPreparationErrorV1
                .invalidVersion
        }
        guard authorizationEpoch.rawValue > 0,
              classes.contains(.view),
              !classes.contains(.text) || classes.contains(.keyboard) else {
            throw LocalInteractiveInitialDesktopPreparationErrorV1
                .invalidRequest
        }
        self.protocolVersion = protocolVersion
        self.commandID = commandID
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
        self.selectedDisplayID = selectedDisplayID
        self.interactionClasses = classes
    }

    private enum CodingKeys: String, CodingKey {
        case protocolVersion
        case commandID
        case interactiveSessionID
        case authorizationEpoch
        case selectedDisplayID
        case interactionClasses
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let classes = try container.decode(
            [SurfaceInteractionClass].self,
            forKey: .interactionClasses
        )
        guard classes == classes.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(classes).count == classes.count else {
            throw DecodingError.dataCorruptedError(
                forKey: .interactionClasses,
                in: container,
                debugDescription:
                    "interaction classes must be sorted and unique"
            )
        }
        do {
            try self.init(
                protocolVersion: container.decode(
                    LocalIPCProtocolVersion.self,
                    forKey: .protocolVersion
                ),
                commandID: container.decode(UUID.self, forKey: .commandID),
                interactiveSessionID: container.decode(
                    UUID.self,
                    forKey: .interactiveSessionID
                ),
                authorizationEpoch: container.decode(
                    AuthorizationEpoch.self,
                    forKey: .authorizationEpoch
                ),
                selectedDisplayID: container.decode(
                    UUID.self,
                    forKey: .selectedDisplayID
                ),
                interactionClasses: Set(classes)
            )
        } catch let error as DecodingError {
            throw error
        } catch {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription:
                        "invalid initial Desktop preparation command",
                    underlyingError: error
                )
            )
        }
    }
}

public struct LocalInteractiveInitialDesktopPreparedReceiptV1:
    Codable,
    Equatable,
    Sendable
{
    public let protocolVersion: LocalIPCProtocolVersion
    public let correlationID: UUID
    public let descriptor: AdaptiveSurfaceDescriptor

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        correlationID: UUID,
        descriptor: AdaptiveSurfaceDescriptor
    ) throws {
        guard protocolVersion == .init() else {
            throw LocalInteractiveInitialDesktopPreparationErrorV1
                .invalidVersion
        }
        do {
            try descriptor.validate()
        } catch {
            throw LocalInteractiveInitialDesktopPreparationErrorV1
                .bindingMismatch
        }
        guard descriptor.kind == .desktop else {
            throw LocalInteractiveInitialDesktopPreparationErrorV1
                .bindingMismatch
        }
        self.protocolVersion = protocolVersion
        self.correlationID = correlationID
        self.descriptor = descriptor
    }

    public func validate(
        against command: LocalInteractiveInitialDesktopPreparationCommandV1
    ) throws {
        guard protocolVersion == command.protocolVersion,
              correlationID == command.commandID,
              descriptor.interactiveSessionID
                == command.interactiveSessionID,
              descriptor.authorizationEpoch == command.authorizationEpoch,
              descriptor.kind == .desktop,
              descriptor.interactionClasses == command.interactionClasses else {
            throw LocalInteractiveInitialDesktopPreparationErrorV1
                .bindingMismatch
        }
    }

    private enum CodingKeys: String, CodingKey {
        case protocolVersion
        case correlationID
        case descriptor
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                protocolVersion: container.decode(
                    LocalIPCProtocolVersion.self,
                    forKey: .protocolVersion
                ),
                correlationID: container.decode(
                    UUID.self,
                    forKey: .correlationID
                ),
                descriptor: container.decode(
                    AdaptiveSurfaceDescriptor.self,
                    forKey: .descriptor
                )
            )
        } catch let error as DecodingError {
            throw error
        } catch {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription:
                        "invalid initial Desktop prepared receipt",
                    underlyingError: error
                )
            )
        }
    }
}
