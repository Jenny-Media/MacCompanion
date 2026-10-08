#if os(macOS)
import Foundation
import OSLog

private let macManagedSunshineProcessOwnerLoggerV1 = Logger(
    subsystem: "media.jenny.maccompanion.mac",
    category: "managed-video-process"
)

/// Menu-owned process adapter. The authenticated Control owner supplies the
/// admission closure and original deadline; neither a helper nor its endpoint
/// can grant permission. Artifact admission belongs to the local composition.
@MainActor
public final class MacManagedSunshineProcessOwnerV1 {
    public enum Failure: Error {
        case invalidPhase
        case leaseExpired
        case authorizationLost
        case invalidPath
    }

    private let revalidateControl: @MainActor () -> Bool
    private let didExit: @MainActor (Int32) -> Void
    private var process: Process?
    private var watchdog: Task<Void, Never>?
    private var generation: UUID?
    private var retired = false
    private var stopWaiters: [CheckedContinuation<Void, Never>] = []

    public init(
        revalidateControl: @escaping @MainActor () -> Bool,
        didExit: @escaping @MainActor (Int32) -> Void
    ) {
        self.revalidateControl = revalidateControl
        self.didExit = didExit
    }

    public func start(
        supervisor: URL,
        sunshine: URL,
        configuration: URL,
        dataDirectory: URL,
        log: URL,
        expiresAtMonotonicNanoseconds: UInt64,
        managedEnrollment: Bool = false,
        nativeCapture: (operationID: UUID, path: URL, mode: String)? = nil,
        selectedCaptureContext: URL? = nil
    ) throws {
        guard process == nil, !retired else { throw Failure.invalidPhase }
        guard revalidateControl() else { throw Failure.authorizationLost }
        let now = DispatchTime.now().uptimeNanoseconds
        guard expiresAtMonotonicNanoseconds > now else { throw Failure.leaseExpired }
        // The normative Control maximum is four hours; keep the original deadline.
        guard expiresAtMonotonicNanoseconds - now <= 14_400_000_000_000 else { throw Failure.leaseExpired }
        for path in [supervisor, sunshine, configuration, dataDirectory, log] {
            guard path.isFileURL, path.path.hasPrefix("/") else { throw Failure.invalidPath }
        }
        let identifier = UUID()
        let child = Process()
        child.executableURL = supervisor
        child.arguments = [String(expiresAtMonotonicNanoseconds), sunshine.path, configuration.path]
        var environment = ProcessInfo.processInfo.environment
        environment["SUNSHINE_APPDATA"] = dataDirectory.path
        environment.removeValue(forKey: "MACCOMPANION_MANAGED_ENROLLMENT")
        if managedEnrollment { environment["MACCOMPANION_MANAGED_ENROLLMENT"] = "1" }
        for key in ["MACCOMPANION_NATIVE_OPERATION", "MACCOMPANION_NATIVE_GEOMETRY_PATH", "MACCOMPANION_NATIVE_MODE", "MACCOMPANION_NATIVE_SELECTION_PATH"] {
            environment.removeValue(forKey: key)
        }
        if let nativeCapture {
            guard managedEnrollment, nativeCapture.path.isFileURL,
                  nativeCapture.path.deletingLastPathComponent().standardizedFileURL == dataDirectory.standardizedFileURL,
                  nativeCapture.path.lastPathComponent == "capture-geometry.json",
                  nativeCapture.mode.range(of: #"^[0-9]{3,4}x[0-9]{3,4}x60$"#, options: .regularExpression) != nil else {
                throw Failure.invalidPath
            }
            environment["MACCOMPANION_NATIVE_OPERATION"] = nativeCapture.operationID.uuidString
            environment["MACCOMPANION_NATIVE_GEOMETRY_PATH"] = nativeCapture.path.path
            environment["MACCOMPANION_NATIVE_MODE"] = nativeCapture.mode
        }
        if let selectedCaptureContext {
            guard managedEnrollment, nativeCapture != nil, selectedCaptureContext.isFileURL,
                  selectedCaptureContext.deletingLastPathComponent().standardizedFileURL == dataDirectory.standardizedFileURL,
                  selectedCaptureContext.lastPathComponent == "selected-capture.json" else { throw Failure.invalidPath }
            environment["MACCOMPANION_NATIVE_SELECTION_PATH"] = selectedCaptureContext.path
        }
        child.environment = environment
        let output = try FileHandle(forWritingTo: log)
        child.standardOutput = output
        child.standardError = output
        child.terminationHandler = { [weak self] terminated in
            let status = terminated.terminationStatus
            Task { @MainActor [weak self] in
                self?.completed(generation: identifier, status: status)
            }
        }
        // Close the local descriptor after spawn; the child's inherited
        // descriptor remains valid. Logs stay in ignored, private local data.
        defer { try? output.close() }
        guard revalidateControl(), DispatchTime.now().uptimeNanoseconds < expiresAtMonotonicNanoseconds else {
            throw Failure.authorizationLost
        }
        generation = identifier
        process = child
        do { try child.run() }
        catch { generation = nil; process = nil; throw error }
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.generation == identifier else { return }
                let controlCurrent = self.revalidateControl()
                let deadlineCurrent = DispatchTime.now().uptimeNanoseconds < expiresAtMonotonicNanoseconds
                if !controlCurrent || !deadlineCurrent {
                    macManagedSunshineProcessOwnerLoggerV1.error(
                        "managed video watchdog stopping controlCurrent=\(controlCurrent, privacy: .public) deadlineCurrent=\(deadlineCurrent, privacy: .public)"
                    )
                    await self.stop()
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    public var isRunning: Bool { !retired && process?.isRunning == true }

    /// Terminal for this owner. Completion follows supervisor reaping, so a
    /// later approved generation cannot overlap the retiring capture process.
    public func stop() async {
        retired = true
        watchdog?.cancel()
        watchdog = nil
        guard let process else { return }
        await withCheckedContinuation { continuation in
            stopWaiters.append(continuation)
            if process.isRunning { process.terminate() }
        }
    }

    private func completed(generation identifier: UUID, status: Int32) {
        guard generation == identifier else { return }
        retired = true
        watchdog?.cancel()
        watchdog = nil
        generation = nil
        process = nil
        let waiters = stopWaiters
        stopWaiters.removeAll()
        didExit(status)
        for waiter in waiters { waiter.resume() }
    }
}

#endif
