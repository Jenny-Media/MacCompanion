import CompanionClientPlatform
import CompanionInteractiveShared
import CompanionMoonlightEngine
import UIKit

/// Explicit reference-only composition test: real normal-product UIKit surface
/// and owner, synthetic local authority, upstream paired transport. This class
/// cannot enable input or demonstrate MacCompanion enrollment/approval.
@available(iOS 26.0, *)
@MainActor
@objc(MacCompanionNativeSurfaceProbe)
public final class ReferenceNativeSurfaceProbe: NSObject {
    private var owner: UIKitClientNativeVideoOwnerV0?
    private let container: UIView
    private var surface: UIKitClientLiveSurfaceViewV0?
    private var admitted = true
    private var stopped = false

    @objc(initWithConfiguration:referenceView:event:error:)
    public init(configuration: CompanionMoonlightVideoConfiguration,
                referenceView: UIView, event: @escaping (CompanionMoonlightVideoEvent, Int32) -> Void) throws {
        container = referenceView
        super.init()
        let current = try InteractiveNativeVideoBindingV0(
            hostID: UUID(), hostFingerprint: Data(repeating: 0x11, count: 32),
            clientID: UUID(), primaryConnectionID: Data(repeating: 0x22, count: 16),
            interactiveSessionID: UUID(), authorizationEpoch: 1, grantRevision: 1,
            policyRevision: 1, controlGeneration: UUID(),
            expiresAtMonotonicMilliseconds: DispatchTime.now().uptimeNanoseconds / 1_000_000 + 600_000)
        let surface = UIKitClientLiveSurfaceViewV0(mode: .directTouch,
            onPayloads: { _ in assertionFailure("Reference native composition must not submit input") },
            onFailure: { _ in event(.failed, -1) })
        surface.frame = referenceView.bounds
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        referenceView.addSubview(surface)
        self.surface = surface
        var firstFrameReported = false
        owner = try UIKitClientNativeVideoOwnerV0(
            binding: current,
            descriptor: .init(surfaceID: UUID(), surfaceRevision: 1, coordinateSpaceRevision: 1,
                              encodedWidth: Int(configuration.width), encodedHeight: Int(configuration.height)),
            surface: surface, driver: MoonlightNativeVideoDriverV0(configuration: configuration),
            current: { [weak self] in self?.admitted == true ? current : nil },
            changed: { phase, failure in
                switch phase {
                case .connected: event(.connected, 0)
                case .displaying:
                    if !firstFrameReported { firstFrameReported = true; event(.firstFrame, 0) }
                case .failed: event(.failed, failure == .expired ? -2 : -1)
                default: break
                }
            })
    }

    @objc public func start() throws {
        guard !stopped, let owner else { throw InteractiveNativeVideoFailureV0.connectionFailed }
        try owner.start()
    }

    @objc(stopWithCompletion:)
    public func stop(completion: @escaping () -> Void) {
        stopped = true
        admitted = false
        surface?.resetInputAndBlank()
        Task { [self] in
            await owner?.close()
            owner = nil
            surface?.removeFromSuperview()
            surface = nil
            completion()
        }
    }
}
