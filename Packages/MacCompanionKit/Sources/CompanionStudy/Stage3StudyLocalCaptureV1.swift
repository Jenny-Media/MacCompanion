import Dispatch
import Foundation

public enum Stage3StudyLocalCaptureErrorV1:
    Error, Equatable, Sendable
{
    case alreadyEnrolled
    case noEnrollment
    case sessionAlreadyActive
    case noActiveSession
    case invalidDayIndex
    case invalidTransition
}

public struct Stage3StudyLocalEnrollmentV1: Equatable, Sendable {
    public let cohortPhase: Stage3StudyCohortPhaseV1
    public let studyCode: String
    public let build: Stage3StudyBuildV1
    public let workaround: Stage3StudyWorkaroundV1
    public let adaptiveJobApplicable: Bool

    public init(
        cohortPhase: Stage3StudyCohortPhaseV1,
        studyCode: String,
        build: Stage3StudyBuildV1,
        workaround: Stage3StudyWorkaroundV1,
        adaptiveJobApplicable: Bool
    ) {
        self.cohortPhase = cohortPhase
        self.studyCode = studyCode
        self.build = build
        self.workaround = workaround
        self.adaptiveJobApplicable = adaptiveJobApplicable
    }
}

public struct Stage3StudyControlDurationDeltaV1: Equatable, Sendable {
    public let desktopMilliseconds: Int64
    public let applicationMilliseconds: Int64
    public let windowMilliseconds: Int64
    public let focusedRegionMilliseconds: Int64

    public init(
        desktopMilliseconds: Int64 = 0,
        applicationMilliseconds: Int64 = 0,
        windowMilliseconds: Int64 = 0,
        focusedRegionMilliseconds: Int64 = 0
    ) throws {
        let validated = try Stage3StudyControlDurationsV1(
            desktopMilliseconds: desktopMilliseconds,
            applicationMilliseconds: applicationMilliseconds,
            windowMilliseconds: windowMilliseconds,
            focusedRegionMilliseconds: focusedRegionMilliseconds
        )
        self.desktopMilliseconds = validated.desktopMilliseconds
        self.applicationMilliseconds = validated.applicationMilliseconds
        self.windowMilliseconds = validated.windowMilliseconds
        self.focusedRegionMilliseconds =
            validated.focusedRegionMilliseconds
    }
}

public enum Stage3StudyTimingKindV1: String, CaseIterable, Sendable {
    case routeRecovery
    case surfaceTransition
}

/// Owns an explicitly started local study session. Nothing is captured before
/// enrollment and `beginSession(dayIndex:)`, and no wall-clock timestamp or
/// stable product identity is persisted. Callers may submit only closed facts
/// already established by their product authority.
public actor Stage3StudyLocalCaptureV1 {
    private struct SessionFence: Equatable, Sendable {
        let id: UUID
        let dayIndex: Int
    }

    private let reportOwner: Stage3StudyLocalReportOwnerV1
    private let monotonicNowMilliseconds: @Sendable () -> Int64
    private var activeDayIndex: Int?
    private var sessionStartedAtMilliseconds: Int64?
    private var activeSessionID: UUID?
    private var mutationOwned = false
    private var mutationWaiters: [CheckedContinuation<Void, Never>] = []

    public init(
        reportOwner: Stage3StudyLocalReportOwnerV1,
        monotonicNowMilliseconds: @escaping @Sendable () -> Int64 = {
            let value = DispatchTime.now().uptimeNanoseconds / 1_000_000
            return value <= UInt64(Int64.max) ? Int64(value) : -1
        }
    ) {
        self.reportOwner = reportOwner
        self.monotonicNowMilliseconds = monotonicNowMilliseconds
    }

    @discardableResult
    public func enroll(
        _ enrollment: Stage3StudyLocalEnrollmentV1
    ) async throws -> Stage3StudyReportV1 {
        await acquireMutation()
        defer { releaseMutation() }
        guard try await reportOwner.currentReport() == nil else {
            throw Stage3StudyLocalCaptureErrorV1.alreadyEnrolled
        }
        let report = try Stage3StudyReportV1(
            cohortPhase: enrollment.cohortPhase,
            studyCode: enrollment.studyCode,
            build: enrollment.build,
            setupAttempted: false,
            pairing: Stage3StudyPairingV1(
                result: .notAttempted,
                developerIntervention: false
            ),
            firstFreshObserve: .notAttempted,
            workaround: enrollment.workaround,
            adaptiveJobApplicable: enrollment.adaptiveJobApplicable,
            jobs: [],
            operationalEvents: [],
            controlDurations: try Stage3StudyControlDurationsV1(
                desktopMilliseconds: 0,
                applicationMilliseconds: 0,
                windowMilliseconds: 0,
                focusedRegionMilliseconds: 0
            ),
            routeClassesUsed: [],
            timings: try Stage3StudyTimingsV1(),
            physicalReturns: [],
            comprehension: nil,
            safetyReviewCompleted: false,
            safetyIncidents: [],
            recoveryConfusions: []
        )
        _ = try await reportOwner.save(report)
        return report
    }

    public func beginSession(dayIndex: Int) async throws {
        await acquireMutation()
        defer { releaseMutation() }
        guard activeDayIndex == nil else {
            throw Stage3StudyLocalCaptureErrorV1.sessionAlreadyActive
        }
        guard (0..<Stage3StudyRulesV1.studyDayCount).contains(dayIndex) else {
            throw Stage3StudyLocalCaptureErrorV1.invalidDayIndex
        }
        guard let report = try await reportOwner.currentReport() else {
            throw Stage3StudyLocalCaptureErrorV1.noEnrollment
        }
        guard !report.safetyReviewCompleted else {
            throw Stage3StudyLocalCaptureErrorV1.invalidTransition
        }
        let now = monotonicNowMilliseconds()
        guard now >= 0 else {
            throw Stage3StudyLocalCaptureErrorV1.invalidTransition
        }
        activeDayIndex = dayIndex
        sessionStartedAtMilliseconds = now
        activeSessionID = UUID()
    }

    public func endSession() async {
        await acquireMutation()
        defer { releaseMutation() }
        activeDayIndex = nil
        sessionStartedAtMilliseconds = nil
        activeSessionID = nil
    }

    public func currentSessionDayIndex() -> Int? { activeDayIndex }

    public func elapsedSinceSessionStartMilliseconds() -> Int64? {
        guard activeDayIndex != nil,
              let sessionStartedAtMilliseconds else { return nil }
        let now = monotonicNowMilliseconds()
        guard now >= sessionStartedAtMilliseconds else { return nil }
        return now - sessionStartedAtMilliseconds
    }

    @discardableResult
    public func recordSetupAttempted() async throws -> Stage3StudyReportV1 {
        let session = try requireSession()
        return try await update(session: session) { draft in
            draft.setupAttempted = true
            if draft.pairing.result == .notAttempted {
                draft.pairing = Stage3StudyPairingV1(
                    result: .notCompleted,
                    developerIntervention: false
                )
            }
        }
    }

    @discardableResult
    public func recordPairingResult(
        _ result: Stage3StudyAttemptResultV1,
        developerIntervention: Bool,
        durationMilliseconds: Int64? = nil
    ) async throws -> Stage3StudyReportV1 {
        let session = try requireSession()
        guard result != .notAttempted,
              result != .notCompleted,
              (result == .completed) == (durationMilliseconds != nil) else {
            throw Stage3StudyLocalCaptureErrorV1.invalidTransition
        }
        return try await update(session: session) { draft in
            guard draft.setupAttempted else {
                throw Stage3StudyLocalCaptureErrorV1.invalidTransition
            }
            if draft.pairing.result == .completed {
                guard result == .completed else {
                    throw Stage3StudyLocalCaptureErrorV1.invalidTransition
                }
                return
            }
            draft.pairing = Stage3StudyPairingV1(
                result: result,
                developerIntervention: developerIntervention
            )
            if let durationMilliseconds {
                draft.timings = try draft.timings.replacing(
                    timeToPairMilliseconds: durationMilliseconds
                )
            }
        }
    }

    @discardableResult
    public func recordFirstFreshObserve(
        _ result: Stage3StudyAttemptResultV1,
        durationMilliseconds: Int64? = nil
    ) async throws -> Stage3StudyReportV1 {
        let session = try requireSession()
        guard result != .notAttempted,
              (result == .completed) == (durationMilliseconds != nil) else {
            throw Stage3StudyLocalCaptureErrorV1.invalidTransition
        }
        return try await update(session: session) { draft in
            guard draft.pairing.result == .completed else {
                throw Stage3StudyLocalCaptureErrorV1.invalidTransition
            }
            if draft.firstFreshObserve == .completed {
                guard result == .completed else {
                    throw Stage3StudyLocalCaptureErrorV1.invalidTransition
                }
                return
            }
            draft.firstFreshObserve = result
            if let durationMilliseconds {
                draft.timings = try draft.timings.replacing(
                    timeToFirstFreshObserveMilliseconds:
                        durationMilliseconds
                )
            }
        }
    }

    @discardableResult
    public func recordOperationalEvent(
        kind: Stage3StudyOperationalEventKindV1,
        initiator: Stage3StudyOperationalEventInitiatorV1,
        result: Stage3StudyAttemptResultV1
    ) async throws -> Stage3StudyReportV1 {
        let session = try requireSession()
        guard result != .notAttempted else {
            throw Stage3StudyLocalCaptureErrorV1.invalidTransition
        }
        return try await update(session: session) { draft in
            draft.operationalEvents.append(
                try Stage3StudyOperationalEventV1(
                    dayIndex: session.dayIndex,
                    kind: kind,
                    initiator: initiator,
                    result: result
                )
            )
        }
    }

    @discardableResult
    public func recordRouteClass(
        _ routeClass: Stage3StudyRouteClassV1
    ) async throws -> Stage3StudyReportV1 {
        let session = try requireSession()
        return try await update(session: session) { draft in
            guard draft.pairing.result == .completed else {
                throw Stage3StudyLocalCaptureErrorV1.invalidTransition
            }
            if !draft.routeClassesUsed.contains(routeClass) {
                draft.routeClassesUsed.append(routeClass)
            }
        }
    }

    @discardableResult
    public func recordJob(
        path: Stage3StudyPathV1,
        category: Stage3StudyJobCategoryV1,
        result: Stage3StudyAttemptResultV1,
        controlModesUsed: [Stage3StudyControlModeV1] = [],
        controlDurationDelta:
            Stage3StudyControlDurationDeltaV1? = nil
    ) async throws -> Stage3StudyReportV1 {
        let session = try requireSession()
        return try await update(session: session) { draft in
            guard draft.pairing.result == .completed else {
                throw Stage3StudyLocalCaptureErrorV1.invalidTransition
            }
            let isControl = path == .control
            guard isControl == (controlDurationDelta != nil) else {
                throw Stage3StudyLocalCaptureErrorV1.invalidTransition
            }
            draft.jobs.append(try Stage3StudyJobV1(
                dayIndex: session.dayIndex,
                path: path,
                category: category,
                result: result,
                controlWasActive: isControl,
                controlModesUsed: controlModesUsed
            ))
            if let controlDurationDelta {
                draft.controlDurations = try draft.controlDurations.adding(
                    controlDurationDelta
                )
            }
        }
    }

    @discardableResult
    public func recordTiming(
        _ kind: Stage3StudyTimingKindV1,
        milliseconds: Int64
    ) async throws -> Stage3StudyReportV1 {
        let session = try requireSession()
        return try await update(session: session) { draft in
            switch kind {
            case .routeRecovery:
                draft.timings = try draft.timings.replacing(
                    routeRecoveryMilliseconds: milliseconds
                )
            case .surfaceTransition:
                draft.timings = try draft.timings.replacing(
                    surfaceTransitionMilliseconds: milliseconds
                )
            }
        }
    }

    @discardableResult
    public func recordPhysicalReturn(
        _ reason: Stage3StudyPhysicalReturnReasonV1
    ) async throws -> Stage3StudyReportV1 {
        let session = try requireSession()
        return try await update(session: session) { draft in
            let value = try Stage3StudyPhysicalReturnV1(
                dayIndex: session.dayIndex,
                reason: reason
            )
            if !draft.physicalReturns.contains(value) {
                draft.physicalReturns.append(value)
            }
        }
    }

    @discardableResult
    public func completeReview(
        comprehension: Stage3StudyComprehensionV1,
        safetyIncidents: [Stage3StudySafetyIncidentV1],
        recoveryConfusions: [Stage3StudyRecoveryConfusionV1]
    ) async throws -> Stage3StudyReportV1 {
        let session = try requireSession()
        return try await update(
            session: session,
            retireSessionAfterSave: true
        ) { draft in
            draft.comprehension = comprehension
            draft.safetyReviewCompleted = true
            draft.safetyIncidents = safetyIncidents
            draft.recoveryConfusions = recoveryConfusions
        }
    }

    private func requireSession() throws -> SessionFence {
        guard let activeDayIndex, let activeSessionID else {
            throw Stage3StudyLocalCaptureErrorV1.noActiveSession
        }
        return SessionFence(id: activeSessionID, dayIndex: activeDayIndex)
    }

    private func update(
        session: SessionFence,
        retireSessionAfterSave: Bool = false,
        _ mutation: (inout Stage3StudyReportDraftV1) throws -> Void
    ) async throws -> Stage3StudyReportV1 {
        await acquireMutation()
        defer { releaseMutation() }
        guard activeSessionID == session.id,
              activeDayIndex == session.dayIndex else {
            throw Stage3StudyLocalCaptureErrorV1.noActiveSession
        }
        guard let current = try await reportOwner.currentReport() else {
            activeDayIndex = nil
            sessionStartedAtMilliseconds = nil
            activeSessionID = nil
            throw Stage3StudyLocalCaptureErrorV1.noEnrollment
        }
        var draft = Stage3StudyReportDraftV1(current)
        guard !draft.safetyReviewCompleted else {
            throw Stage3StudyLocalCaptureErrorV1.invalidTransition
        }
        try mutation(&draft)
        let report = try draft.report()
        _ = try await reportOwner.save(report)
        if retireSessionAfterSave {
            activeDayIndex = nil
            sessionStartedAtMilliseconds = nil
            activeSessionID = nil
        }
        return report
    }

    private func acquireMutation() async {
        guard mutationOwned else {
            mutationOwned = true
            return
        }
        await withCheckedContinuation { continuation in
            mutationWaiters.append(continuation)
        }
    }

    private func releaseMutation() {
        guard !mutationWaiters.isEmpty else {
            mutationOwned = false
            return
        }
        mutationWaiters.removeFirst().resume()
    }
}

private struct Stage3StudyReportDraftV1 {
    var cohortPhase: Stage3StudyCohortPhaseV1
    var studyCode: String
    var build: Stage3StudyBuildV1
    var setupAttempted: Bool
    var pairing: Stage3StudyPairingV1
    var firstFreshObserve: Stage3StudyAttemptResultV1
    var workaround: Stage3StudyWorkaroundV1
    var adaptiveJobApplicable: Bool
    var jobs: [Stage3StudyJobV1]
    var operationalEvents: [Stage3StudyOperationalEventV1]
    var controlDurations: Stage3StudyControlDurationsV1
    var routeClassesUsed: [Stage3StudyRouteClassV1]
    var timings: Stage3StudyTimingsV1
    var physicalReturns: [Stage3StudyPhysicalReturnV1]
    var comprehension: Stage3StudyComprehensionV1?
    var safetyReviewCompleted: Bool
    var safetyIncidents: [Stage3StudySafetyIncidentV1]
    var recoveryConfusions: [Stage3StudyRecoveryConfusionV1]

    init(_ report: Stage3StudyReportV1) {
        cohortPhase = report.cohortPhase
        studyCode = report.studyCode
        build = report.build
        setupAttempted = report.setupAttempted
        pairing = report.pairing
        firstFreshObserve = report.firstFreshObserve
        workaround = report.workaround
        adaptiveJobApplicable = report.adaptiveJobApplicable
        jobs = report.jobs
        operationalEvents = report.operationalEvents
        controlDurations = report.controlDurations
        routeClassesUsed = report.routeClassesUsed
        timings = report.timings
        physicalReturns = report.physicalReturns
        comprehension = report.comprehension
        safetyReviewCompleted = report.safetyReviewCompleted
        safetyIncidents = report.safetyIncidents
        recoveryConfusions = report.recoveryConfusions
    }

    func report() throws -> Stage3StudyReportV1 {
        try Stage3StudyReportV1(
            cohortPhase: cohortPhase,
            studyCode: studyCode,
            build: build,
            setupAttempted: setupAttempted,
            pairing: pairing,
            firstFreshObserve: firstFreshObserve,
            workaround: workaround,
            adaptiveJobApplicable: adaptiveJobApplicable,
            jobs: jobs,
            operationalEvents: operationalEvents,
            controlDurations: controlDurations,
            routeClassesUsed: routeClassesUsed,
            timings: timings,
            physicalReturns: physicalReturns,
            comprehension: comprehension,
            safetyReviewCompleted: safetyReviewCompleted,
            safetyIncidents: safetyIncidents,
            recoveryConfusions: recoveryConfusions
        )
    }
}

private extension Stage3StudyControlDurationsV1 {
    func adding(
        _ delta: Stage3StudyControlDurationDeltaV1
    ) throws -> Stage3StudyControlDurationsV1 {
        let desktop = desktopMilliseconds.addingReportingOverflow(
            delta.desktopMilliseconds
        )
        let application = applicationMilliseconds.addingReportingOverflow(
            delta.applicationMilliseconds
        )
        let window = windowMilliseconds.addingReportingOverflow(
            delta.windowMilliseconds
        )
        let focusedRegion = focusedRegionMilliseconds
            .addingReportingOverflow(delta.focusedRegionMilliseconds)
        guard !desktop.overflow, !application.overflow, !window.overflow,
              !focusedRegion.overflow else {
            throw Stage3StudyReportErrorV1.boundsExceeded(
                "controlDurations"
            )
        }
        return try Stage3StudyControlDurationsV1(
            desktopMilliseconds: desktop.partialValue,
            applicationMilliseconds: application.partialValue,
            windowMilliseconds: window.partialValue,
            focusedRegionMilliseconds: focusedRegion.partialValue
        )
    }
}

private extension Stage3StudyTimingsV1 {
    func replacing(
        timeToPairMilliseconds: Int64? = nil,
        timeToFirstFreshObserveMilliseconds: Int64? = nil,
        routeRecoveryMilliseconds: Int64? = nil,
        surfaceTransitionMilliseconds: Int64? = nil
    ) throws -> Stage3StudyTimingsV1 {
        try Stage3StudyTimingsV1(
            timeToPairMilliseconds:
                timeToPairMilliseconds ?? self.timeToPairMilliseconds,
            timeToFirstFreshObserveMilliseconds:
                timeToFirstFreshObserveMilliseconds
                    ?? self.timeToFirstFreshObserveMilliseconds,
            timeToFirstControllableFrameMilliseconds:
                timeToFirstControllableFrameMilliseconds,
            routeRecoveryMilliseconds:
                routeRecoveryMilliseconds ?? self.routeRecoveryMilliseconds,
            surfaceTransitionMilliseconds:
                surfaceTransitionMilliseconds
                    ?? self.surfaceTransitionMilliseconds
        )
    }
}
