#if os(iOS)
import CompanionClientPlatform
import CompanionMoonlightEngine
import UIKit

/// The normal UIKit Control owner consumes this driver through its injected
/// protocol. Foreign engine admission belongs to the application build.
@available(iOS 26.0, *)
@MainActor
public final class MoonlightNativeVideoDriverV0: UIKitClientNativeVideoDriverV0 {
    private var configuration: CompanionMoonlightVideoConfiguration?
    private var session: CompanionMoonlightVideo?
    private var stopped = false
    private var retired: (@MainActor () -> Void)?
    private var frameProgressMonitor: Task<Void, Never>?
    private let diagnostic: @MainActor (String) -> Void

    public init(configuration: CompanionMoonlightVideoConfiguration,
                retired: (@MainActor () -> Void)? = nil,
                diagnostic: @escaping @MainActor (String) -> Void = { _ in }) {
        self.retired = retired
        self.diagnostic = diagnostic
        // The engine copies parameters at construction. This temporary launch
        // object is discarded immediately after constructing the native session.
        self.configuration = configuration
    }

    public func start(view: UIView,
               event: @escaping @MainActor (UIKitClientNativeVideoEventV0) -> Void) throws {
        guard !stopped, session == nil, let configuration else {
            throw DriverFailure.invalidPhase
        }
        // ObjC guarantees main-thread delivery. `assumeIsolated` verifies that
        // promise rather than scheduling a stale callback onto a later owner.
        let native = try CompanionMoonlightVideo(configuration: configuration, view: view) { [weak self] value, _ in
            MainActor.assumeIsolated {
                guard let self, !self.stopped, let native = self.session else { return }
                switch value {
                case .connected: event(.connected)
                case .firstFrame: event(.firstFrame(width: Int(native.decodedWidth), height: Int(native.decodedHeight)))
                case .failed: event(.failed)
                case .disconnected: event(.disconnected)
                @unknown default: event(.failed)
                }
            }
        }
        self.configuration = nil
        session = native
        try native.start()
        #if DEBUG
        frameProgressMonitor = Task { [weak self, weak native] in
            var previous: UInt64 = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self, let native,
                      !self.stopped, self.session === native else { return }
                let current = native.queuedVideoFrameCount
                self.diagnostic(
                    current > previous
                        ? "native.video.frames-advanced"
                        : "native.video.frames-stalled"
                )
                previous = current
            }
        }
        #endif
    }

    public var presentationIsReady: Bool { !stopped && session?.presentationReady == true }

    public func stop() async {
        stopped = true
        frameProgressMonitor?.cancel()
        frameProgressMonitor = nil
        configuration = nil
        let callback = retired
        retired = nil
        guard let session else { callback?(); return }
        await withCheckedContinuation { continuation in
            session.stop { continuation.resume() }
        }
        self.session = nil
        callback?()
    }

    private enum DriverFailure: Error { case invalidPhase }
}
#endif
