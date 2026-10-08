#if os(iOS)
import CompanionClientPlatform
import CompanionInteractiveShared
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
    private var surfaceProgressMonitor: Task<Void, Never>?
    private var surfaceProgressAttempt = UUID()
    private var eventHandler: (@MainActor (UIKitClientNativeVideoEventV0) -> Void)?
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
        eventHandler = event
        // ObjC guarantees main-thread delivery. `assumeIsolated` verifies that
        // promise rather than scheduling a stale callback onto a later owner.
        let native = try CompanionMoonlightVideo(configuration: configuration, view: view) { [weak self] value, code in
            MainActor.assumeIsolated {
                guard let self, !self.stopped, let native = self.session else { return }
                guard let event = self.eventHandler else { return }
                switch value {
                case .connected: event(.connected)
                case .firstFrame:
                    self.observeSurfaceProgress(native)
                    event(.firstFrame(width: Int(native.decodedWidth), height: Int(native.decodedHeight)))
                case .failed:
                    self.diagnostic("native.video.driver.terminal-source-" + String(native.terminalDiagnosticCode))
                    self.diagnostic("native.video.driver.failed-code-" + String(code))
                    event(.failed)
                case .disconnected:
                    self.diagnostic("native.video.driver.terminal-source-" + String(native.terminalDiagnosticCode))
                    self.diagnostic("native.video.driver.disconnected-code-" + String(code))
                    event(.disconnected)
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
    public var supportsSurfaceReplacement: Bool { !stopped && session != nil }

    /// Debug evidence only: a second queued frame must belong to this exact
    /// presentation generation. This never changes admission or UI timing.
    private func observeSurfaceProgress(_ native: CompanionMoonlightVideo) {
        #if DEBUG
        surfaceProgressMonitor?.cancel()
        let attempt = surfaceProgressAttempt
        let baseline = native.queuedVideoFrameCount
        diagnostic("native.video.surface-presented attempt=" + attempt.uuidString)
        surfaceProgressMonitor = Task { [weak self, weak native] in
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self, let native, !self.stopped,
                      self.session === native, self.surfaceProgressAttempt == attempt else { return }
                if native.presentationReady && native.queuedVideoFrameCount > baseline {
                    self.diagnostic("native.video.surface-frames-advanced attempt=" + attempt.uuidString)
                    return
                }
            }
            guard let self, !Task.isCancelled, !self.stopped,
                  self.surfaceProgressAttempt == attempt else { return }
            self.diagnostic("native.video.surface-frames-stalled attempt=" + attempt.uuidString)
        }
        #endif
    }

    public func beginSurfaceReplacement(event: @escaping @MainActor (UIKitClientNativeVideoEventV0) -> Void) throws {
        guard !stopped, let session else { throw DriverFailure.invalidPhase }
        try session.beginSurfaceReplacement()
        surfaceProgressMonitor?.cancel()
        surfaceProgressMonitor = nil
        surfaceProgressAttempt = UUID()
        eventHandler = event
    }

    public func resumeSurfaceReplacement(surface: InteractiveNativeVideoSurfaceV0) throws {
        guard !stopped, let session else { throw DriverFailure.invalidPhase }
        var bytes = Data([0xd5,0xe7,0xc9,0x3a,0x1d,0xa9,0x4b,0xf2,0x8f,0x2b,0x09,0xa1,0xde,0x10,0x5a,0x51])
        var uuid = surface.surfaceID.uuid
        withUnsafeBytes(of: &uuid) { bytes.append(contentsOf: $0) }
        for revision in [surface.surfaceRevision, surface.coordinateSpaceRevision] {
            guard (1...9_007_199_254_740_991).contains(revision) else { throw DriverFailure.invalidPhase }
            var bigEndian = UInt64(revision).bigEndian
            withUnsafeBytes(of: &bigEndian) { bytes.append(contentsOf: $0) }
        }
        try session.resumeSurfaceReplacement(withEpoch: bytes)
    }

    public func stop() async {
        stopped = true
        eventHandler = nil
        frameProgressMonitor?.cancel()
        frameProgressMonitor = nil
        surfaceProgressMonitor?.cancel()
        surfaceProgressMonitor = nil
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
