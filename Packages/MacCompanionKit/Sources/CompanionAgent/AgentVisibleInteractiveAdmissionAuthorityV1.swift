import CompanionInteractiveHost
import CompanionIPC
import Foundation

public enum AgentVisibleInteractiveAdmissionAuthorityErrorV1:
    Error,
    Equatable,
    Sendable
{
    case unavailable
    case invalidTransportGeneration
    case invalidInitialRevision
    case staleOrSkippedRevision
    case menuGenerationChanged
    case terminal
}

/// Stable Agent-side owner of the replaceable visible-menu admission. Durable
/// grants remain in SQLite; this actor owns only the authenticated transport
/// generation, opaque menu generation/revision, and optional opaque display
/// token joined by `SQLiteInteractiveSessionAdmissionReaderV0`.
public actor AgentVisibleInteractiveAdmissionAuthorityV1:
    VisibleInteractiveAdmissionReadingV0
{
    private struct Current: Sendable {
        let transportGeneration: UInt64
        var publication: LocalInteractiveAdmissionPublicationV1
        var receipt: LocalInteractiveAdmissionPublishedReceiptV1
    }

    private var current: Current?
    private var highestTransportGeneration: UInt64 = 0
    private var terminal = false

    public init() {}

    public func publish(
        _ publication: LocalInteractiveAdmissionPublicationV1,
        transportGeneration: UInt64
    ) throws -> LocalInteractiveAdmissionPublishedReceiptV1 {
        guard !terminal else {
            throw AgentVisibleInteractiveAdmissionAuthorityErrorV1.terminal
        }
        guard transportGeneration > 0 else {
            throw AgentVisibleInteractiveAdmissionAuthorityErrorV1
                .invalidTransportGeneration
        }

        if var current {
            guard current.transportGeneration == transportGeneration else {
                throw AgentVisibleInteractiveAdmissionAuthorityErrorV1
                    .invalidTransportGeneration
            }
            if current.publication == publication {
                return current.receipt
            }
            guard publication.menuAppGeneration
                    == current.publication.menuAppGeneration else {
                throw AgentVisibleInteractiveAdmissionAuthorityErrorV1
                    .menuGenerationChanged
            }
            guard current.publication.revision < UInt64.max,
                  publication.revision
                    == current.publication.revision + 1 else {
                throw AgentVisibleInteractiveAdmissionAuthorityErrorV1
                    .staleOrSkippedRevision
            }
            let receipt = try receipt(for: publication)
            current.publication = publication
            current.receipt = receipt
            self.current = current
            return receipt
        }

        guard transportGeneration > highestTransportGeneration else {
            throw AgentVisibleInteractiveAdmissionAuthorityErrorV1
                .invalidTransportGeneration
        }
        guard publication.revision == 1 else {
            throw AgentVisibleInteractiveAdmissionAuthorityErrorV1
                .invalidInitialRevision
        }
        let receipt = try receipt(for: publication)
        highestTransportGeneration = transportGeneration
        current = Current(
            transportGeneration: transportGeneration,
            publication: publication,
            receipt: receipt
        )
        return receipt
    }

    @discardableResult
    public func invalidate(transportGeneration: UInt64) -> Bool {
        guard current?.transportGeneration == transportGeneration else {
            return false
        }
        current = nil
        return true
    }

    public func finish() {
        terminal = true
        current = nil
    }

    public func snapshot() async throws
        -> VisibleInteractiveAdmissionStateV0 {
        guard !terminal, let publication = current?.publication else {
            throw AgentVisibleInteractiveAdmissionAuthorityErrorV1.unavailable
        }
        return VisibleInteractiveAdmissionStateV0(
            generation: publication.menuAppGeneration,
            revision: publication.revision,
            visibleMenuAppAvailable: true,
            selectedDisplayID: publication.selectedDisplayID
        )
    }

    private func receipt(
        for publication: LocalInteractiveAdmissionPublicationV1
    ) throws -> LocalInteractiveAdmissionPublishedReceiptV1 {
        try LocalInteractiveAdmissionPublishedReceiptV1(
            correlationID: publication.commandID,
            menuAppGeneration: publication.menuAppGeneration,
            revision: publication.revision,
            selectedDisplayID: publication.selectedDisplayID
        )
    }
}
