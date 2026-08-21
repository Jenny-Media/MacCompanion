import CompanionDomain
import CompanionPresentation

public struct MacEffectFactProjectionV0: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let requiresAttention: Bool

    public init(title: String, detail: String, requiresAttention: Bool) {
        self.title = title
        self.detail = detail
        self.requiresAttention = requiresAttention
    }
}

public struct MacGrantCapabilityProjectionV0: Equatable, Sendable {
    public let capabilityID: String
    public let title: String
    public let summary: String
    public let effects: [MacEffectFactProjectionV0]

    public init(item: LocalCapabilityGrantReviewItem) {
        capabilityID = item.capabilityID
        title = item.englishTitle
        summary = item.englishSummary
        effects = Self.project(item.effects)
    }

    private static func project(
        _ facts: LocalCapabilityEffectPresentation
    ) -> [MacEffectFactProjectionV0] {
        [
            .init(
                title: "Data access",
                detail: dataAccessDetail(facts.dataAccess),
                requiresAttention: facts.dataAccess != .none
            ),
            .init(
                title: "Changes this Mac",
                detail: localStateDetail(facts.changesLocalState),
                requiresAttention: facts.changesLocalState != .none
            ),
            booleanFact(
                title: "May disrupt your work",
                value: facts.mayDisruptUser
            ),
            booleanFact(
                title: "Uses an external service",
                value: facts.invokesExternalService
            ),
            booleanFact(
                title: "Uses credentials",
                value: facts.usesCredentials
            ),
            booleanFact(
                title: "Can be destructive",
                value: facts.destructive
            ),
            booleanFact(
                title: "Requires an unlocked session",
                value: facts.requiresForegroundSession
            ),
            booleanFact(
                title: "Allowed while this Mac is locked",
                value: facts.allowedWhileLocked
            ),
            .init(
                title: "Cancellation",
                detail: cancellationDetail(facts.cancellation),
                requiresAttention: facts.cancellation == .bestEffort
            ),
        ]
    }

    private static func booleanFact(
        title: String,
        value: Bool
    ) -> MacEffectFactProjectionV0 {
        .init(
            title: title,
            detail: value ? "Yes" : "No",
            requiresAttention: value
        )
    }

    private static func dataAccessDetail(
        _ value: CapabilityDataAccessEffect
    ) -> String {
        switch value {
        case .none: "No data access"
        case .publicData: "Public data"
        case .privateData: "Private data"
        case .credentials: "Credential data"
        }
    }

    private static func localStateDetail(
        _ value: CapabilityLocalStateEffect
    ) -> String {
        switch value {
        case .none: "Makes no local changes"
        case .reversible: "Makes reversible changes"
        case .irreversible: "May make irreversible changes"
        }
    }

    private static func cancellationDetail(
        _ value: CapabilityCancellationEffect
    ) -> String {
        switch value {
        case .notApplicable: "Not applicable"
        case .bestEffort: "Best effort after starting"
        }
    }
}

public enum MacGrantReviewStatusV0: Equatable, Sendable {
    case reviewing
    case applying
    case applied
    case declined
    case failed
}

public struct MacGrantReviewProjectionV0: Equatable, Sendable {
    public let deviceDisplayName: String
    public let currentGrantCount: Int
    public let proposedGrantCount: Int
    public let capabilities: [MacGrantCapabilityProjectionV0]
    public let status: MacGrantReviewStatusV0
    public let canApprove: Bool
    public let canDecline: Bool

    public init(presentation: LocalGrantExpansionPresentation) {
        deviceDisplayName = presentation.deviceDisplayName.rawValue
        currentGrantCount = presentation.currentGrants.capabilityIDs.count
        proposedGrantCount = presentation.proposedGrants.capabilityIDs.count
        capabilities = presentation.requestedCapabilities.map(
            MacGrantCapabilityProjectionV0.init
        )
        switch presentation.phase {
        case .reviewing:
            status = .reviewing
            canApprove = true
            canDecline = true
        case .applying:
            status = .applying
            canApprove = false
            canDecline = false
        case .applied:
            status = .applied
            canApprove = false
            canDecline = false
        case .declined:
            status = .declined
            canApprove = false
            canDecline = false
        case .failed:
            status = .failed
            canApprove = true
            canDecline = true
        }
    }
}

public struct MacInteractiveWarningProjectionV0: Equatable, Sendable {
    public let deviceDisplayName: String
    public let status: LocalInteractiveWarningPhase
    public let effectLabels: [String]
    public let hasActiveSession: Bool
    public let canStop: Bool

    public init(presentation: LocalInteractiveWarningPresentation) {
        deviceDisplayName = presentation.deviceDisplayName.rawValue
        status = presentation.phase
        effectLabels = presentation.effects.map(Self.effectLabel)
        hasActiveSession = presentation.interactiveSessionID != nil
        canStop = presentation.phase != .ending && presentation.phase != .ended
    }

    private static func effectLabel(
        _ effect: LocalInteractiveWarningEffect
    ) -> String {
        switch effect {
        case .viewMacScreen: "View this Mac’s screen"
        case .movePointer: "Move the pointer and click"
        case .pressKeyboardKeys: "Press keyboard keys"
        case .insertText: "Insert eligible text"
        }
    }
}

public struct MacDeviceNameProjectionV0: Equatable, Sendable {
    public let confirmedName: String?
    public let draft: String
    public let phase: DeviceNameEditorPhase
    public let issue: DeviceNameDraftIssue?
    public let isEditing: Bool
    public let canSave: Bool

    public init(presentation: DeviceNameAdministrationPresentation) {
        confirmedName = presentation.confirmedName?.rawValue
        draft = presentation.draft
        phase = presentation.phase
        issue = presentation.draftIssue()
        switch presentation.phase {
        case .editing, .saveFailed:
            isEditing = true
        case .viewing, .saving:
            isEditing = false
        }
        canSave = presentation.phase == .editing && issue == nil
    }
}
