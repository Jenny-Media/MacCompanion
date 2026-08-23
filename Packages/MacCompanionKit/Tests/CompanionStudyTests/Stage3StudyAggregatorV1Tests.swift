import CompanionStudy
import Testing

@Test func confirmatoryCohortPassesOnlyWhenEveryPreregisteredGatePasses()
throws {
    let enrollments = try (0..<15).map {
        try studyEnrollment(index: $0, report: studyReport(index: $0))
    }
    let result = try Stage3StudyAggregatorV1.aggregate(
        binding: studyBinding(),
        enrollments: enrollments
    )
    #expect(result.decision == .passed)
    #expect(result.eligibleCount == 15)
    #expect(result.activatedCount == 15)
    #expect(result.cleanPairing.status == .passed)
    #expect(result.repeatedRealValue.status == .passed)
    #expect(result.repeatedControl.denominator == 15)
    #expect(result.adaptiveDuration.status == .passed)
    #expect(result.safety == .passed)
}

@Test func exactPairingAndRepeatValuePercentagesUseIntegerFractions()
throws {
    let binding = try studyBinding()
    let exactPairing = try (0..<15).map { index in
        try studyEnrollment(
            index: index,
            report: studyReport(index: index, cleanPairing: index < 12)
        )
    }
    let pairingResult = try Stage3StudyAggregatorV1.aggregate(
        binding: binding,
        enrollments: exactPairing
    )
    #expect(pairingResult.cleanPairing.successes == 12)
    #expect(pairingResult.cleanPairing.status == .passed)

    let repeatBoundary = try (0..<15).map { index in
        try studyEnrollment(
            index: index,
            report: studyReport(
                index: index,
                useDayCount: index < 9 ? 3 : 1
            )
        )
    }
    let repeatResult = try Stage3StudyAggregatorV1.aggregate(
        binding: binding,
        enrollments: repeatBoundary
    )
    #expect(repeatResult.repeatedRealValue.successes == 9)
    #expect(repeatResult.repeatedRealValue.status == .passed)

    var belowPairing = exactPairing
    belowPairing[11] = try studyEnrollment(
        index: 11,
        report: studyReport(index: 11, cleanPairing: false)
    )
    #expect(try Stage3StudyAggregatorV1.aggregate(
        binding: binding,
        enrollments: belowPairing
    ).decision == .failed)
}

@Test func incompleteOrUndersizedConfirmatoryEvidenceIsInconclusive()
throws {
    let binding = try studyBinding()
    let fourteen = try (0..<14).map {
        try studyEnrollment(index: $0, report: studyReport(index: $0))
    }
    #expect(try Stage3StudyAggregatorV1.aggregate(
        binding: binding,
        enrollments: fourteen
    ).decision == .inconclusive)

    var missing = try (0..<15).map {
        try studyEnrollment(index: $0, report: studyReport(index: $0))
    }
    missing[0] = try studyEnrollment(
        index: 0,
        report: nil,
        status: .withdrew
    )
    let missingResult = try Stage3StudyAggregatorV1.aggregate(
        binding: binding,
        enrollments: missing
    )
    #expect(missingResult.decision == .inconclusive)
    #expect(missingResult.cleanPairing.successes == 14)
    #expect(missingResult.cleanPairing.denominator == 15)
    #expect(missingResult.comprehension.denominator == 15)
    #expect(missingResult.withdrawnEligibleCount == 1)
}

@Test func safetyAndRecurringRecoveryConfusionOverrideEngagement()
throws {
    let binding = try studyBinding()
    var safety = try (0..<15).map {
        try studyEnrollment(index: $0, report: studyReport(index: $0))
    }
    safety[0] = try studyEnrollment(
        index: 0,
        report: studyReport(
            index: 0,
            safetyIncidents: [.localStopOrRevocationFailure]
        )
    )
    #expect(try Stage3StudyAggregatorV1.aggregate(
        binding: binding,
        enrollments: safety
    ).decision == .failed)

    var confusion = try (0..<15).map {
        try studyEnrollment(index: $0, report: studyReport(index: $0))
    }
    for index in 0..<2 {
        confusion[index] = try studyEnrollment(
            index: index,
            report: studyReport(
                index: index,
                recoveryConfusions: [.stalePresentedAsFresh]
            )
        )
    }
    let confusionResult = try Stage3StudyAggregatorV1.aggregate(
        binding: binding,
        enrollments: confusion
    )
    #expect(confusionResult.truthfulRecovery == .failed)
    #expect(confusionResult.decision == .failed)
}

@Test func adaptiveGateIsStrictAndRequiresApplicableEvidence() throws {
    let binding = try studyBinding()
    let exactlyEighty = try (0..<15).map { index in
        try studyEnrollment(
            index: index,
            report: studyReport(
                index: index,
                desktopMilliseconds: 80,
                adaptiveMilliseconds: 20
            )
        )
    }
    let durationResult = try Stage3StudyAggregatorV1.aggregate(
        binding: binding,
        enrollments: exactlyEighty
    )
    #expect(durationResult.adaptiveDuration.status == .failed)
    #expect(durationResult.decision == .failed)

    let notApplicable = try (0..<15).map { index in
        try studyEnrollment(
            index: index,
            report: studyReport(
                index: index,
                adaptiveApplicable: false,
                adaptiveRepeat: false,
                desktopMilliseconds: 100,
                adaptiveMilliseconds: 0
            )
        )
    }
    let applicableResult = try Stage3StudyAggregatorV1.aggregate(
        binding: binding,
        enrollments: notApplicable
    )
    #expect(applicableResult.adaptiveRepeat.status == .notApplicable)
    #expect(applicableResult.decision == .inconclusive)
}

@Test func calibrationCannotPassAndCohortInputsCannotBePooled() throws {
    let calibration = try (0..<15).map { index in
        try studyEnrollment(
            index: index,
            report: studyReport(index: index, phase: .calibration)
        )
    }
    #expect(try Stage3StudyAggregatorV1.aggregate(
        binding: studyBinding(phase: .calibration),
        enrollments: calibration
    ).decision == .calibrationOnly)

    let wrongBuild = try studyEnrollment(
        index: 100,
        report: studyReport(index: 100, buildNumber: "2")
    )
    #expect(throws: Stage3StudyAggregationErrorV1.self) {
        try Stage3StudyAggregatorV1.aggregate(
            binding: studyBinding(),
            enrollments: [wrongBuild]
        )
    }

    let duplicate = try studyEnrollment(
        index: 101,
        report: studyReport(index: 101)
    )
    #expect(throws: Stage3StudyAggregationErrorV1.self) {
        try Stage3StudyAggregatorV1.aggregate(
            binding: studyBinding(),
            enrollments: [duplicate, duplicate]
        )
    }
}
