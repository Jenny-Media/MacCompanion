import CompanionInteractiveShared
import CompanionStudy
import Foundation

public enum ClientStage3StudyControlAccumulatorErrorV1:
    Error, Equatable, Sendable
{
    case invalidClock
    case alreadyActive
    case notActive
}

public struct ClientStage3StudyControlSnapshotV1: Equatable, Sendable {
    public let modesUsed: [Stage3StudyControlModeV1]
    public let durationDelta: Stage3StudyControlDurationDeltaV1
}

/// Pure monotonic accumulator for one explicitly reviewed Control job. It
/// records only closed surface kinds and aggregate active milliseconds.
public struct ClientStage3StudyControlAccumulatorV1: Sendable {
    private var modesUsed: Set<Stage3StudyControlModeV1> = []
    private var currentMode: Stage3StudyControlModeV1?
    private var currentModeStartedAtMilliseconds: Int64?
    private var desktopMilliseconds: Int64 = 0
    private var applicationMilliseconds: Int64 = 0
    private var windowMilliseconds: Int64 = 0
    private var focusedRegionMilliseconds: Int64 = 0

    public init() {}

    public mutating func resume(
        surfaceKind: InteractiveSurfaceKind,
        at monotonicMilliseconds: Int64
    ) throws {
        guard monotonicMilliseconds >= 0 else {
            throw ClientStage3StudyControlAccumulatorErrorV1.invalidClock
        }
        guard currentMode == nil,
              currentModeStartedAtMilliseconds == nil else {
            throw ClientStage3StudyControlAccumulatorErrorV1.alreadyActive
        }
        let mode = Self.studyMode(surfaceKind)
        modesUsed.insert(mode)
        currentMode = mode
        currentModeStartedAtMilliseconds = monotonicMilliseconds
    }

    public mutating func pause(
        at monotonicMilliseconds: Int64
    ) throws {
        guard let currentMode, let started = currentModeStartedAtMilliseconds
        else {
            return
        }
        guard monotonicMilliseconds >= started else {
            throw ClientStage3StudyControlAccumulatorErrorV1.invalidClock
        }
        try add(monotonicMilliseconds - started, to: currentMode)
        self.currentMode = nil
        currentModeStartedAtMilliseconds = nil
    }

    public func snapshot(
        at monotonicMilliseconds: Int64
    ) throws -> ClientStage3StudyControlSnapshotV1 {
        var copy = self
        try copy.pause(at: monotonicMilliseconds)
        guard !copy.modesUsed.isEmpty else {
            throw ClientStage3StudyControlAccumulatorErrorV1.notActive
        }
        return ClientStage3StudyControlSnapshotV1(
            modesUsed: copy.modesUsed.sorted { $0.rawValue < $1.rawValue },
            durationDelta: try Stage3StudyControlDurationDeltaV1(
                desktopMilliseconds: copy.desktopMilliseconds,
                applicationMilliseconds: copy.applicationMilliseconds,
                windowMilliseconds: copy.windowMilliseconds,
                focusedRegionMilliseconds:
                    copy.focusedRegionMilliseconds
            )
        )
    }

    private mutating func add(
        _ milliseconds: Int64,
        to mode: Stage3StudyControlModeV1
    ) throws {
        switch mode {
        case .desktop:
            desktopMilliseconds = try Self.add(
                desktopMilliseconds,
                milliseconds
            )
        case .application:
            applicationMilliseconds = try Self.add(
                applicationMilliseconds,
                milliseconds
            )
        case .window:
            windowMilliseconds = try Self.add(
                windowMilliseconds,
                milliseconds
            )
        case .focusedRegion:
            focusedRegionMilliseconds = try Self.add(
                focusedRegionMilliseconds,
                milliseconds
            )
        }
    }

    private static func add(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let value = lhs.addingReportingOverflow(rhs)
        guard !value.overflow else {
            throw ClientStage3StudyControlAccumulatorErrorV1.invalidClock
        }
        return value.partialValue
    }

    private static func studyMode(
        _ kind: InteractiveSurfaceKind
    ) -> Stage3StudyControlModeV1 {
        switch kind {
        case .desktop: .desktop
        case .application: .application
        case .window: .window
        case .focusedRegion: .focusedRegion
        }
    }
}
