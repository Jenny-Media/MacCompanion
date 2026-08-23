@testable import CompanionClientUI
import CompanionInteractiveShared
import CompanionStudy
import Testing

@Test func studyControlAccumulatorTracksOnlyActiveClosedSurfaceDurations()
throws {
    var accumulator = ClientStage3StudyControlAccumulatorV1()
    try accumulator.resume(surfaceKind: .desktop, at: 100)
    try accumulator.pause(at: 250)
    try accumulator.resume(surfaceKind: .application, at: 300)
    let snapshot = try accumulator.snapshot(at: 500)

    #expect(snapshot.modesUsed == [.application, .desktop])
    #expect(snapshot.durationDelta.desktopMilliseconds == 150)
    #expect(snapshot.durationDelta.applicationMilliseconds == 200)
    #expect(snapshot.durationDelta.windowMilliseconds == 0)
    #expect(snapshot.durationDelta.focusedRegionMilliseconds == 0)
}

@Test func studyControlAccumulatorRejectsClockRegressionAndDoubleResume()
throws {
    var accumulator = ClientStage3StudyControlAccumulatorV1()
    try accumulator.resume(surfaceKind: .window, at: 100)
    #expect(throws: ClientStage3StudyControlAccumulatorErrorV1.alreadyActive) {
        try accumulator.resume(surfaceKind: .desktop, at: 101)
    }
    #expect(throws: ClientStage3StudyControlAccumulatorErrorV1.invalidClock) {
        try accumulator.pause(at: 99)
    }

    let empty = ClientStage3StudyControlAccumulatorV1()
    #expect(throws: ClientStage3StudyControlAccumulatorErrorV1.notActive) {
        try empty.snapshot(at: 1)
    }
}
