import CompanionStudy
import Foundation

func studyCode(_ index: Int) -> String {
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
    var value = index
    var characters = Array(repeating: Character("A"), count: 16)
    for position in stride(from: 15, through: 0, by: -1) {
        characters[position] = alphabet[value % alphabet.count]
        value /= alphabet.count
    }
    return String(characters)
}

func studyBinding(
    phase: Stage3StudyCohortPhaseV1 = .confirmatory,
    buildNumber: String = "1"
) throws -> Stage3StudyCohortBindingV1 {
    try Stage3StudyCohortBindingV1(
        cohortPhase: phase,
        appVersion: "0.1.0",
        buildNumber: buildNumber
    )
}

func studyReport(
    index: Int,
    phase: Stage3StudyCohortPhaseV1 = .confirmatory,
    buildNumber: String = "1",
    cleanPairing: Bool = true,
    useDayCount: Int = 3,
    controlRepeat: Bool = true,
    nonvisualRepeat: Bool = true,
    comprehensionCorrect: Bool = true,
    adaptiveApplicable: Bool = true,
    adaptiveRepeat: Bool = true,
    desktopMilliseconds: Int64 = 20,
    adaptiveMilliseconds: Int64 = 80,
    safetyReviewCompleted: Bool = true,
    safetyIncidents: [Stage3StudySafetyIncidentV1] = [],
    recoveryConfusions: [Stage3StudyRecoveryConfusionV1] = []
) throws -> Stage3StudyReportV1 {
    var jobs = [Stage3StudyJobV1]()
    for day in 0..<useDayCount {
        jobs.append(try Stage3StudyJobV1(
            dayIndex: day,
            path: .observe,
            category: .observeSystemHealth,
            result: .completed,
            controlWasActive: !nonvisualRepeat
        ))
    }
    if controlRepeat {
        for day in 0..<2 {
            jobs.append(try Stage3StudyJobV1(
                dayIndex: day,
                path: .control,
                category: .controlDevelopmentApp,
                result: .completed,
                controlWasActive: true,
                controlModesUsed: [
                    adaptiveRepeat ? .application : .desktop,
                ]
            ))
        }
    }

    let comprehension = Stage3StudyComprehensionV1(
        distinguishesPairedAndConnected: comprehensionCorrect,
        distinguishesViewingAndControlling: comprehensionCorrect,
        understandsApprovalRequired: comprehensionCorrect,
        understandsSeparateGrants: comprehensionCorrect
    )
    return try Stage3StudyReportV1(
        cohortPhase: phase,
        studyCode: studyCode(index),
        build: Stage3StudyBuildV1(
            appVersion: "0.1.0",
            buildNumber: buildNumber,
            iOSMajorVersion: 26,
            macOSMajorVersion: 26
        ),
        setupAttempted: true,
        pairing: Stage3StudyPairingV1(
            result: .completed,
            developerIntervention: !cleanPairing
        ),
        firstFreshObserve: .completed,
        workaround: .screenSharingOrRemoteDesktop,
        adaptiveJobApplicable: adaptiveApplicable,
        jobs: jobs,
        operationalEvents: [
            try Stage3StudyOperationalEventV1(
                dayIndex: 0,
                kind: .surfaceChange,
                initiator: .automatic,
                result: .completed
            ),
            try Stage3StudyOperationalEventV1(
                dayIndex: 0,
                kind: .stop,
                initiator: .user,
                result: .completed
            ),
        ],
        controlDurations: Stage3StudyControlDurationsV1(
            desktopMilliseconds: desktopMilliseconds,
            applicationMilliseconds: adaptiveMilliseconds,
            windowMilliseconds: 0,
            focusedRegionMilliseconds: 0
        ),
        routeClassesUsed: [.lan],
        timings: Stage3StudyTimingsV1(
            timeToPairMilliseconds: 1_000,
            timeToFirstFreshObserveMilliseconds: 2_000,
            timeToFirstControllableFrameMilliseconds: 3_000
        ),
        physicalReturns: [],
        comprehension: comprehension,
        safetyReviewCompleted: safetyReviewCompleted,
        safetyIncidents: safetyIncidents,
        recoveryConfusions: recoveryConfusions
    )
}

func studyEnrollment(
    index: Int,
    report: Stage3StudyReportV1?,
    status: Stage3StudyParticipationStatusV1 = .completed
) throws -> Stage3StudyEnrollmentV1 {
    try Stage3StudyEnrollmentV1(
        studyCode: studyCode(index),
        eligibility: .eligible,
        participationStatus: status,
        report: report
    )
}
