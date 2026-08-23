import CompanionWire
import Foundation

public enum Stage3StudyCohortPhaseV1: String, CaseIterable, Hashable, Sendable {
    case dogfood
    case calibration
    case confirmatory
}

public enum Stage3StudyAttemptResultV1: String, CaseIterable, Hashable, Sendable {
    case notAttempted
    case unsupported
    case denied
    case failed
    case notCompleted
    case outcomeUnknown
    case completed
}

public enum Stage3StudyPathV1: String, CaseIterable, Hashable, Sendable {
    case observe
    case act
    case control
}

public enum Stage3StudyJobCategoryV1: String, CaseIterable, Hashable, Sendable {
    case observeLongRunningTask
    case observeSystemHealth
    case observeAvailability
    case actSetAudioMuted
    case controlUnexpectedDialog
    case controlDevelopmentApp
    case controlOtherOwnedApp

    fileprivate var path: Stage3StudyPathV1 {
        switch self {
        case .observeLongRunningTask, .observeSystemHealth,
             .observeAvailability:
            .observe
        case .actSetAudioMuted:
            .act
        case .controlUnexpectedDialog, .controlDevelopmentApp,
             .controlOtherOwnedApp:
            .control
        }
    }
}

public enum Stage3StudyWorkaroundV1: String, CaseIterable, Hashable, Sendable {
    case returnOrDefer
    case screenSharingOrRemoteDesktop
    case sshScriptShortcutOrUtility
    case keepPrimaryMacNearby
    case noWorkableAlternative
}

public enum Stage3StudyRouteClassV1: String, CaseIterable, Hashable, Sendable {
    case lan
    case privateDNS
    case privateNetwork
}

public enum Stage3StudyControlModeV1: String, CaseIterable, Hashable, Sendable {
    case desktop
    case application
    case window
    case focusedRegion

    fileprivate var isAdaptive: Bool { self != .desktop }
}

public enum Stage3StudyPhysicalReturnReasonV1:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case permission
    case pairing
    case network
    case lock
    case sleep
    case dialog
    case input
    case unclearState
    case other
}

public enum Stage3StudySafetyIncidentV1:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case staleAuthorityInput
    case unintendedSurfaceOrFieldInput
    case behindLockContentDisclosure
    case unauthorizedCapabilityElevation
    case localStopOrRevocationFailure
}

public enum Stage3StudyRecoveryConfusionV1:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case unreachablePresentedAsLive
    case stalePresentedAsFresh
    case lockedPresentedAsUnlocked
    case sleepingPresentedAsReachable
    case outcomeUnknownPresentedAsCompleted
}

public enum Stage3StudyOperationalEventKindV1:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case macInstall
    case clientInstall
    case screenRecordingPermission
    case accessibilityPermission
    case route
    case connection
    case surfaceChange
    case fallback
    case stop
    case revoke
    case recovery
}

public enum Stage3StudyOperationalEventInitiatorV1:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case user
    case automatic
    case system
}

public enum Stage3StudyReportErrorV1: Error, Equatable, Sendable {
    case invalidField(String)
    case boundsExceeded(String)
    case duplicateValue(String)
    case inconsistentState(String)
}

public struct Stage3StudyBuildV1: Equatable, Sendable {
    public let appVersion: String
    public let buildNumber: String
    public let protocolVersion: String
    public let iOSMajorVersion: Int
    public let macOSMajorVersion: Int

    public init(
        appVersion: String,
        buildNumber: String,
        protocolVersion: String = "0.1",
        iOSMajorVersion: Int,
        macOSMajorVersion: Int
    ) throws {
        guard Stage3StudyRulesV1.isVersion(appVersion) else {
            throw Stage3StudyReportErrorV1.invalidField("appVersion")
        }
        guard Stage3StudyRulesV1.isBuildNumber(buildNumber) else {
            throw Stage3StudyReportErrorV1.invalidField("buildNumber")
        }
        guard protocolVersion == "0.1" else {
            throw Stage3StudyReportErrorV1.invalidField("protocolVersion")
        }
        guard (26...99).contains(iOSMajorVersion) else {
            throw Stage3StudyReportErrorV1.invalidField(
                "iOSMajorVersion"
            )
        }
        guard (26...99).contains(macOSMajorVersion) else {
            throw Stage3StudyReportErrorV1.invalidField(
                "macOSMajorVersion"
            )
        }
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.protocolVersion = protocolVersion
        self.iOSMajorVersion = iOSMajorVersion
        self.macOSMajorVersion = macOSMajorVersion
    }
}

public struct Stage3StudyPairingV1: Equatable, Sendable {
    public let result: Stage3StudyAttemptResultV1
    public let developerIntervention: Bool

    public init(
        result: Stage3StudyAttemptResultV1,
        developerIntervention: Bool
    ) {
        self.result = result
        self.developerIntervention = developerIntervention
    }

    public var completedWithoutIntervention: Bool {
        result == .completed && !developerIntervention
    }
}

public struct Stage3StudyJobV1: Equatable, Sendable {
    public let dayIndex: Int
    public let path: Stage3StudyPathV1
    public let category: Stage3StudyJobCategoryV1
    public let result: Stage3StudyAttemptResultV1
    public let controlWasActive: Bool
    public let controlModesUsed: [Stage3StudyControlModeV1]

    public init(
        dayIndex: Int,
        path: Stage3StudyPathV1,
        category: Stage3StudyJobCategoryV1,
        result: Stage3StudyAttemptResultV1,
        controlWasActive: Bool,
        controlModesUsed: [Stage3StudyControlModeV1] = []
    ) throws {
        guard (0..<Stage3StudyRulesV1.studyDayCount).contains(dayIndex) else {
            throw Stage3StudyReportErrorV1.invalidField("job.dayIndex")
        }
        guard category.path == path else {
            throw Stage3StudyReportErrorV1.inconsistentState(
                "job.categoryPath"
            )
        }
        try Stage3StudyRulesV1.requireUnique(
            controlModesUsed,
            field: "job.controlModesUsed"
        )
        switch path {
        case .control:
            guard controlWasActive, !controlModesUsed.isEmpty else {
                throw Stage3StudyReportErrorV1.inconsistentState(
                    "job.controlShape"
                )
            }
        case .observe, .act:
            guard controlModesUsed.isEmpty else {
                throw Stage3StudyReportErrorV1.inconsistentState(
                    "job.nonControlModes"
                )
            }
        }
        self.dayIndex = dayIndex
        self.path = path
        self.category = category
        self.result = result
        self.controlWasActive = controlWasActive
        self.controlModesUsed = controlModesUsed.sorted {
            $0.rawValue < $1.rawValue
        }
    }

    public var isCompletedRealJob: Bool { result == .completed }
    public var usedAdaptiveMode: Bool {
        controlModesUsed.contains(where: \.isAdaptive)
    }
}

public struct Stage3StudyOperationalEventV1: Equatable, Sendable {
    public let dayIndex: Int
    public let kind: Stage3StudyOperationalEventKindV1
    public let initiator: Stage3StudyOperationalEventInitiatorV1
    public let result: Stage3StudyAttemptResultV1

    public init(
        dayIndex: Int,
        kind: Stage3StudyOperationalEventKindV1,
        initiator: Stage3StudyOperationalEventInitiatorV1,
        result: Stage3StudyAttemptResultV1
    ) throws {
        guard (0..<Stage3StudyRulesV1.studyDayCount).contains(dayIndex) else {
            throw Stage3StudyReportErrorV1.invalidField(
                "operationalEvent.dayIndex"
            )
        }
        self.dayIndex = dayIndex
        self.kind = kind
        self.initiator = initiator
        self.result = result
    }
}

public struct Stage3StudyControlDurationsV1: Equatable, Sendable {
    public let desktopMilliseconds: Int64
    public let applicationMilliseconds: Int64
    public let windowMilliseconds: Int64
    public let focusedRegionMilliseconds: Int64

    public init(
        desktopMilliseconds: Int64,
        applicationMilliseconds: Int64,
        windowMilliseconds: Int64,
        focusedRegionMilliseconds: Int64
    ) throws {
        let values = [
            desktopMilliseconds,
            applicationMilliseconds,
            windowMilliseconds,
            focusedRegionMilliseconds,
        ]
        guard values.allSatisfy({ $0 >= 0 }) else {
            throw Stage3StudyReportErrorV1.invalidField(
                "controlDurations"
            )
        }
        guard values.reduce(0, +) <= Stage3StudyRulesV1.maximumStudyDuration
        else {
            throw Stage3StudyReportErrorV1.boundsExceeded(
                "controlDurations"
            )
        }
        self.desktopMilliseconds = desktopMilliseconds
        self.applicationMilliseconds = applicationMilliseconds
        self.windowMilliseconds = windowMilliseconds
        self.focusedRegionMilliseconds = focusedRegionMilliseconds
    }

    public var totalMilliseconds: Int64 {
        desktopMilliseconds + applicationMilliseconds
            + windowMilliseconds + focusedRegionMilliseconds
    }

    public var adaptiveMilliseconds: Int64 {
        applicationMilliseconds + windowMilliseconds
            + focusedRegionMilliseconds
    }
}

public struct Stage3StudyTimingsV1: Equatable, Sendable {
    public let timeToPairMilliseconds: Int64?
    public let timeToFirstFreshObserveMilliseconds: Int64?
    public let timeToFirstControllableFrameMilliseconds: Int64?
    public let routeRecoveryMilliseconds: Int64?
    public let surfaceTransitionMilliseconds: Int64?

    public init(
        timeToPairMilliseconds: Int64? = nil,
        timeToFirstFreshObserveMilliseconds: Int64? = nil,
        timeToFirstControllableFrameMilliseconds: Int64? = nil,
        routeRecoveryMilliseconds: Int64? = nil,
        surfaceTransitionMilliseconds: Int64? = nil
    ) throws {
        let values = [
            timeToPairMilliseconds,
            timeToFirstFreshObserveMilliseconds,
            timeToFirstControllableFrameMilliseconds,
            routeRecoveryMilliseconds,
            surfaceTransitionMilliseconds,
        ]
        guard values.allSatisfy({ value in
            value.map {
                (0...Stage3StudyRulesV1.maximumTimingDuration).contains($0)
            } ?? true
        }) else {
            throw Stage3StudyReportErrorV1.boundsExceeded("timings")
        }
        self.timeToPairMilliseconds = timeToPairMilliseconds
        self.timeToFirstFreshObserveMilliseconds =
            timeToFirstFreshObserveMilliseconds
        self.timeToFirstControllableFrameMilliseconds =
            timeToFirstControllableFrameMilliseconds
        self.routeRecoveryMilliseconds = routeRecoveryMilliseconds
        self.surfaceTransitionMilliseconds = surfaceTransitionMilliseconds
    }
}

public struct Stage3StudyPhysicalReturnV1: Equatable, Hashable, Sendable {
    public let dayIndex: Int
    public let reason: Stage3StudyPhysicalReturnReasonV1

    public init(
        dayIndex: Int,
        reason: Stage3StudyPhysicalReturnReasonV1
    ) throws {
        guard (0..<Stage3StudyRulesV1.studyDayCount).contains(dayIndex) else {
            throw Stage3StudyReportErrorV1.invalidField(
                "physicalReturn.dayIndex"
            )
        }
        self.dayIndex = dayIndex
        self.reason = reason
    }
}

public struct Stage3StudyComprehensionV1: Equatable, Sendable {
    public let distinguishesPairedAndConnected: Bool
    public let distinguishesViewingAndControlling: Bool
    public let understandsApprovalRequired: Bool
    public let understandsSeparateGrants: Bool

    public init(
        distinguishesPairedAndConnected: Bool,
        distinguishesViewingAndControlling: Bool,
        understandsApprovalRequired: Bool,
        understandsSeparateGrants: Bool
    ) {
        self.distinguishesPairedAndConnected =
            distinguishesPairedAndConnected
        self.distinguishesViewingAndControlling =
            distinguishesViewingAndControlling
        self.understandsApprovalRequired = understandsApprovalRequired
        self.understandsSeparateGrants = understandsSeparateGrants
    }

    public var isCorrect: Bool {
        distinguishesPairedAndConnected
            && distinguishesViewingAndControlling
            && understandsApprovalRequired
            && understandsSeparateGrants
    }
}

public struct Stage3StudyReportV1: Equatable, Sendable {
    public static let schema = "maccompanion.stage3.study-report.v1"
    public static let adrRevision = "0002@2026-08-23"
    public static let maximumEncodedBytes = 256 * 1_024

    public let cohortPhase: Stage3StudyCohortPhaseV1
    public let studyCode: String
    public let build: Stage3StudyBuildV1
    public let setupAttempted: Bool
    public let pairing: Stage3StudyPairingV1
    public let firstFreshObserve: Stage3StudyAttemptResultV1
    public let workaround: Stage3StudyWorkaroundV1
    public let adaptiveJobApplicable: Bool
    public let jobs: [Stage3StudyJobV1]
    public let operationalEvents: [Stage3StudyOperationalEventV1]
    public let controlDurations: Stage3StudyControlDurationsV1
    public let routeClassesUsed: [Stage3StudyRouteClassV1]
    public let timings: Stage3StudyTimingsV1
    public let physicalReturns: [Stage3StudyPhysicalReturnV1]
    public let comprehension: Stage3StudyComprehensionV1?
    public let safetyReviewCompleted: Bool
    public let safetyIncidents: [Stage3StudySafetyIncidentV1]
    public let recoveryConfusions: [Stage3StudyRecoveryConfusionV1]

    public init(
        cohortPhase: Stage3StudyCohortPhaseV1,
        studyCode: String,
        build: Stage3StudyBuildV1,
        setupAttempted: Bool,
        pairing: Stage3StudyPairingV1,
        firstFreshObserve: Stage3StudyAttemptResultV1,
        workaround: Stage3StudyWorkaroundV1,
        adaptiveJobApplicable: Bool,
        jobs: [Stage3StudyJobV1],
        operationalEvents: [Stage3StudyOperationalEventV1],
        controlDurations: Stage3StudyControlDurationsV1,
        routeClassesUsed: [Stage3StudyRouteClassV1],
        timings: Stage3StudyTimingsV1,
        physicalReturns: [Stage3StudyPhysicalReturnV1],
        comprehension: Stage3StudyComprehensionV1?,
        safetyReviewCompleted: Bool,
        safetyIncidents: [Stage3StudySafetyIncidentV1],
        recoveryConfusions: [Stage3StudyRecoveryConfusionV1]
    ) throws {
        guard Stage3StudyRulesV1.isStudyCode(studyCode) else {
            throw Stage3StudyReportErrorV1.invalidField("studyCode")
        }
        guard jobs.count <= Stage3StudyRulesV1.maximumJobs else {
            throw Stage3StudyReportErrorV1.boundsExceeded("jobs")
        }
        guard operationalEvents.count
            <= Stage3StudyRulesV1.maximumOperationalEvents else {
            throw Stage3StudyReportErrorV1.boundsExceeded(
                "operationalEvents"
            )
        }
        guard physicalReturns.count
            <= Stage3StudyRulesV1.maximumPhysicalReturns else {
            throw Stage3StudyReportErrorV1.boundsExceeded(
                "physicalReturns"
            )
        }
        try Stage3StudyRulesV1.requireUnique(
            routeClassesUsed,
            field: "routeClassesUsed"
        )
        try Stage3StudyRulesV1.requireUnique(
            physicalReturns,
            field: "physicalReturns"
        )
        try Stage3StudyRulesV1.requireUnique(
            safetyIncidents,
            field: "safetyIncidents"
        )
        try Stage3StudyRulesV1.requireUnique(
            recoveryConfusions,
            field: "recoveryConfusions"
        )
        guard setupAttempted || pairing.result == .notAttempted else {
            throw Stage3StudyReportErrorV1.inconsistentState(
                "pairingWithoutSetup"
            )
        }
        guard !pairing.developerIntervention
            || pairing.result != .notAttempted else {
            throw Stage3StudyReportErrorV1.inconsistentState(
                "interventionWithoutPairingAttempt"
            )
        }
        guard pairing.result != .completed || setupAttempted else {
            throw Stage3StudyReportErrorV1.inconsistentState(
                "completedPairingWithoutSetup"
            )
        }
        guard firstFreshObserve != .completed
            || pairing.result == .completed else {
            throw Stage3StudyReportErrorV1.inconsistentState(
                "observeWithoutPairing"
            )
        }
        if pairing.result != .completed {
            guard jobs.isEmpty,
                  controlDurations.totalMilliseconds == 0,
                  routeClassesUsed.isEmpty else {
                throw Stage3StudyReportErrorV1.inconsistentState(
                    "remoteEvidenceWithoutPairing"
                )
            }
        }
        if controlDurations.totalMilliseconds > 0 {
            guard jobs.contains(where: { job in
                job.path == .control && job.controlWasActive
            }) else {
                throw Stage3StudyReportErrorV1.inconsistentState(
                    "controlDurationWithoutControlJob"
                )
            }
        }
        let adaptiveEvidence = jobs.contains(where: \.usedAdaptiveMode)
            || controlDurations.adaptiveMilliseconds > 0
        guard !adaptiveEvidence || adaptiveJobApplicable else {
            throw Stage3StudyReportErrorV1.inconsistentState(
                "adaptiveEvidenceNotApplicable"
            )
        }
        if pairing.result == .completed {
            guard timings.timeToPairMilliseconds != nil else {
                throw Stage3StudyReportErrorV1.inconsistentState(
                    "completedPairingWithoutTiming"
                )
            }
        }
        if firstFreshObserve == .completed {
            guard timings.timeToFirstFreshObserveMilliseconds != nil else {
                throw Stage3StudyReportErrorV1.inconsistentState(
                    "completedObserveWithoutTiming"
                )
            }
        }
        self.cohortPhase = cohortPhase
        self.studyCode = studyCode
        self.build = build
        self.setupAttempted = setupAttempted
        self.pairing = pairing
        self.firstFreshObserve = firstFreshObserve
        self.workaround = workaround
        self.adaptiveJobApplicable = adaptiveJobApplicable
        self.jobs = jobs
        self.operationalEvents = operationalEvents
        self.controlDurations = controlDurations
        self.routeClassesUsed = routeClassesUsed.sorted {
            $0.rawValue < $1.rawValue
        }
        self.timings = timings
        self.physicalReturns = physicalReturns.sorted {
            ($0.dayIndex, $0.reason.rawValue)
                < ($1.dayIndex, $1.reason.rawValue)
        }
        self.comprehension = comprehension
        self.safetyReviewCompleted = safetyReviewCompleted
        self.safetyIncidents = safetyIncidents.sorted {
            $0.rawValue < $1.rawValue
        }
        self.recoveryConfusions = recoveryConfusions.sorted {
            $0.rawValue < $1.rawValue
        }
    }

    public var isActivated: Bool {
        pairing.result == .completed && firstFreshObserve == .completed
    }
}

public enum Stage3StudyReportCodecV1 {
    public static func encode(_ report: Stage3StudyReportV1) throws -> Data {
        let data = CanonicalJSON.canonicalData(for: report.wireValue)
        guard data.count <= Stage3StudyReportV1.maximumEncodedBytes else {
            throw Stage3StudyReportErrorV1.boundsExceeded("encodedBytes")
        }
        return data
    }

    public static func decode(_ data: Data) throws -> Stage3StudyReportV1 {
        guard !data.isEmpty,
              data.count <= Stage3StudyReportV1.maximumEncodedBytes else {
            throw Stage3StudyReportErrorV1.boundsExceeded("encodedBytes")
        }
        let canonicalInput = data.last == UInt8(ascii: "\n")
            ? Data(data.dropLast())
            : data
        guard !canonicalInput.isEmpty,
              try CanonicalJSON.canonicalize(canonicalInput)
                == canonicalInput else {
            throw Stage3StudyReportErrorV1.invalidField("canonicalJSON")
        }
        let value = try CanonicalJSON.parse(canonicalInput)
        try CanonicalJSON.validate(value)
        return try Stage3StudyReportV1(wireValue: value)
    }
}

enum Stage3StudyRulesV1 {
    static let studyDayCount = 14
    static let maximumJobs = 256
    static let maximumOperationalEvents = 512
    static let maximumPhysicalReturns = 64
    static let maximumStudyDuration: Int64 = 14 * 24 * 60 * 60 * 1_000
    static let maximumTimingDuration: Int64 = 24 * 60 * 60 * 1_000

    static func isStudyCode(_ value: String) -> Bool {
        value.utf8.count == 16 && value.utf8.allSatisfy { byte in
            (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
                || (UInt8(ascii: "2")...UInt8(ascii: "7")).contains(byte)
        }
    }

    static func isVersion(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 32,
              value.first != ".", value.last != "." else { return false }
        var previousDot = false
        for byte in value.utf8 {
            if byte == UInt8(ascii: ".") {
                guard !previousDot else { return false }
                previousDot = true
            } else {
                guard (UInt8(ascii: "0")...UInt8(ascii: "9"))
                    .contains(byte) else { return false }
                previousDot = false
            }
        }
        return true
    }

    static func isBuildNumber(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 20
            && value.utf8.allSatisfy {
                (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0)
            }
    }

    static func requireUnique<T: Hashable>(
        _ values: [T],
        field: String
    ) throws {
        guard Set(values).count == values.count else {
            throw Stage3StudyReportErrorV1.duplicateValue(field)
        }
    }
}

private extension Stage3StudyReportV1 {
    var wireValue: CanonicalJSONValue {
        .object([
            .init(key: "schema", value: .string(Self.schema)),
            .init(key: "adrRevision", value: .string(Self.adrRevision)),
            .init(key: "cohortPhase", value: .string(cohortPhase.rawValue)),
            .init(key: "studyCode", value: .string(studyCode)),
            .init(key: "build", value: build.wireValue),
            .init(key: "setupAttempted", value: .boolean(setupAttempted)),
            .init(key: "pairing", value: pairing.wireValue),
            .init(
                key: "firstFreshObserve",
                value: .string(firstFreshObserve.rawValue)
            ),
            .init(key: "workaround", value: .string(workaround.rawValue)),
            .init(
                key: "adaptiveJobApplicable",
                value: .boolean(adaptiveJobApplicable)
            ),
            .init(key: "jobs", value: .array(jobs.map(\.wireValue))),
            .init(
                key: "operationalEvents",
                value: .array(operationalEvents.map(\.wireValue))
            ),
            .init(key: "controlDurations", value: controlDurations.wireValue),
            .init(
                key: "routeClassesUsed",
                value: .array(routeClassesUsed.map {
                    .string($0.rawValue)
                })
            ),
            .init(key: "timings", value: timings.wireValue),
            .init(
                key: "physicalReturns",
                value: .array(physicalReturns.map(\.wireValue))
            ),
            .init(
                key: "comprehension",
                value: comprehension?.wireValue ?? .null
            ),
            .init(
                key: "safetyReviewCompleted",
                value: .boolean(safetyReviewCompleted)
            ),
            .init(
                key: "safetyIncidents",
                value: .array(safetyIncidents.map {
                    .string($0.rawValue)
                })
            ),
            .init(
                key: "recoveryConfusions",
                value: .array(recoveryConfusions.map {
                    .string($0.rawValue)
                })
            ),
        ])
    }

    init(wireValue: CanonicalJSONValue) throws {
        let object = try StudyJSONV1.object(
            wireValue,
            keys: [
                "schema", "adrRevision", "cohortPhase", "studyCode",
                "build", "setupAttempted", "pairing", "firstFreshObserve",
                "workaround", "adaptiveJobApplicable", "jobs",
                "operationalEvents",
                "controlDurations", "routeClassesUsed", "timings",
                "physicalReturns", "comprehension", "safetyReviewCompleted",
                "safetyIncidents", "recoveryConfusions",
            ],
            field: "report"
        )
        guard try StudyJSONV1.string(object, "schema") == Self.schema,
              try StudyJSONV1.string(object, "adrRevision")
                == Self.adrRevision else {
            throw Stage3StudyReportErrorV1.invalidField("schema")
        }
        let phase: Stage3StudyCohortPhaseV1 = try StudyJSONV1.enumeration(
            object,
            "cohortPhase"
        )
        let observe: Stage3StudyAttemptResultV1 = try StudyJSONV1.enumeration(
            object,
            "firstFreshObserve"
        )
        let workaround: Stage3StudyWorkaroundV1 = try StudyJSONV1.enumeration(
            object,
            "workaround"
        )
        try self.init(
            cohortPhase: phase,
            studyCode: try StudyJSONV1.string(object, "studyCode"),
            build: try Stage3StudyBuildV1(
                wireValue: StudyJSONV1.value(object, "build")
            ),
            setupAttempted: try StudyJSONV1.boolean(
                object,
                "setupAttempted"
            ),
            pairing: try Stage3StudyPairingV1(
                wireValue: StudyJSONV1.value(object, "pairing")
            ),
            firstFreshObserve: observe,
            workaround: workaround,
            adaptiveJobApplicable: try StudyJSONV1.boolean(
                object,
                "adaptiveJobApplicable"
            ),
            jobs: try StudyJSONV1.array(object, "jobs").map {
                try Stage3StudyJobV1(wireValue: $0)
            },
            operationalEvents: try StudyJSONV1.array(
                object,
                "operationalEvents"
            ).map { try Stage3StudyOperationalEventV1(wireValue: $0) },
            controlDurations: try Stage3StudyControlDurationsV1(
                wireValue: StudyJSONV1.value(object, "controlDurations")
            ),
            routeClassesUsed: try StudyJSONV1.array(
                object,
                "routeClassesUsed"
            ).map { try StudyJSONV1.enumeration($0, field: "routeClass") },
            timings: try Stage3StudyTimingsV1(
                wireValue: StudyJSONV1.value(object, "timings")
            ),
            physicalReturns: try StudyJSONV1.array(
                object,
                "physicalReturns"
            ).map { try Stage3StudyPhysicalReturnV1(wireValue: $0) },
            comprehension: try Stage3StudyComprehensionV1.decodeOptional(
                StudyJSONV1.value(object, "comprehension")
            ),
            safetyReviewCompleted: try StudyJSONV1.boolean(
                object,
                "safetyReviewCompleted"
            ),
            safetyIncidents: try StudyJSONV1.array(
                object,
                "safetyIncidents"
            ).map { try StudyJSONV1.enumeration($0, field: "safetyIncident") },
            recoveryConfusions: try StudyJSONV1.array(
                object,
                "recoveryConfusions"
            ).map {
                try StudyJSONV1.enumeration($0, field: "recoveryConfusion")
            }
        )
    }
}

private extension Stage3StudyBuildV1 {
    var wireValue: CanonicalJSONValue {
        .object([
            .init(key: "appVersion", value: .string(appVersion)),
            .init(key: "buildNumber", value: .string(buildNumber)),
            .init(key: "protocolVersion", value: .string(protocolVersion)),
            .init(
                key: "iOSMajorVersion",
                value: .integer(Int64(iOSMajorVersion))
            ),
            .init(
                key: "macOSMajorVersion",
                value: .integer(Int64(macOSMajorVersion))
            ),
        ])
    }

    init(wireValue: CanonicalJSONValue) throws {
        let object = try StudyJSONV1.object(
            wireValue,
            keys: [
                "appVersion", "buildNumber", "protocolVersion",
                "iOSMajorVersion", "macOSMajorVersion",
            ],
            field: "build"
        )
        try self.init(
            appVersion: try StudyJSONV1.string(object, "appVersion"),
            buildNumber: try StudyJSONV1.string(object, "buildNumber"),
            protocolVersion: try StudyJSONV1.string(
                object,
                "protocolVersion"
            ),
            iOSMajorVersion: try StudyJSONV1.int(object, "iOSMajorVersion"),
            macOSMajorVersion: try StudyJSONV1.int(
                object,
                "macOSMajorVersion"
            )
        )
    }
}

private extension Stage3StudyPairingV1 {
    var wireValue: CanonicalJSONValue {
        .object([
            .init(key: "result", value: .string(result.rawValue)),
            .init(
                key: "developerIntervention",
                value: .boolean(developerIntervention)
            ),
        ])
    }

    init(wireValue: CanonicalJSONValue) throws {
        let object = try StudyJSONV1.object(
            wireValue,
            keys: ["result", "developerIntervention"],
            field: "pairing"
        )
        self.init(
            result: try StudyJSONV1.enumeration(object, "result"),
            developerIntervention: try StudyJSONV1.boolean(
                object,
                "developerIntervention"
            )
        )
    }
}

private extension Stage3StudyJobV1 {
    var wireValue: CanonicalJSONValue {
        .object([
            .init(key: "dayIndex", value: .integer(Int64(dayIndex))),
            .init(key: "path", value: .string(path.rawValue)),
            .init(key: "category", value: .string(category.rawValue)),
            .init(key: "result", value: .string(result.rawValue)),
            .init(
                key: "controlWasActive",
                value: .boolean(controlWasActive)
            ),
            .init(
                key: "controlModesUsed",
                value: .array(controlModesUsed.map {
                    .string($0.rawValue)
                })
            ),
        ])
    }

    init(wireValue: CanonicalJSONValue) throws {
        let object = try StudyJSONV1.object(
            wireValue,
            keys: [
                "dayIndex", "path", "category", "result",
                "controlWasActive", "controlModesUsed",
            ],
            field: "job"
        )
        try self.init(
            dayIndex: try StudyJSONV1.int(object, "dayIndex"),
            path: try StudyJSONV1.enumeration(object, "path"),
            category: try StudyJSONV1.enumeration(object, "category"),
            result: try StudyJSONV1.enumeration(object, "result"),
            controlWasActive: try StudyJSONV1.boolean(
                object,
                "controlWasActive"
            ),
            controlModesUsed: try StudyJSONV1.array(
                object,
                "controlModesUsed"
            ).map { try StudyJSONV1.enumeration($0, field: "controlMode") }
        )
    }
}

private extension Stage3StudyOperationalEventV1 {
    var wireValue: CanonicalJSONValue {
        .object([
            .init(key: "dayIndex", value: .integer(Int64(dayIndex))),
            .init(key: "kind", value: .string(kind.rawValue)),
            .init(key: "initiator", value: .string(initiator.rawValue)),
            .init(key: "result", value: .string(result.rawValue)),
        ])
    }

    init(wireValue: CanonicalJSONValue) throws {
        let object = try StudyJSONV1.object(
            wireValue,
            keys: ["dayIndex", "kind", "initiator", "result"],
            field: "operationalEvent"
        )
        try self.init(
            dayIndex: try StudyJSONV1.int(object, "dayIndex"),
            kind: try StudyJSONV1.enumeration(object, "kind"),
            initiator: try StudyJSONV1.enumeration(object, "initiator"),
            result: try StudyJSONV1.enumeration(object, "result")
        )
    }
}

private extension Stage3StudyControlDurationsV1 {
    var wireValue: CanonicalJSONValue {
        .object([
            .init(
                key: "desktopMilliseconds",
                value: .integer(desktopMilliseconds)
            ),
            .init(
                key: "applicationMilliseconds",
                value: .integer(applicationMilliseconds)
            ),
            .init(
                key: "windowMilliseconds",
                value: .integer(windowMilliseconds)
            ),
            .init(
                key: "focusedRegionMilliseconds",
                value: .integer(focusedRegionMilliseconds)
            ),
        ])
    }

    init(wireValue: CanonicalJSONValue) throws {
        let object = try StudyJSONV1.object(
            wireValue,
            keys: [
                "desktopMilliseconds", "applicationMilliseconds",
                "windowMilliseconds", "focusedRegionMilliseconds",
            ],
            field: "controlDurations"
        )
        try self.init(
            desktopMilliseconds: try StudyJSONV1.int64(
                object,
                "desktopMilliseconds"
            ),
            applicationMilliseconds: try StudyJSONV1.int64(
                object,
                "applicationMilliseconds"
            ),
            windowMilliseconds: try StudyJSONV1.int64(
                object,
                "windowMilliseconds"
            ),
            focusedRegionMilliseconds: try StudyJSONV1.int64(
                object,
                "focusedRegionMilliseconds"
            )
        )
    }
}

private extension Stage3StudyTimingsV1 {
    var wireValue: CanonicalJSONValue {
        .object([
            .init(
                key: "timeToPairMilliseconds",
                value: StudyJSONV1.optionalInteger(timeToPairMilliseconds)
            ),
            .init(
                key: "timeToFirstFreshObserveMilliseconds",
                value: StudyJSONV1.optionalInteger(
                    timeToFirstFreshObserveMilliseconds
                )
            ),
            .init(
                key: "timeToFirstControllableFrameMilliseconds",
                value: StudyJSONV1.optionalInteger(
                    timeToFirstControllableFrameMilliseconds
                )
            ),
            .init(
                key: "routeRecoveryMilliseconds",
                value: StudyJSONV1.optionalInteger(routeRecoveryMilliseconds)
            ),
            .init(
                key: "surfaceTransitionMilliseconds",
                value: StudyJSONV1.optionalInteger(
                    surfaceTransitionMilliseconds
                )
            ),
        ])
    }

    init(wireValue: CanonicalJSONValue) throws {
        let object = try StudyJSONV1.object(
            wireValue,
            keys: [
                "timeToPairMilliseconds",
                "timeToFirstFreshObserveMilliseconds",
                "timeToFirstControllableFrameMilliseconds",
                "routeRecoveryMilliseconds", "surfaceTransitionMilliseconds",
            ],
            field: "timings"
        )
        try self.init(
            timeToPairMilliseconds: try StudyJSONV1.optionalInt64(
                object,
                "timeToPairMilliseconds"
            ),
            timeToFirstFreshObserveMilliseconds:
                try StudyJSONV1.optionalInt64(
                    object,
                    "timeToFirstFreshObserveMilliseconds"
                ),
            timeToFirstControllableFrameMilliseconds:
                try StudyJSONV1.optionalInt64(
                    object,
                    "timeToFirstControllableFrameMilliseconds"
                ),
            routeRecoveryMilliseconds: try StudyJSONV1.optionalInt64(
                object,
                "routeRecoveryMilliseconds"
            ),
            surfaceTransitionMilliseconds: try StudyJSONV1.optionalInt64(
                object,
                "surfaceTransitionMilliseconds"
            )
        )
    }
}

private extension Stage3StudyPhysicalReturnV1 {
    var wireValue: CanonicalJSONValue {
        .object([
            .init(key: "dayIndex", value: .integer(Int64(dayIndex))),
            .init(key: "reason", value: .string(reason.rawValue)),
        ])
    }

    init(wireValue: CanonicalJSONValue) throws {
        let object = try StudyJSONV1.object(
            wireValue,
            keys: ["dayIndex", "reason"],
            field: "physicalReturn"
        )
        try self.init(
            dayIndex: try StudyJSONV1.int(object, "dayIndex"),
            reason: try StudyJSONV1.enumeration(object, "reason")
        )
    }
}

private extension Stage3StudyComprehensionV1 {
    var wireValue: CanonicalJSONValue {
        .object([
            .init(
                key: "distinguishesPairedAndConnected",
                value: .boolean(distinguishesPairedAndConnected)
            ),
            .init(
                key: "distinguishesViewingAndControlling",
                value: .boolean(distinguishesViewingAndControlling)
            ),
            .init(
                key: "understandsApprovalRequired",
                value: .boolean(understandsApprovalRequired)
            ),
            .init(
                key: "understandsSeparateGrants",
                value: .boolean(understandsSeparateGrants)
            ),
        ])
    }

    static func decodeOptional(
        _ value: CanonicalJSONValue
    ) throws -> Stage3StudyComprehensionV1? {
        if value == .null { return nil }
        let object = try StudyJSONV1.object(
            value,
            keys: [
                "distinguishesPairedAndConnected",
                "distinguishesViewingAndControlling",
                "understandsApprovalRequired", "understandsSeparateGrants",
            ],
            field: "comprehension"
        )
        return Stage3StudyComprehensionV1(
            distinguishesPairedAndConnected: try StudyJSONV1.boolean(
                object,
                "distinguishesPairedAndConnected"
            ),
            distinguishesViewingAndControlling: try StudyJSONV1.boolean(
                object,
                "distinguishesViewingAndControlling"
            ),
            understandsApprovalRequired: try StudyJSONV1.boolean(
                object,
                "understandsApprovalRequired"
            ),
            understandsSeparateGrants: try StudyJSONV1.boolean(
                object,
                "understandsSeparateGrants"
            )
        )
    }
}

private enum StudyJSONV1 {
    static func object(
        _ value: CanonicalJSONValue,
        keys: Set<String>,
        field: String
    ) throws -> [String: CanonicalJSONValue] {
        guard case let .object(members) = value,
              Set(members.map(\.key)) == keys else {
            throw Stage3StudyReportErrorV1.invalidField(field)
        }
        return Dictionary(uniqueKeysWithValues: members.map {
            ($0.key, $0.value)
        })
    }

    static func value(
        _ object: [String: CanonicalJSONValue],
        _ key: String
    ) throws -> CanonicalJSONValue {
        guard let value = object[key] else {
            throw Stage3StudyReportErrorV1.invalidField(key)
        }
        return value
    }

    static func string(
        _ object: [String: CanonicalJSONValue],
        _ key: String
    ) throws -> String {
        guard case let .string(value) = try value(object, key) else {
            throw Stage3StudyReportErrorV1.invalidField(key)
        }
        return value
    }

    static func boolean(
        _ object: [String: CanonicalJSONValue],
        _ key: String
    ) throws -> Bool {
        guard case let .boolean(value) = try value(object, key) else {
            throw Stage3StudyReportErrorV1.invalidField(key)
        }
        return value
    }

    static func int64(
        _ object: [String: CanonicalJSONValue],
        _ key: String
    ) throws -> Int64 {
        guard case let .integer(value) = try value(object, key) else {
            throw Stage3StudyReportErrorV1.invalidField(key)
        }
        return value
    }

    static func int(
        _ object: [String: CanonicalJSONValue],
        _ key: String
    ) throws -> Int {
        let value = try int64(object, key)
        guard let converted = Int(exactly: value) else {
            throw Stage3StudyReportErrorV1.boundsExceeded(key)
        }
        return converted
    }

    static func optionalInt64(
        _ object: [String: CanonicalJSONValue],
        _ key: String
    ) throws -> Int64? {
        switch try value(object, key) {
        case .null:
            nil
        case let .integer(value):
            value
        default:
            throw Stage3StudyReportErrorV1.invalidField(key)
        }
    }

    static func optionalInteger(_ value: Int64?) -> CanonicalJSONValue {
        value.map(CanonicalJSONValue.integer) ?? .null
    }

    static func array(
        _ object: [String: CanonicalJSONValue],
        _ key: String
    ) throws -> [CanonicalJSONValue] {
        guard case let .array(values) = try value(object, key) else {
            throw Stage3StudyReportErrorV1.invalidField(key)
        }
        return values
    }

    static func enumeration<T: RawRepresentable>(
        _ object: [String: CanonicalJSONValue],
        _ key: String
    ) throws -> T where T.RawValue == String {
        let raw = try string(object, key)
        guard let value = T(rawValue: raw) else {
            throw Stage3StudyReportErrorV1.invalidField(key)
        }
        return value
    }

    static func enumeration<T: RawRepresentable>(
        _ value: CanonicalJSONValue,
        field: String
    ) throws -> T where T.RawValue == String {
        guard case let .string(raw) = value,
              let parsed = T(rawValue: raw) else {
            throw Stage3StudyReportErrorV1.invalidField(field)
        }
        return parsed
    }
}
