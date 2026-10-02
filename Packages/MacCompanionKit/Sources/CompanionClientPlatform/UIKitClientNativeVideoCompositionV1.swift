#if os(iOS)
import CompanionClient
import CompanionClientNetworkPlatform
import CompanionInteractiveClient
import CompanionInteractiveShared
import Foundation

/// Fixed recovery text supplied by a local adapter; never raw server text,
/// addresses, security material, or input content.
public protocol ClientCommandFailurePresentingV0: Error {
    var commandFailureDetail: String { get }
}

/// Normal-app construction seam for an independently admitted video adapter.
/// Each Control request constructs a fresh preparer. The route reader remains
/// bound to the workspace's currently selected authenticated primary.
@available(iOS 17.0, *)
@MainActor
public enum UIKitClientNativeVideoCompositionV1 {
    public typealias RouteReader = @Sendable (Data) async throws -> String?
    public typealias AdapterFactory = @MainActor @Sendable (
        any ClientSessionAuthenticationSigningV0,
        @escaping RouteReader
    ) throws -> any UIKitClientNativeVideoPreparingV0
    public typealias ProductFactory = @MainActor @Sendable (
        ClientInputInteractionModeV0,
        @escaping @MainActor @Sendable (any Error) -> Void
    ) async throws -> UIKitClientInitialDesktopProductV0

    public static func productFactory(
        signer: any ClientSessionAuthenticationSigningV0,
        primaryState: NetworkClientPrimaryApplicationStateV0,
        roles: NetworkClientInteractiveRoleProductBindingV0,
        adapterFactory: @escaping AdapterFactory,
        changed: @escaping @MainActor @Sendable (InteractiveNativeVideoPhaseV0, InteractiveNativeVideoFailureV0?) -> Void = { _, _ in }
    ) -> ProductFactory {
        { mode, failure in
            let product = try await UIKitClientInitialDesktopProductFactoryV0.make(
                roles: roles, mode: mode, failure: failure
            )
            do {
                let replacement: @MainActor () throws -> any UIKitClientNativeVideoPreparingV0 = {
                    try adapterFactory(signer, {
                        primaryState.currentAuthenticatedNativeIPAddress(primaryConnectionID: $0)
                    })
                }
                let preparer = try replacement()
                do {
                    // The native owner blanks and drains terminal media and
                    // retains its typed failure. This notification must remain
                    // observational while that retirement is in progress.
                    try product.configureNativeVideo(preparer: preparer, replacementPreparer: replacement, changed: { phase, reason in
                        changed(phase, reason)
                    })
                } catch {
                    await preparer.close()
                    throw error
                }
                return product
            } catch {
                await product.close()
                throw error
            }
        }
    }
}
#endif
