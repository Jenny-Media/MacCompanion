import Foundation

public enum Stage3StudyIneligibilityReasonV1:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case unsupportedHardwareOrOS
    case noPersonallyControlledMac
    case cannotInstallCandidate
}

public enum Stage3StudyEligibilityV1: Equatable, Hashable, Sendable {
    case eligible
    case ineligible(Stage3StudyIneligibilityReasonV1)
}

public enum Stage3StudyParticipationStatusV1:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case participating
    case withdrew
    case completed
}

public struct Stage3StudyEnrollmentV1: Equatable, Sendable {
    public let studyCode: String
    public let eligibility: Stage3StudyEligibilityV1
    public let participationStatus: Stage3StudyParticipationStatusV1
    public let report: Stage3StudyReportV1?

    public init(
        studyCode: String,
        eligibility: Stage3StudyEligibilityV1,
        participationStatus: Stage3StudyParticipationStatusV1,
        report: Stage3StudyReportV1?
    ) throws {
        guard Stage3StudyRulesV1.isStudyCode(studyCode) else {
            throw Stage3StudyAggregationErrorV1.invalidEnrollment(
                "studyCode"
            )
        }
        if case .ineligible = eligibility, report != nil {
            throw Stage3StudyAggregationErrorV1.invalidEnrollment(
                "ineligibleReport"
            )
        }
        guard report?.studyCode == nil || report?.studyCode == studyCode else {
            throw Stage3StudyAggregationErrorV1.invalidEnrollment(
                "reportStudyCode"
            )
        }
        self.studyCode = studyCode
        self.eligibility = eligibility
        self.participationStatus = participationStatus
        self.report = report
    }
}

public struct Stage3StudyCohortBindingV1: Equatable, Sendable {
    public let cohortPhase: Stage3StudyCohortPhaseV1
    public let appVersion: String
    public let buildNumber: String
    public let protocolVersion: String
    public let reportSchema: String
    public let adrRevision: String

    public init(
        cohortPhase: Stage3StudyCohortPhaseV1,
        appVersion: String,
        buildNumber: String,
        protocolVersion: String = "0.1",
        reportSchema: String = Stage3StudyReportV1.schema,
        adrRevision: String = Stage3StudyReportV1.adrRevision
    ) throws {
        guard Stage3StudyRulesV1.isVersion(appVersion) else {
            throw Stage3StudyAggregationErrorV1.invalidBinding(
                "appVersion"
            )
        }
        guard Stage3StudyRulesV1.isBuildNumber(buildNumber) else {
            throw Stage3StudyAggregationErrorV1.invalidBinding(
                "buildNumber"
            )
        }
        guard protocolVersion == "0.1" else {
            throw Stage3StudyAggregationErrorV1.invalidBinding(
                "protocolVersion"
            )
        }
        guard reportSchema == Stage3StudyReportV1.schema else {
            throw Stage3StudyAggregationErrorV1.invalidBinding(
                "reportSchema"
            )
        }
        guard adrRevision == Stage3StudyReportV1.adrRevision else {
            throw Stage3StudyAggregationErrorV1.invalidBinding(
                "adrRevision"
            )
        }
        self.cohortPhase = cohortPhase
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.protocolVersion = protocolVersion
        self.reportSchema = reportSchema
        self.adrRevision = adrRevision
    }

    fileprivate func accepts(_ report: Stage3StudyReportV1) -> Bool {
        report.cohortPhase == cohortPhase
            && report.build.appVersion == appVersion
            && report.build.buildNumber == buildNumber
            && report.build.protocolVersion == protocolVersion
    }
}

public enum Stage3StudyGateStatusV1: String, Equatable, Sendable {
    case passed
    case failed
    case notProven
    case notApplicable
}

public enum Stage3StudyThresholdV1: Equatable, Sendable {
    case atLeastCount(Int)
    case atLeastPercent(Int)
}

public struct Stage3StudyMetricV1: Equatable, Sendable {
    public let successes: Int
    public let denominator: Int
    public let threshold: Stage3StudyThresholdV1
    public let status: Stage3StudyGateStatusV1
}

public struct Stage3StudyAdaptiveDurationMetricV1: Equatable, Sendable {
    public let desktopMilliseconds: Int64
    public let totalMilliseconds: Int64
    public let status: Stage3StudyGateStatusV1
}

public enum Stage3StudyDecisionV1: String, Equatable, Sendable {
    case dogfoodOnly
    case calibrationOnly
    case passed
    case failed
    case inconclusive
}

public struct Stage3StudyAggregationV1: Equatable, Sendable {
    public let decision: Stage3StudyDecisionV1
    public let enrolledCount: Int
    public let eligibleCount: Int
    public let withdrawnEligibleCount: Int
    public let receivedEligibleReportCount: Int
    public let activatedCount: Int
    public let cleanPairing: Stage3StudyMetricV1
    public let repeatedRealValue: Stage3StudyMetricV1
    public let repeatedControl: Stage3StudyMetricV1
    public let repeatedNonvisualValue: Stage3StudyMetricV1
    public let comprehension: Stage3StudyMetricV1
    public let adaptiveRepeat: Stage3StudyMetricV1
    public let adaptiveDuration: Stage3StudyAdaptiveDurationMetricV1
    public let safety: Stage3StudyGateStatusV1
    public let truthfulRecovery: Stage3StudyGateStatusV1
}

public enum Stage3StudyAggregationErrorV1: Error, Equatable, Sendable {
    case invalidBinding(String)
    case invalidEnrollment(String)
    case tooManyEnrollments
    case duplicateStudyCode(String)
    case cohortBindingMismatch(String)
}

public enum Stage3StudyAggregatorV1 {
    public static let minimumConfirmatoryEligibleCount = 15
    public static let maximumEnrollmentCount = 128

    public static func aggregate(
        binding: Stage3StudyCohortBindingV1,
        enrollments: [Stage3StudyEnrollmentV1]
    ) throws -> Stage3StudyAggregationV1 {
        guard enrollments.count <= maximumEnrollmentCount else {
            throw Stage3StudyAggregationErrorV1.tooManyEnrollments
        }
        var seenCodes = Set<String>()
        for enrollment in enrollments {
            guard seenCodes.insert(enrollment.studyCode).inserted else {
                throw Stage3StudyAggregationErrorV1.duplicateStudyCode(
                    enrollment.studyCode
                )
            }
            if let report = enrollment.report,
               !binding.accepts(report) {
                throw Stage3StudyAggregationErrorV1.cohortBindingMismatch(
                    enrollment.studyCode
                )
            }
            if enrollment.eligibility == .eligible,
               let report = enrollment.report,
               !report.setupAttempted {
                throw Stage3StudyAggregationErrorV1.invalidEnrollment(
                    "eligibleSetupNotAttempted"
                )
            }
        }

        let eligible = enrollments.filter { enrollment in
            enrollment.eligibility == .eligible
        }
        let reports = eligible.compactMap(\.report)
        let activated = reports.filter(\.isActivated)

        let cleanPairingCount = reports.count {
            $0.setupAttempted && $0.pairing.completedWithoutIntervention
        }
        let repeatedValueCount = activated.count {
            completedDays(in: $0.jobs).count >= 3
        }
        let repeatedControlCount = activated.count {
            completedDays(in: $0.jobs, path: .control).count >= 2
        }
        let repeatedNonvisualCount = activated.count { report in
            let days = Set(report.jobs.compactMap { job -> Int? in
                guard job.isCompletedRealJob,
                      job.path == .observe || job.path == .act,
                      !job.controlWasActive else { return nil }
                return job.dayIndex
            })
            return days.count >= 2
        }
        let comprehensionCount = reports.count {
            $0.comprehension?.isCorrect == true
        }
        let adaptiveRepeatCount = activated.count { report in
            let days = Set(report.jobs.compactMap { job -> Int? in
                guard job.isCompletedRealJob,
                      job.path == .control,
                      job.usedAdaptiveMode else { return nil }
                return job.dayIndex
            })
            return days.count >= 2
        }

        let desktopMilliseconds = reports.reduce(Int64(0)) {
            $0 + $1.controlDurations.desktopMilliseconds
        }
        let totalMilliseconds = reports.reduce(Int64(0)) {
            $0 + $1.controlDurations.totalMilliseconds
        }
        let anyAdaptiveApplicable = reports.contains {
            $0.adaptiveJobApplicable
        }
        let allEvidencePresent = reports.count == eligible.count
        let allSafetyReviewed = allEvidencePresent && reports.allSatisfy {
            $0.safetyReviewCompleted
        }
        let hasSafetyIncident = reports.contains {
            !$0.safetyIncidents.isEmpty
        }
        let hasRecurringRecoveryConfusion = recurringRecoveryConfusion(
            in: reports
        )

        let cleanPairing = fractionMetric(
            successes: cleanPairingCount,
            denominator: eligible.count,
            minimumPercent: 80
        )
        let repeatedRealValue = fractionMetric(
            successes: repeatedValueCount,
            denominator: activated.count,
            minimumPercent: 60
        )
        let repeatedControl = countMetric(
            successes: repeatedControlCount,
            denominator: activated.count,
            minimum: 5
        )
        let repeatedNonvisualValue = countMetric(
            successes: repeatedNonvisualCount,
            denominator: activated.count,
            minimum: 3
        )
        let comprehension = fractionMetric(
            successes: comprehensionCount,
            denominator: eligible.count,
            minimumPercent: 80
        )
        let adaptiveRepeat = countMetric(
            successes: adaptiveRepeatCount,
            denominator: activated.count,
            minimum: 3,
            applicable: anyAdaptiveApplicable
        )
        let adaptiveDuration = Stage3StudyAdaptiveDurationMetricV1(
            desktopMilliseconds: desktopMilliseconds,
            totalMilliseconds: totalMilliseconds,
            status: adaptiveDurationStatus(
                desktopMilliseconds: desktopMilliseconds,
                totalMilliseconds: totalMilliseconds,
                applicable: anyAdaptiveApplicable
            )
        )
        let safety: Stage3StudyGateStatusV1 = hasSafetyIncident
            ? .failed
            : (allSafetyReviewed ? .passed : .notProven)
        let truthfulRecovery: Stage3StudyGateStatusV1 =
            hasRecurringRecoveryConfusion ? .failed : .passed

        let statuses = [
            cleanPairing.status,
            repeatedRealValue.status,
            repeatedControl.status,
            repeatedNonvisualValue.status,
            comprehension.status,
            adaptiveRepeat.status,
            adaptiveDuration.status,
            safety,
            truthfulRecovery,
        ]
        let decision: Stage3StudyDecisionV1
        switch binding.cohortPhase {
        case .dogfood:
            decision = .dogfoodOnly
        case .calibration:
            decision = .calibrationOnly
        case .confirmatory:
            if hasSafetyIncident || hasRecurringRecoveryConfusion {
                decision = .failed
            } else if eligible.count < minimumConfirmatoryEligibleCount
                || !allEvidencePresent
                || !allSafetyReviewed
                || !anyAdaptiveApplicable {
                decision = .inconclusive
            } else if statuses.contains(.failed) {
                decision = .failed
            } else if statuses.allSatisfy({ $0 == .passed }) {
                decision = .passed
            } else {
                decision = .inconclusive
            }
        }

        return Stage3StudyAggregationV1(
            decision: decision,
            enrolledCount: enrollments.count,
            eligibleCount: eligible.count,
            withdrawnEligibleCount: eligible.count {
                $0.participationStatus == .withdrew
            },
            receivedEligibleReportCount: reports.count,
            activatedCount: activated.count,
            cleanPairing: cleanPairing,
            repeatedRealValue: repeatedRealValue,
            repeatedControl: repeatedControl,
            repeatedNonvisualValue: repeatedNonvisualValue,
            comprehension: comprehension,
            adaptiveRepeat: adaptiveRepeat,
            adaptiveDuration: adaptiveDuration,
            safety: safety,
            truthfulRecovery: truthfulRecovery
        )
    }

    private static func completedDays(
        in jobs: [Stage3StudyJobV1],
        path: Stage3StudyPathV1? = nil
    ) -> Set<Int> {
        Set(jobs.compactMap { job in
            guard job.isCompletedRealJob,
                  path == nil || job.path == path else { return nil }
            return job.dayIndex
        })
    }

    private static func fractionMetric(
        successes: Int,
        denominator: Int,
        minimumPercent: Int
    ) -> Stage3StudyMetricV1 {
        let passed = denominator > 0
            && successes * 100 >= minimumPercent * denominator
        return Stage3StudyMetricV1(
            successes: successes,
            denominator: denominator,
            threshold: .atLeastPercent(minimumPercent),
            status: passed ? .passed : .failed
        )
    }

    private static func countMetric(
        successes: Int,
        denominator: Int,
        minimum: Int,
        applicable: Bool = true
    ) -> Stage3StudyMetricV1 {
        Stage3StudyMetricV1(
            successes: successes,
            denominator: denominator,
            threshold: .atLeastCount(minimum),
            status: applicable
                ? (successes >= minimum ? .passed : .failed)
                : .notApplicable
        )
    }

    private static func adaptiveDurationStatus(
        desktopMilliseconds: Int64,
        totalMilliseconds: Int64,
        applicable: Bool
    ) -> Stage3StudyGateStatusV1 {
        guard applicable else { return .notApplicable }
        guard totalMilliseconds > 0 else { return .failed }
        return desktopMilliseconds * 100 < totalMilliseconds * 80
            ? .passed
            : .failed
    }

    private static func recurringRecoveryConfusion(
        in reports: [Stage3StudyReportV1]
    ) -> Bool {
        var occurrenceCounts: [Stage3StudyRecoveryConfusionV1: Int] = [:]
        for report in reports {
            for confusion in Set(report.recoveryConfusions) {
                occurrenceCounts[confusion, default: 0] += 1
            }
        }
        return occurrenceCounts.values.contains { $0 >= 2 }
    }
}
