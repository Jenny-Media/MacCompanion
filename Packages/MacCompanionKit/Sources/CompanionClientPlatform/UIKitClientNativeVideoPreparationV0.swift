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
    func close() async
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
