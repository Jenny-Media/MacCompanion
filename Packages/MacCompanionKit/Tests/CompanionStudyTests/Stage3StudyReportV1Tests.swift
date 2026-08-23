import CompanionStudy
import Foundation
import Testing

private struct Stage3StudyFixtureManifest: Decodable {
    struct FixtureCase: Decodable {
        let path: String
        let accepted: Bool
    }

    let profile: String
    let cases: [FixtureCase]
}

@Test func studyReportFixtureCorpusFailsClosedOnProhibitedFields() throws {
    let root = Bundle.module.resourceURL!
    let manifest = try JSONDecoder().decode(
        Stage3StudyFixtureManifest.self,
        from: Data(contentsOf: root.appendingPathComponent("manifest.json"))
    )
    #expect(manifest.profile == "maccompanion.stage3.study-report-fixtures.v1")
    #expect(manifest.cases.count == 5)
    for fixture in manifest.cases {
        let data = try Data(
            contentsOf: root.appendingPathComponent(fixture.path)
        )
        if fixture.accepted {
            #expect(throws: Never.self) {
                try Stage3StudyReportCodecV1.decode(data)
            }
        } else {
            #expect(throws: (any Error).self) {
                try Stage3StudyReportCodecV1.decode(data)
            }
        }
    }
}

@Test func studyReportRoundTripsAsCanonicalContentFreeJSON() throws {
    let report = try studyReport(index: 7)
    let encoded = try Stage3StudyReportCodecV1.encode(report)
    #expect(try Stage3StudyReportCodecV1.decode(encoded) == report)
    #expect(try Stage3StudyReportCodecV1.encode(
        Stage3StudyReportCodecV1.decode(encoded)
    ) == encoded)

    let json = String(decoding: encoded, as: UTF8.self)
    for prohibited in [
        "screenTitle", "typedText", "keyCode", "pointerCoordinate",
        "clipboard", "filePath", "shellCommand", "deviceID",
        "publicKey", "token", "ipAddress", "dnsName", "email",
        "bundleIdentifier", "operationParameter",
    ] {
        #expect(!json.contains(prohibited))
    }
}

@Test func studyReportRejectsUnknownAndDuplicateJSONMembers() throws {
    let encoded = try Stage3StudyReportCodecV1.encode(
        studyReport(index: 8)
    )
    let json = String(decoding: encoded, as: UTF8.self)
    let unknown = Data(
        (String(json.dropLast()) + ",\"screenTitle\":\"secret\"}").utf8
    )
    #expect(throws: Stage3StudyReportErrorV1.self) {
        try Stage3StudyReportCodecV1.decode(unknown)
    }

    let marker = "\"schema\":\"\(Stage3StudyReportV1.schema)\""
    #expect(json.contains(marker))
    let duplicate = Data(
        (String(json.dropLast()) + ",\(marker)}").utf8
    )
    #expect(throws: (any Error).self) {
        try Stage3StudyReportCodecV1.decode(duplicate)
    }
}

@Test func studyReportRejectsInvalidIdentityBoundsAndJobShape() throws {
    #expect(throws: Stage3StudyReportErrorV1.self) {
        try Stage3StudyBuildV1(
            appVersion: "0.1-beta",
            buildNumber: "1",
            iOSMajorVersion: 26,
            macOSMajorVersion: 26
        )
    }
    #expect(throws: Stage3StudyReportErrorV1.self) {
        try Stage3StudyControlDurationsV1(
            desktopMilliseconds: -1,
            applicationMilliseconds: 0,
            windowMilliseconds: 0,
            focusedRegionMilliseconds: 0
        )
    }
    #expect(throws: Stage3StudyReportErrorV1.self) {
        try Stage3StudyJobV1(
            dayIndex: 14,
            path: .observe,
            category: .observeAvailability,
            result: .completed,
            controlWasActive: false
        )
    }
    #expect(throws: Stage3StudyReportErrorV1.self) {
        try Stage3StudyJobV1(
            dayIndex: 0,
            path: .act,
            category: .observeAvailability,
            result: .completed,
            controlWasActive: false
        )
    }
    #expect(throws: Stage3StudyReportErrorV1.self) {
        try Stage3StudyJobV1(
            dayIndex: 0,
            path: .control,
            category: .controlDevelopmentApp,
            result: .completed,
            controlWasActive: true
        )
    }
}

@Test func studyReportRejectsInconsistentAuthorityEvidence() throws {
    let build = try Stage3StudyBuildV1(
        appVersion: "0.1.0",
        buildNumber: "1",
        iOSMajorVersion: 26,
        macOSMajorVersion: 26
    )
    let timings = try Stage3StudyTimingsV1(
        timeToPairMilliseconds: 100,
        timeToFirstFreshObserveMilliseconds: 200
    )
    #expect(throws: Stage3StudyReportErrorV1.self) {
        try Stage3StudyReportV1(
            cohortPhase: .confirmatory,
            studyCode: studyCode(9),
            build: build,
            setupAttempted: true,
            pairing: Stage3StudyPairingV1(
                result: .failed,
                developerIntervention: false
            ),
            firstFreshObserve: .completed,
            workaround: .returnOrDefer,
            adaptiveJobApplicable: false,
            jobs: [],
            operationalEvents: [],
            controlDurations: Stage3StudyControlDurationsV1(
                desktopMilliseconds: 0,
                applicationMilliseconds: 0,
                windowMilliseconds: 0,
                focusedRegionMilliseconds: 0
            ),
            routeClassesUsed: [],
            timings: timings,
            physicalReturns: [],
            comprehension: nil,
            safetyReviewCompleted: false,
            safetyIncidents: [],
            recoveryConfusions: []
        )
    }
}

@Test func studyReportRejectsRemoteFactsWithoutCompletedPairing() throws {
    let base = try studyReport(index: 10)
    #expect(throws: Stage3StudyReportErrorV1.self) {
        try Stage3StudyReportV1(
            cohortPhase: base.cohortPhase,
            studyCode: base.studyCode,
            build: base.build,
            setupAttempted: true,
            pairing: Stage3StudyPairingV1(
                result: .failed,
                developerIntervention: false
            ),
            firstFreshObserve: .notCompleted,
            workaround: base.workaround,
            adaptiveJobApplicable: base.adaptiveJobApplicable,
            jobs: base.jobs,
            operationalEvents: base.operationalEvents,
            controlDurations: base.controlDurations,
            routeClassesUsed: base.routeClassesUsed,
            timings: Stage3StudyTimingsV1(),
            physicalReturns: [],
            comprehension: nil,
            safetyReviewCompleted: false,
            safetyIncidents: [],
            recoveryConfusions: []
        )
    }
}
