#if os(iOS)
import UIKit
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionClientNetworkPlatform

/// An admitted adapter prepares native transport under the normal Control
/// owner. Its close method must cancel pending enrollment/TLS and erase secrets.
@available(iOS 17.0, *)
@MainActor
public protocol UIKitClientNativeVideoPreparingV0: AnyObject {
    func prepare(descriptor: AdaptiveSurfaceDescriptor,
                 roles: NetworkClientInteractiveRoleProductBindingV0) async throws -> UIKitClientNativeVideoPreparationV0
    func supportsStreamContinuity() async -> Bool
    func retainStream() async throws
    func prepareReplacement(descriptor: AdaptiveSurfaceDescriptor,
        roles: NetworkClientInteractiveRoleProductBindingV0) async throws -> UIKitClientNativeVideoPreparationV0
    func close() async
}

@available(iOS 17.0, *)
public extension UIKitClientNativeVideoPreparingV0 {
    func supportsStreamContinuity() async -> Bool { false }
    func retainStream() async throws { throw InteractiveNativeVideoFailureV0.authorizationLost }
    func prepareReplacement(descriptor: AdaptiveSurfaceDescriptor,
        roles: NetworkClientInteractiveRoleProductBindingV0) async throws -> UIKitClientNativeVideoPreparationV0 {
        throw InteractiveNativeVideoFailureV0.authorizationLost
    }
}

/// Local selection preflight only; the existing Control/presentation owners
/// still own all transport and input admission.
@available(iOS 17.0, *)
@MainActor
enum UIKitClientNativeSurfaceSelectionPreflightV0 {
    static func canRetain(
        supportsStreamContinuity: @MainActor () async -> Bool,
        rendererReady: @MainActor () -> Bool,
        selectionCurrent: @MainActor () -> Bool
    ) async throws -> Bool {
        guard !Task.isCancelled, selectionCurrent() else { throw CancellationError() }
        let supported = await supportsStreamContinuity()
        // Recovery can publish its busy state before it reserves the surface
        // transition. Revalidate after the probe even for unsupported peers;
        // a false result must not send stale work down the replacement path.
        guard !Task.isCancelled, selectionCurrent() else { throw CancellationError() }
        return supported && rendererReady()
    }
}

@available(iOS 17.0, *)
@MainActor
public struct UIKitClientNativeVideoPreparationV0 {
    public let binding: InteractiveNativeVideoBindingV0
    public let driver: any UIKitClientNativeVideoDriverV0
    public let acknowledgePresentation: (@MainActor (UInt64, InteractiveNativeVideoSurfaceV0) async throws -> InteractiveNativeVideoPresentationReceiptBodyV0)?
    public let current: @MainActor () -> InteractiveNativeVideoBindingV0?
    public init(binding: InteractiveNativeVideoBindingV0, driver: any UIKitClientNativeVideoDriverV0,
                current: @escaping @MainActor () -> InteractiveNativeVideoBindingV0?,
                acknowledgePresentation: (@MainActor (UInt64, InteractiveNativeVideoSurfaceV0) async throws -> InteractiveNativeVideoPresentationReceiptBodyV0)? = nil) {
        self.acknowledgePresentation = acknowledgePresentation
        self.binding = binding; self.driver = driver; self.current = current
    }
}
#endif
