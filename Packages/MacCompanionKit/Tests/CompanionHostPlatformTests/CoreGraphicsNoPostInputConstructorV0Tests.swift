import CompanionHostPlatform
import CompanionIPC
import CompanionInteractiveShared
import CompanionInteractiveWire
import CoreGraphics
import Foundation
import Testing

private struct ConstructedEventSnapshot: Equatable {
    let type: CGEventType
    let location: CGPoint
    let flags: CGEventFlags
    let virtualKeyCode: Int64
    let clickState: Int64
    let unicodeText: String
}

private final class ConstructedEventSnapshotSink:
    CoreGraphicsConstructedEventSinkV0
{
    private(set) var snapshots: [ConstructedEventSnapshot] = []

    func receiveConstructedEvent(_ event: CGEvent) throws {
        var units = [UniChar](repeating: 0, count: 4_096)
        var actualLength = 0
        units.withUnsafeMutableBufferPointer { buffer in
            event.keyboardGetUnicodeString(
                maxStringLength: buffer.count,
                actualStringLength: &actualLength,
                unicodeString: buffer.baseAddress!
            )
        }
        snapshots.append(.init(
            type: event.type,
            location: event.location,
            flags: event.flags,
            virtualKeyCode: event.getIntegerValueField(
                .keyboardEventKeycode
            ),
            clickState: event.getIntegerValueField(
                .mouseEventClickState
            ),
            unicodeText: String(
                utf16CodeUnits: units,
                count: actualLength
            )
        ))
    }
}

@Test func buttonConstructionPreservesExplicitDoubleClickState() throws {
    let sink = ConstructedEventSnapshotSink()
    let cursor = CGPoint(x: 12, y: 64)
    #expect(try CoreGraphicsNoPostInputConstructorV0().construct(
        [.button(button: .primary, transition: .down)],
        fence: constructionFence(),
        geometry: constructionGeometry(),
        currentCursorPosition: cursor,
        buttonClickState: 2,
        sink: sink
    ) == 1)
    #expect(sink.snapshots.first?.type == .leftMouseDown)
    #expect(sink.snapshots.first?.clickState == 2)
}

private let constructionBounds = CGRect(x: -100, y: 50, width: 200, height: 100)
private let constructionDisplayID = UUID(
    uuidString: "018f6700-0000-7000-8000-000000000001"
)!

private func constructionGeometry(
    displayID: UUID = constructionDisplayID,
    coordinateRevision: UInt64 = 1
) throws -> MacDisplayGeometrySnapshotV0 {
    try MacDisplayGeometrySnapshotV0(
        selectedDisplayID: displayID,
        coordinateRevision: .init(rawValue: coordinateRevision),
        logicalBounds: constructionBounds,
        backingScaleFactor: 2,
        rotation: .degrees0
    )
}

private func constructionFence(
    displayID: UUID = constructionDisplayID,
    coordinateRevision: UInt64 = 1
) -> InteractiveCommandFence {
    InteractiveCommandFence(
        leaseID: UUID(),
        hostID: UUID(),
        deviceID: UUID(),
        interactiveSessionID: UUID(),
        authorizationEpoch: .init(rawValue: 1),
        selectedDisplayID: displayID,
        surfaceID: UUID(),
        surfaceRevision: .init(rawValue: 1),
        coordinateRevision: .init(rawValue: coordinateRevision)
    )
}

@Test func normalizedPointerConstructionStaysInsideSelectedDisplay() throws {
    let sink = ConstructedEventSnapshotSink()
    let constructor = CoreGraphicsNoPostInputConstructorV0()
    #expect(try constructor.construct(
        [.pointerMove(x: 0, y: UInt16.max)],
        fence: constructionFence(),
        geometry: constructionGeometry(),
        currentCursorPosition: .zero,
        sink: sink
    ) == 1)
    let snapshot = try #require(sink.snapshots.first)
    #expect(snapshot.type == .mouseMoved)
    #expect(snapshot.location.x == constructionBounds.minX)
    #expect(snapshot.location.y < constructionBounds.maxY)
    #expect(snapshot.location.y > constructionBounds.maxY - 0.001)
}

@Test func buttonsScrollAndKeyFlagsConstructWithoutPosting() throws {
    let sink = ConstructedEventSnapshotSink()
    let cursor = CGPoint(x: 12, y: 64)
    let descriptions: [MacInteractiveInputEventV0] = [
        .button(button: .secondary, transition: .down),
        .scroll(unit: .pixel, deltaX: 4, deltaY: -5),
        .key(
            virtualKeyCode: 0,
            transition: .down,
            modifiers: [.leftShift, .rightCommand]
        ),
        .key(
            virtualKeyCode: 56,
            transition: .down,
            modifiers: [.leftShift]
        ),
    ]
    #expect(try CoreGraphicsNoPostInputConstructorV0().construct(
        descriptions,
        fence: constructionFence(),
        geometry: constructionGeometry(),
        currentCursorPosition: cursor,
        sink: sink
    ) == 4)
    #expect(sink.snapshots[0].type == .rightMouseDown)
    #expect(sink.snapshots[0].location == cursor)
    #expect(sink.snapshots[1].type == .scrollWheel)
    #expect(sink.snapshots[2].type == .keyDown)
    #expect(sink.snapshots[2].virtualKeyCode == 0)
    #expect(sink.snapshots[2].flags.contains(.maskShift))
    #expect(sink.snapshots[2].flags.contains(.maskCommand))
    #expect(sink.snapshots[3].type == .flagsChanged)
}

@Test func unicodeConstructionUsesPairedEventsAndNoClipboard() throws {
    let sink = ConstructedEventSnapshotSink()
    #expect(try CoreGraphicsNoPostInputConstructorV0().construct(
        [.unicodeText("Hi 👋")],
        fence: constructionFence(),
        geometry: constructionGeometry(),
        currentCursorPosition: .zero,
        sink: sink
    ) == 2)
    #expect(sink.snapshots.map(\.type) == [.keyDown, .keyUp])
    #expect(sink.snapshots.map(\.unicodeText) == ["Hi 👋", "Hi 👋"])
}

@Test func staleGeometryFenceCreatesNoEvent() throws {
    let sink = ConstructedEventSnapshotSink()
    #expect(throws: CoreGraphicsInputConstructionErrorV0.geometryFenceMismatch) {
        try CoreGraphicsNoPostInputConstructorV0().construct(
            [.pointerMove(x: 1, y: 1)],
            fence: constructionFence(coordinateRevision: 2),
            geometry: constructionGeometry(coordinateRevision: 1),
            currentCursorPosition: .zero,
            sink: sink
        )
    }
    #expect(sink.snapshots.isEmpty)
}

@Test func geometryRejectsZeroRevisionScaleAndUnboundedOrigins() {
    #expect(throws: CoreGraphicsInputConstructionErrorV0.invalidDisplayBounds) {
        try MacDisplayGeometrySnapshotV0(
            selectedDisplayID: constructionDisplayID,
            coordinateRevision: .init(rawValue: 0),
            logicalBounds: constructionBounds,
            backingScaleFactor: 2,
            rotation: .degrees0
        )
    }
    #expect(throws: CoreGraphicsInputConstructionErrorV0.invalidDisplayBounds) {
        try MacDisplayGeometrySnapshotV0(
            selectedDisplayID: constructionDisplayID,
            coordinateRevision: .init(rawValue: 1),
            logicalBounds: CGRect(
                x: 200_000,
                y: 0,
                width: 100,
                height: 100
            ),
            backingScaleFactor: 0,
            rotation: .degrees90
        )
    }
}

@Test func pointerThenButtonUsesTheNewSelectedDisplayPosition() throws {
    let sink = ConstructedEventSnapshotSink()
    #expect(try CoreGraphicsNoPostInputConstructorV0().construct(
        [
            .pointerMove(x: UInt16.max / 2, y: UInt16.max / 2),
            .button(button: .primary, transition: .down),
        ],
        fence: constructionFence(),
        geometry: constructionGeometry(),
        currentCursorPosition: CGPoint(x: 1_000, y: 1_000),
        sink: sink
    ) == 2)
    #expect(sink.snapshots[0].type == .mouseMoved)
    #expect(sink.snapshots[1].type == .leftMouseDown)
    #expect(sink.snapshots[1].location == sink.snapshots[0].location)
}

@Test func buttonOutsideSelectedDisplayCreatesNoPartialEvent() throws {
    let sink = ConstructedEventSnapshotSink()
    #expect(
        throws: CoreGraphicsInputConstructionErrorV0
            .cursorOutsideSelectedDisplay
    ) {
        try CoreGraphicsNoPostInputConstructorV0().construct(
            [.button(button: .primary, transition: .down)],
            fence: constructionFence(),
            geometry: constructionGeometry(),
            currentCursorPosition: CGPoint(x: 1_000, y: 1_000),
            sink: sink
        )
    }
    #expect(sink.snapshots.isEmpty)
}
