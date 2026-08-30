import CompanionClientPlatform
import CompanionInteractiveClient
import Foundation
import Testing

private enum UnrelatedGestureErrorV0: Error { case failed }

@Test func inputPausedByFocusEventDropsOnlyAlreadyQueuedInput() {
    #expect(
        ClientInputSubmissionErrorPolicyV0.disposition(
            for: ClientSurfaceControlErrorV0.inputPausedByFocusEvent
        ) == .ignoreLocally
    )
    #expect(
        ClientInputSubmissionErrorPolicyV0.disposition(
            for: ClientSurfaceControlErrorV0.descriptorMismatch
        ) == .failClosed
    )
    #expect(
        ClientInputSubmissionErrorPolicyV0.disposition(
            for: UnrelatedGestureErrorV0.failed
        ) == .failClosed
    )
}

@Test func letterboxMissIsIgnoredLocally() {
    #expect(
        ClientInputGestureErrorPolicyV0.disposition(
            for: ClientViewportInputMapperErrorV0.pointOutsideContent
        ) == .ignoreLocally
    )
}

@Test func subpixelScrollThatRoundsToZeroIsIgnoredLocally() {
    #expect(
        ClientInputGestureErrorPolicyV0.disposition(
            for: ClientViewportInputMapperErrorV0.zeroScroll
        ) == .ignoreLocally
    )
}

@Test func malformedGestureStillFailsClosed() {
    #expect(
        ClientInputGestureErrorPolicyV0.disposition(
            for: ClientViewportInputMapperErrorV0.invalidGeometry
        ) == .failClosed
    )
    #expect(
        ClientInputGestureErrorPolicyV0.disposition(
            for: UnrelatedGestureErrorV0.failed
        ) == .failClosed
    )
}

@Test func visualZoomFailureResetsOnlyLocalPresentation() {
    #expect(
        ClientInputGestureErrorPolicyV0.disposition(
            for: ClientVisualZoomTransformErrorV0.invalidGeometry
        ) == .resetVisualZoomLocally
    )
    #expect(
        ClientInputGestureErrorPolicyV0.disposition(
            for: ClientVisualZoomTransformErrorV0.invalidScale
        ) == .resetVisualZoomLocally
    )
}

#if os(iOS)
@Test func twoFingerPanScrollsAtFitAndMovesTheMagnifiedViewport() {
    #expect(
        UIKitClientVisualZoomGesturePolicyV0.twoFingerPanDestination(
            visualZoomScale: 1
        ) == .remoteScroll
    )
    #expect(
        UIKitClientVisualZoomGesturePolicyV0.twoFingerPanDestination(
            visualZoomScale: 1.000_1
        ) == .remoteScroll
    )
    #expect(
        UIKitClientVisualZoomGesturePolicyV0.twoFingerPanDestination(
            visualZoomScale: 1.5
        ) == .localViewport
    )
}
#endif
