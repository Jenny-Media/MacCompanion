import Foundation

public enum LocalInteractiveDisplaySelectionErrorV1:
    Error, Equatable, Sendable
{
    case invalidCommand
    case invalidReceipt
}

public struct LocalInteractiveDisplayCatalogCommandV1:
    Codable, Equatable, Sendable
{
    public let commandID: UUID

    public init(commandID: UUID) {
        self.commandID = commandID
    }
}

public struct LocalInteractiveDisplayCandidateV1:
    Codable, Equatable, Sendable
{
    public let displayID: UUID
    public let ordinal: UInt8
    public let pixelWidth: UInt16
    public let pixelHeight: UInt16
    public let isMain: Bool

    public init(
        displayID: UUID,
        ordinal: UInt8,
        pixelWidth: UInt16,
        pixelHeight: UInt16,
        isMain: Bool
    ) throws {
        guard ordinal >= 1, pixelWidth >= 1, pixelHeight >= 1 else {
            throw LocalInteractiveDisplaySelectionErrorV1.invalidReceipt
        }
        self.displayID = displayID
        self.ordinal = ordinal
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.isMain = isMain
    }
}

public struct LocalInteractiveDisplayCatalogReceiptV1:
    Codable, Equatable, Sendable
{
    public static let maximumCandidates = 16

    public let correlationID: UUID
    public let selectedDisplayID: UUID
    public let candidates: [LocalInteractiveDisplayCandidateV1]

    public init(
        correlationID: UUID,
        selectedDisplayID: UUID,
        candidates: [LocalInteractiveDisplayCandidateV1]
    ) throws {
        guard !candidates.isEmpty,
              candidates.count <= Self.maximumCandidates,
              Set(candidates.map(\.displayID)).count == candidates.count,
              Set(candidates.map(\.ordinal)).count == candidates.count,
              candidates.contains(where: {
                  $0.displayID == selectedDisplayID
              }),
              candidates.filter(\.isMain).count <= 1 else {
            throw LocalInteractiveDisplaySelectionErrorV1.invalidReceipt
        }
        self.correlationID = correlationID
        self.selectedDisplayID = selectedDisplayID
        self.candidates = candidates
    }

    public func validate(
        against command: LocalInteractiveDisplayCatalogCommandV1
    ) throws {
        guard correlationID == command.commandID else {
            throw LocalInteractiveDisplaySelectionErrorV1.invalidReceipt
        }
        _ = try Self(
            correlationID: correlationID,
            selectedDisplayID: selectedDisplayID,
            candidates: candidates
        )
    }
}

public struct LocalInteractiveDisplaySelectCommandV1:
    Codable, Equatable, Sendable
{
    public let commandID: UUID
    public let displayID: UUID

    public init(commandID: UUID, displayID: UUID) {
        self.commandID = commandID
        self.displayID = displayID
    }
}

public struct LocalInteractiveDisplaySelectedReceiptV1:
    Codable, Equatable, Sendable
{
    public let correlationID: UUID
    public let selectedDisplayID: UUID

    public init(correlationID: UUID, selectedDisplayID: UUID) {
        self.correlationID = correlationID
        self.selectedDisplayID = selectedDisplayID
    }

    public func validate(
        against command: LocalInteractiveDisplaySelectCommandV1
    ) throws {
        guard correlationID == command.commandID,
              selectedDisplayID == command.displayID else {
            throw LocalInteractiveDisplaySelectionErrorV1.invalidReceipt
        }
    }
}
