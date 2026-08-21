import CompanionDomain
import Foundation

public enum DeviceNameDraftIssue: String, Codable, CaseIterable, Sendable {
    case empty
    case tooLong
    case surroundingWhitespace
    case nonCanonicalUnicode
    case unsupportedCharacters
}

public enum DeviceNameSaveFailure: String, Codable, CaseIterable, Sendable {
    case deviceRevoked
    case staleLocalState
    case serviceUnavailable
    case unknown
}

public enum DeviceNameEditorPhase: Equatable, Sendable {
    case viewing
    case editing
    case saving(requestID: UUID)
    case saveFailed(DeviceNameSaveFailure)
}

public struct DeviceNameSaveIntent: Equatable, Sendable {
    public let requestID: UUID
    public let deviceID: UUID
    public let displayName: DeviceDisplayName

    public init(
        requestID: UUID,
        deviceID: UUID,
        displayName: DeviceDisplayName
    ) {
        self.requestID = requestID
        self.deviceID = deviceID
        self.displayName = displayName
    }
}

public enum DeviceNameEditorError: Error, Equatable, Sendable {
    case invalidPhase
    case invalidDraft(DeviceNameDraftIssue)
    case staleResponse
    case responseMismatch
}

/// Presentation-only state for a local menu-app editor. The only initial name
/// is an optional value read from Agent-owned local persistence; there is no
/// remote suggestion, discovery label, or pairing-name input.
public struct DeviceNameAdministrationPresentation: Equatable, Sendable {
    public let deviceID: UUID
    public private(set) var confirmedName: DeviceDisplayName?
    public private(set) var draft: String
    public private(set) var phase: DeviceNameEditorPhase
    private var pendingName: DeviceDisplayName?

    public init(
        deviceID: UUID,
        locallyConfirmedName: DeviceDisplayName?
    ) {
        self.deviceID = deviceID
        confirmedName = locallyConfirmedName
        draft = locallyConfirmedName?.rawValue ?? ""
        phase = .viewing
        pendingName = nil
    }

    public mutating func beginEditing() throws {
        switch phase {
        case .viewing:
            draft = confirmedName?.rawValue ?? ""
        case .saveFailed:
            break
        default:
            throw DeviceNameEditorError.invalidPhase
        }
        phase = .editing
    }

    public mutating func updateDraft(_ value: String) throws {
        guard phase == .editing else {
            throw DeviceNameEditorError.invalidPhase
        }
        draft = value
    }

    public func draftIssue() -> DeviceNameDraftIssue? {
        do {
            _ = try DeviceDisplayName(draft)
            return nil
        } catch let error as DeviceDisplayNameError {
            return Self.map(error)
        } catch {
            return .unsupportedCharacters
        }
    }

    public mutating func submit(requestID: UUID) throws -> DeviceNameSaveIntent {
        guard phase == .editing else {
            throw DeviceNameEditorError.invalidPhase
        }
        let name: DeviceDisplayName
        do {
            name = try DeviceDisplayName(draft)
        } catch let error as DeviceDisplayNameError {
            throw DeviceNameEditorError.invalidDraft(Self.map(error))
        }
        pendingName = name
        phase = .saving(requestID: requestID)
        return DeviceNameSaveIntent(
            requestID: requestID,
            deviceID: deviceID,
            displayName: name
        )
    }

    public mutating func saveSucceeded(
        requestID: UUID,
        storedName: DeviceDisplayName
    ) throws {
        guard phase == .saving(requestID: requestID),
              let pendingName else {
            throw DeviceNameEditorError.staleResponse
        }
        guard storedName == pendingName else {
            throw DeviceNameEditorError.responseMismatch
        }
        confirmedName = storedName
        draft = storedName.rawValue
        self.pendingName = nil
        phase = .viewing
    }

    public mutating func saveFailed(
        requestID: UUID,
        reason: DeviceNameSaveFailure
    ) throws {
        guard phase == .saving(requestID: requestID) else {
            throw DeviceNameEditorError.staleResponse
        }
        pendingName = nil
        phase = .saveFailed(reason)
    }

    public mutating func cancelEditing() throws {
        switch phase {
        case .editing, .saveFailed:
            break
        default:
            throw DeviceNameEditorError.invalidPhase
        }
        draft = confirmedName?.rawValue ?? ""
        pendingName = nil
        phase = .viewing
    }

    private static func map(
        _ error: DeviceDisplayNameError
    ) -> DeviceNameDraftIssue {
        switch error {
        case .empty: .empty
        case .tooLong: .tooLong
        case .surroundingWhitespace: .surroundingWhitespace
        case .nonCanonicalUnicode: .nonCanonicalUnicode
        case .forbiddenScalar: .unsupportedCharacters
        }
    }
}
