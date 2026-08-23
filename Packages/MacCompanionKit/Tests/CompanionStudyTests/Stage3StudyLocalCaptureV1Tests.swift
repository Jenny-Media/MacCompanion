import CompanionStudy
import Foundation
import Testing

private func makeLocalCapture() throws -> (
    URL,
    Stage3StudyLocalReportOwnerV1,
    Stage3StudyLocalCaptureV1
) {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "maccompanion-study-capture-tests-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    let store = try AtomicFileStage3StudyReportStoreV1(
        directory: directory
    )
    let owner = Stage3StudyLocalReportOwnerV1(persistence: store)
    return (
        directory,
        owner,
        Stage3StudyLocalCaptureV1(reportOwner: owner)
    )
}

private func studyEnrollment(
    index: Int,
    adaptiveJobApplicable: Bool = true
) throws -> Stage3StudyLocalEnrollmentV1 {
    Stage3StudyLocalEnrollmentV1(
        cohortPhase: .dogfood,
        studyCode: studyCode(index),
        build: try Stage3StudyBuildV1(
            appVersion: "0.1.0",
            buildNumber: "1",
            iOSMajorVersion: 27,
            macOSMajorVersion: 27
        ),
        workaround: .screenSharingOrRemoteDesktop,
        adaptiveJobApplicable: adaptiveJobApplicable
    )
}

@Test func localCaptureRequiresExplicitEnrollmentAndSession() async throws {
    let (directory, owner, capture) = try makeLocalCapture()
    defer { try? FileManager.default.removeItem(at: directory) }

    await #expect(
        throws: Stage3StudyLocalCaptureErrorV1.noEnrollment
    ) {
        try await capture.beginSession(dayIndex: 0)
    }
    let enrolled = try await capture.enroll(studyEnrollment(index: 300))
    #expect(enrolled.setupAttempted == false)
    #expect(enrolled.pairing.result == .notAttempted)
    #expect(enrolled.jobs.isEmpty)
    #expect(try await owner.currentReport() == enrolled)

    await #expect(
        throws: Stage3StudyLocalCaptureErrorV1.noActiveSession
    ) {
        try await capture.recordSetupAttempted()
    }
    await #expect(
        throws: Stage3StudyLocalCaptureErrorV1.invalidDayIndex
    ) {
        try await capture.beginSession(dayIndex: 14)
    }
    try await capture.beginSession(dayIndex: 0)
    await #expect(
        throws: Stage3StudyLocalCaptureErrorV1.sessionAlreadyActive
    ) {
        try await capture.beginSession(dayIndex: 1)
    }
    await capture.endSession()
    #expect(await capture.currentSessionDayIndex() == nil)
}

@Test func localCaptureRecordsOnlySubmittedClosedProductFacts()
async throws {
    let (directory, owner, capture) = try makeLocalCapture()
    defer { try? FileManager.default.removeItem(at: directory) }
    _ = try await capture.enroll(studyEnrollment(index: 301))
    try await capture.beginSession(dayIndex: 2)

    _ = try await capture.recordSetupAttempted()
    _ = try await capture.recordPairingResult(
        .failed,
        developerIntervention: false
    )
    _ = try await capture.recordPairingResult(
        .completed,
        developerIntervention: false,
        durationMilliseconds: 1_200
    )
    _ = try await capture.recordOperationalEvent(
        kind: .route,
        initiator: .user,
        result: .completed
    )
    _ = try await capture.recordRouteClass(.lan)
    _ = try await capture.recordFirstFreshObserve(
        .completed,
        durationMilliseconds: 250
    )
    _ = try await capture.recordJob(
        path: .observe,
        category: .observeSystemHealth,
        result: .completed
    )
    _ = try await capture.recordJob(
        path: .control,
        category: .controlDevelopmentApp,
        result: .completed,
        controlModesUsed: [.desktop, .application],
        controlDurationDelta: try Stage3StudyControlDurationDeltaV1(
            desktopMilliseconds: 4_000,
            applicationMilliseconds: 6_000
        )
    )
    _ = try await capture.recordTiming(
        .surfaceTransition,
        milliseconds: 300
    )
    _ = try await capture.recordPhysicalReturn(.dialog)
    let comprehension = Stage3StudyComprehensionV1(
        distinguishesPairedAndConnected: true,
        distinguishesViewingAndControlling: true,
        understandsApprovalRequired: true,
        understandsSeparateGrants: true
    )
    let final = try await capture.completeReview(
        comprehension: comprehension,
        safetyIncidents: [],
        recoveryConfusions: []
    )

    #expect(final.pairing.completedWithoutIntervention)
    #expect(final.timings.timeToPairMilliseconds == 1_200)
    #expect(final.timings.timeToFirstFreshObserveMilliseconds == 250)
    #expect(final.timings.surfaceTransitionMilliseconds == 300)
    #expect(final.routeClassesUsed == [.lan])
    #expect(final.jobs.count == 2)
    #expect(final.jobs.allSatisfy { $0.dayIndex == 2 })
    #expect(final.controlDurations.desktopMilliseconds == 4_000)
    #expect(final.controlDurations.applicationMilliseconds == 6_000)
    #expect(final.physicalReturns == [
        try Stage3StudyPhysicalReturnV1(dayIndex: 2, reason: .dialog),
    ])
    #expect(final.safetyReviewCompleted)
    #expect(final.comprehension?.isCorrect == true)
    #expect(try await owner.currentReport() == final)
    await #expect(
        throws: Stage3StudyLocalCaptureErrorV1.invalidTransition
    ) {
        try await capture.recordOperationalEvent(
            kind: .recovery,
            initiator: .user,
            result: .completed
        )
    }
    #expect(try await owner.currentReport() == final)

    let json = String(
        decoding: try Stage3StudyReportCodecV1.encode(final),
        as: UTF8.self
    )
    #expect(!json.contains("hostID"))
    #expect(!json.contains("screenTitle"))
    #expect(!json.contains("endpoint"))
}

@Test func localCaptureRejectsControlDurationOverflowWithoutMutation()
async throws {
    let (directory, owner, capture) = try makeLocalCapture()
    defer { try? FileManager.default.removeItem(at: directory) }
    _ = try await capture.enroll(studyEnrollment(index: 305))
    try await capture.beginSession(dayIndex: 0)
    _ = try await capture.recordSetupAttempted()
    _ = try await capture.recordPairingResult(
        .completed,
        developerIntervention: false,
        durationMilliseconds: 1
    )
    _ = try await capture.recordJob(
        path: .control,
        category: .controlDevelopmentApp,
        result: .completed,
        controlModesUsed: [.desktop],
        controlDurationDelta: try Stage3StudyControlDurationDeltaV1(
            desktopMilliseconds: 14 * 24 * 60 * 60 * 1_000
        )
    )
    let before = try #require(await owner.currentReport())

    await #expect(throws: Stage3StudyReportErrorV1.self) {
        try await capture.recordJob(
            path: .control,
            category: .controlOtherOwnedApp,
            result: .completed,
            controlModesUsed: [.desktop],
            controlDurationDelta: try Stage3StudyControlDurationDeltaV1(
                desktopMilliseconds: 1
            )
        )
    }
    #expect(try await owner.currentReport() == before)
}

@Test func localCaptureRejectsInvalidAuthorityTransitionsWithoutMutation()
async throws {
    let (directory, owner, capture) = try makeLocalCapture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let enrolled = try await capture.enroll(studyEnrollment(index: 302))
    try await capture.beginSession(dayIndex: 0)

    await #expect(
        throws: Stage3StudyLocalCaptureErrorV1.invalidTransition
    ) {
        try await capture.recordPairingResult(
            .completed,
            developerIntervention: false
        )
    }
    await #expect(
        throws: Stage3StudyLocalCaptureErrorV1.invalidTransition
    ) {
        try await capture.recordRouteClass(.privateNetwork)
    }
    await #expect(
        throws: Stage3StudyLocalCaptureErrorV1.invalidTransition
    ) {
        try await capture.recordJob(
            path: .observe,
            category: .observeAvailability,
            result: .completed,
            controlDurationDelta:
                try Stage3StudyControlDurationDeltaV1(
                    desktopMilliseconds: 1
                )
        )
    }
    #expect(try await owner.currentReport() == enrolled)
}

@Test func localCaptureRefusesReplacementEnrollmentAndStopsAfterDelete()
async throws {
    let (directory, owner, capture) = try makeLocalCapture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let enrolled = try await capture.enroll(studyEnrollment(index: 303))
    await #expect(
        throws: Stage3StudyLocalCaptureErrorV1.alreadyEnrolled
    ) {
        try await capture.enroll(studyEnrollment(index: 304))
    }
    try await capture.beginSession(dayIndex: 1)
    #expect(try await owner.deleteAfterExplicitRequest(
        studyCode: enrolled.studyCode
    ) == .deleted)
    await #expect(
        throws: Stage3StudyLocalCaptureErrorV1.noEnrollment
    ) {
        try await capture.recordOperationalEvent(
            kind: .connection,
            initiator: .system,
            result: .failed
        )
    }
    #expect(await capture.currentSessionDayIndex() == nil)
}
