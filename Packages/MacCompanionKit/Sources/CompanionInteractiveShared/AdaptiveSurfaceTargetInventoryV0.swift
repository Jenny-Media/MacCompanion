import CompanionDomain
import Foundation

public enum AdaptiveSurfaceTargetInventoryErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidConfiguration
    case invalidObservation
    case capacityExceeded
    case revisionExhausted
    case tokenCollision
    case unavailable
    case staleInventory
    case kindMismatch
}

public enum AdaptiveSurfaceTargetObservationKindV0: Sendable {
    case application
    case window
}

/// Sanitized menu-local facts. `sourceReference` values never cross IPC or the
/// network and may index ScreenCaptureKit objects only inside the menu app.
public struct AdaptiveSurfaceTargetObservationV0: Equatable, Sendable {
    public let sourceReference: UUID
    public let kind: AdaptiveSurfaceTargetObservationKindV0
    public let applicationSourceReference: UUID
    public let applicationName: String
    public let currentWindowAvailable: Bool
    /// Menu-local ordering input only. It is never copied into a candidate.
    public let localSortOrder: UInt64

    public init(
        sourceReference: UUID,
        kind: AdaptiveSurfaceTargetObservationKindV0,
        applicationSourceReference: UUID,
        applicationName: String,
        currentWindowAvailable: Bool,
        localSortOrder: UInt64 = 0
    ) throws {
        self.sourceReference = sourceReference
        self.kind = kind
        self.applicationSourceReference = applicationSourceReference
        self.applicationName = applicationName
        self.currentWindowAvailable = currentWindowAvailable
        self.localSortOrder = localSortOrder
        try Self.validateName(applicationName)
        if kind == .application {
            guard sourceReference == applicationSourceReference else {
                throw AdaptiveSurfaceTargetInventoryErrorV0.invalidObservation
            }
        } else {
            guard sourceReference != applicationSourceReference else {
                throw AdaptiveSurfaceTargetInventoryErrorV0.invalidObservation
            }
        }
    }

    static func validateName(_ value: String) throws {
        guard !value.isEmpty,
              value.utf8.count <= 128,
              value.unicodeScalars.allSatisfy({ scalar in
                  scalar.value >= 0x20
                      && scalar.value != 0x7f
                      && scalar.value != 0x2028
                      && scalar.value != 0x2029
              }) else {
            throw AdaptiveSurfaceTargetInventoryErrorV0.invalidObservation
        }
    }
}

public struct AdaptiveSurfaceTargetCandidateV0: Equatable, Sendable {
    public let targetToken: UUID
    public let kind: InteractiveSurfaceKind
    public let applicationToken: UUID
    public let applicationName: String
    public let windowOrdinal: UInt8?
    public let currentWindowAvailable: Bool

    public init(
        targetToken: UUID,
        kind: InteractiveSurfaceKind,
        applicationToken: UUID,
        applicationName: String,
        windowOrdinal: UInt8?,
        currentWindowAvailable: Bool
    ) throws {
        self.targetToken = targetToken
        self.kind = kind
        self.applicationToken = applicationToken
        self.applicationName = applicationName
        self.windowOrdinal = windowOrdinal
        self.currentWindowAvailable = currentWindowAvailable
        try AdaptiveSurfaceTargetObservationV0.validateName(applicationName)
        switch kind {
        case .application:
            guard targetToken == applicationToken,
                  windowOrdinal == nil else {
                throw AdaptiveSurfaceTargetInventoryErrorV0.invalidObservation
            }
        case .window:
            guard targetToken != applicationToken,
                  let windowOrdinal,
                  (1...64).contains(windowOrdinal) else {
                throw AdaptiveSurfaceTargetInventoryErrorV0.invalidObservation
            }
        case .desktop, .focusedRegion:
            throw AdaptiveSurfaceTargetInventoryErrorV0.invalidObservation
        }
    }
}

public struct AdaptiveSurfaceTargetInventorySnapshotV0:
    Equatable,
    Sendable
{
    public let interactiveSessionID: UUID
    public let authorizationEpoch: AuthorizationEpoch
    public let revision: UInt64
    public let createdAtMonotonicMilliseconds: Int64
    public let expiresAtMonotonicMilliseconds: Int64
    public let candidates: [AdaptiveSurfaceTargetCandidateV0]

    public init(
        interactiveSessionID: UUID,
        authorizationEpoch: AuthorizationEpoch,
        revision: UInt64,
        createdAtMonotonicMilliseconds: Int64,
        expiresAtMonotonicMilliseconds: Int64,
        candidates: [AdaptiveSurfaceTargetCandidateV0]
    ) throws {
        guard authorizationEpoch.rawValue >= 1,
              revision >= 1,
              revision <= WireSafeInteger.maximum,
              createdAtMonotonicMilliseconds >= 0,
              expiresAtMonotonicMilliseconds
                > createdAtMonotonicMilliseconds,
              expiresAtMonotonicMilliseconds
                - createdAtMonotonicMilliseconds
                    <= AdaptiveSurfaceTargetInventoryV0
                        .maximumLifetimeMilliseconds,
              candidates.count
                <= AdaptiveSurfaceTargetInventoryV0.maximumCandidates else {
            throw AdaptiveSurfaceTargetInventoryErrorV0.invalidConfiguration
        }
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
        self.revision = revision
        self.createdAtMonotonicMilliseconds =
            createdAtMonotonicMilliseconds
        self.expiresAtMonotonicMilliseconds =
            expiresAtMonotonicMilliseconds
        self.candidates = candidates
    }
}

public struct AdaptiveSurfaceTargetResolutionV0: Equatable, Sendable {
    public let candidate: AdaptiveSurfaceTargetCandidateV0
    public let sourceReference: UUID
    public let applicationSourceReference: UUID
}

/// Single-session, replace-all inventory. Refresh regenerates every remote
/// token. Selection consumes the complete inventory so a second selection
/// requires a fresh privacy-limited snapshot.
public struct AdaptiveSurfaceTargetInventoryV0: Sendable {
    public static let maximumApplications = 64
    public static let maximumWindowsPerApplication = 64
    public static let maximumCandidates = 192
    public static let maximumLifetimeMilliseconds: Int64 = 10_000

    private struct Entry: Sendable {
        let candidate: AdaptiveSurfaceTargetCandidateV0
        let sourceReference: UUID
        let applicationSourceReference: UUID
    }

    public let interactiveSessionID: UUID
    public let authorizationEpoch: AuthorizationEpoch
    private let tokenGenerator: @Sendable () -> UUID
    private var revision: UInt64 = 0
    private var snapshotStorage: AdaptiveSurfaceTargetInventorySnapshotV0?
    private var entries: [UUID: Entry] = [:]

    public init(
        interactiveSessionID: UUID,
        authorizationEpoch: AuthorizationEpoch,
        tokenGenerator: @escaping @Sendable () -> UUID = { UUID() }
    ) throws {
        guard authorizationEpoch.rawValue >= 1 else {
            throw AdaptiveSurfaceTargetInventoryErrorV0.invalidConfiguration
        }
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
        self.tokenGenerator = tokenGenerator
    }

    @discardableResult
    public mutating func replace(
        observations: [AdaptiveSurfaceTargetObservationV0],
        nowMonotonicMilliseconds: Int64,
        lifetimeMilliseconds: Int64 = maximumLifetimeMilliseconds
    ) throws -> AdaptiveSurfaceTargetInventorySnapshotV0 {
        guard nowMonotonicMilliseconds >= 0,
              (1...Self.maximumLifetimeMilliseconds)
                .contains(lifetimeMilliseconds),
              nowMonotonicMilliseconds
                <= Int64.max - lifetimeMilliseconds else {
            throw AdaptiveSurfaceTargetInventoryErrorV0.invalidConfiguration
        }
        guard revision < UInt64(WireSafeInteger.maximum) else {
            throw AdaptiveSurfaceTargetInventoryErrorV0.revisionExhausted
        }
        guard Set(observations.map(\.sourceReference)).count
                == observations.count else {
            throw AdaptiveSurfaceTargetInventoryErrorV0.invalidObservation
        }

        let applications = observations.filter { $0.kind == .application }
        guard applications.count <= Self.maximumApplications else {
            throw AdaptiveSurfaceTargetInventoryErrorV0.capacityExceeded
        }
        let applicationReferences = Set(applications.map(\.sourceReference))
        let windows = observations.filter { $0.kind == .window }
        guard windows.allSatisfy({
            applicationReferences.contains($0.applicationSourceReference)
        }) else {
            throw AdaptiveSurfaceTargetInventoryErrorV0.invalidObservation
        }

        var newEntries: [UUID: Entry] = [:]
        var candidates: [AdaptiveSurfaceTargetCandidateV0] = []
        for application in applications.sorted(by: Self.precedes) {
            let token = tokenGenerator()
            guard newEntries[token] == nil else {
                throw AdaptiveSurfaceTargetInventoryErrorV0.tokenCollision
            }
            let candidate = try AdaptiveSurfaceTargetCandidateV0(
                targetToken: token,
                kind: .application,
                applicationToken: token,
                applicationName: application.applicationName,
                windowOrdinal: nil,
                currentWindowAvailable:
                    application.currentWindowAvailable
            )
            newEntries[token] = Entry(
                candidate: candidate,
                sourceReference: application.sourceReference,
                applicationSourceReference:
                    application.applicationSourceReference
            )
            candidates.append(candidate)

            let ownedWindows = windows.filter {
                $0.applicationSourceReference == application.sourceReference
            }.sorted(by: Self.precedes)
            guard ownedWindows.count <= Self.maximumWindowsPerApplication else {
                throw AdaptiveSurfaceTargetInventoryErrorV0.capacityExceeded
            }
            for (offset, window) in ownedWindows.enumerated() {
                let windowToken = tokenGenerator()
                guard newEntries[windowToken] == nil else {
                    throw AdaptiveSurfaceTargetInventoryErrorV0.tokenCollision
                }
                let candidate = try AdaptiveSurfaceTargetCandidateV0(
                    targetToken: windowToken,
                    kind: .window,
                    applicationToken: token,
                    applicationName: application.applicationName,
                    windowOrdinal: UInt8(offset + 1),
                    currentWindowAvailable:
                        window.currentWindowAvailable
                )
                newEntries[windowToken] = Entry(
                    candidate: candidate,
                    sourceReference: window.sourceReference,
                    applicationSourceReference:
                        window.applicationSourceReference
                )
                candidates.append(candidate)
            }
        }
        guard candidates.count <= Self.maximumCandidates else {
            throw AdaptiveSurfaceTargetInventoryErrorV0.capacityExceeded
        }
        candidates.sort(by: Self.candidatePrecedes)
        revision += 1
        let snapshot = try AdaptiveSurfaceTargetInventorySnapshotV0(
            interactiveSessionID: interactiveSessionID,
            authorizationEpoch: authorizationEpoch,
            revision: revision,
            createdAtMonotonicMilliseconds: nowMonotonicMilliseconds,
            expiresAtMonotonicMilliseconds:
                nowMonotonicMilliseconds + lifetimeMilliseconds,
            candidates: candidates
        )
        entries = newEntries
        snapshotStorage = snapshot
        return snapshot
    }

    public func snapshot(
        nowMonotonicMilliseconds: Int64
    ) throws -> AdaptiveSurfaceTargetInventorySnapshotV0 {
        guard let snapshotStorage,
              nowMonotonicMilliseconds
                >= snapshotStorage.createdAtMonotonicMilliseconds,
              nowMonotonicMilliseconds
                < snapshotStorage.expiresAtMonotonicMilliseconds else {
            throw AdaptiveSurfaceTargetInventoryErrorV0.staleInventory
        }
        return snapshotStorage
    }

    public mutating func consume(
        targetToken: UUID,
        expectedKind: InteractiveSurfaceKind,
        nowMonotonicMilliseconds: Int64
    ) throws -> AdaptiveSurfaceTargetResolutionV0 {
        _ = try snapshot(nowMonotonicMilliseconds: nowMonotonicMilliseconds)
        guard let entry = entries[targetToken] else {
            throw AdaptiveSurfaceTargetInventoryErrorV0.unavailable
        }
        guard entry.candidate.currentWindowAvailable else {
            throw AdaptiveSurfaceTargetInventoryErrorV0.unavailable
        }
        guard entry.candidate.kind == expectedKind else {
            throw AdaptiveSurfaceTargetInventoryErrorV0.kindMismatch
        }
        let resolution = AdaptiveSurfaceTargetResolutionV0(
            candidate: entry.candidate,
            sourceReference: entry.sourceReference,
            applicationSourceReference: entry.applicationSourceReference
        )
        invalidate()
        return resolution
    }

    public mutating func invalidate() {
        entries.removeAll(keepingCapacity: false)
        snapshotStorage = nil
    }

    private static func precedes(
        _ lhs: AdaptiveSurfaceTargetObservationV0,
        _ rhs: AdaptiveSurfaceTargetObservationV0
    ) -> Bool {
        let leftName = lhs.applicationName.unicodeScalars.map(\.value)
        let rightName = rhs.applicationName.unicodeScalars.map(\.value)
        if leftName != rightName {
            return leftName.lexicographicallyPrecedes(rightName)
        }
        if lhs.localSortOrder != rhs.localSortOrder {
            return lhs.localSortOrder < rhs.localSortOrder
        }
        return lhs.sourceReference.uuidString.lowercased()
            < rhs.sourceReference.uuidString.lowercased()
    }

    private static func candidatePrecedes(
        _ lhs: AdaptiveSurfaceTargetCandidateV0,
        _ rhs: AdaptiveSurfaceTargetCandidateV0
    ) -> Bool {
        let leftName = lhs.applicationName.unicodeScalars.map(\.value)
        let rightName = rhs.applicationName.unicodeScalars.map(\.value)
        if leftName != rightName {
            return leftName.lexicographicallyPrecedes(rightName)
        }
        if lhs.kind != rhs.kind { return lhs.kind == .application }
        if lhs.windowOrdinal != rhs.windowOrdinal {
            return (lhs.windowOrdinal ?? 0) < (rhs.windowOrdinal ?? 0)
        }
        return lhs.targetToken.uuidString.lowercased()
            < rhs.targetToken.uuidString.lowercased()
    }
}

private enum WireSafeInteger {
    static let maximum: UInt64 = 9_007_199_254_740_991
}
