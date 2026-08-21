#if os(iOS)
import CompanionClientPlatform
import CompanionInteractiveClient
import SwiftUI

@available(iOS 17.0, *)
public struct ClientLiveControlSurfaceV0: UIViewRepresentable {
    @MainActor
    public final class Coordinator {
        let session: UIKitClientLiveSurfaceSessionV0

        init(session: UIKitClientLiveSurfaceSessionV0) {
            self.session = session
        }
    }

    public let session: UIKitClientLiveSurfaceSessionV0
    public let mode: ClientInputInteractionModeV0
    public let encodedWidth: UInt16
    public let encodedHeight: UInt16
    public let inputEnabled: Bool

    public init(
        session: UIKitClientLiveSurfaceSessionV0,
        mode: ClientInputInteractionModeV0,
        encodedWidth: UInt16,
        encodedHeight: UInt16,
        inputEnabled: Bool
    ) {
        self.session = session
        self.mode = mode
        self.encodedWidth = encodedWidth
        self.encodedHeight = encodedHeight
        self.inputEnabled = inputEnabled
    }

    public func makeUIView(context: Context) -> UIKitClientLiveSurfaceViewV0 {
        session.view
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    public func updateUIView(
        _ view: UIKitClientLiveSurfaceViewV0,
        context: Context
    ) {
        view.setMode(mode)
        view.setEncodedDimensions(
            width: encodedWidth,
            height: encodedHeight
        )
        view.setInputEnabled(inputEnabled)
    }

    public static func dismantleUIView(
        _ view: UIKitClientLiveSurfaceViewV0,
        coordinator: Coordinator
    ) {
        coordinator.session.interruptAndBlank()
    }
}
#endif
