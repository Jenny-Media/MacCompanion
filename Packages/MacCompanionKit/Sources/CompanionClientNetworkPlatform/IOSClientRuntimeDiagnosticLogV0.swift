import Foundation
import CompanionInteractiveShared
import CompanionInteractiveClient

/// Bounded, content-free diagnostics for physical-device reliability work.
/// The log records fixed events, error types, ephemeral attempt IDs and elapsed
/// durations. These IDs carry no host, device or session identity. It never
/// records host names, addresses, pairing material, user input, or pixels.
public enum IOSClientRuntimeDiagnosticLogV0 {
    public static let relativePath =
        "Library/Caches/mac-companion-runtime-diagnostics-v0.log"

    public static func recordViewTransition(_ stage: ClientViewTransitionTraceV1.Stage,
        trace: ClientViewTransitionTraceV1, error: (any Error)? = nil) {
        record("view-transition." + stage.rawValue
            + " attempt=" + trace.attemptID.uuidString
            + " elapsedMs=" + String(trace.elapsedMilliseconds()), error: error)
    }

    public static func record(
        _ event: String,
        error: (any Error)? = nil
    ) {
#if os(iOS)
        IOSClientRuntimeDiagnosticLogStorageV0.shared.record(
            event,
            errorType: error.map { String(reflecting: type(of: $0)) },
            errorCode: error.flatMap(classify)
        )
#endif
    }

    private static func classify(_ error: any Error) -> String? {
        if error is CancellationError { return "cancelled" }
        if let error = error as? NetworkClientInteractiveInitialDesktopErrorV0 {
            switch error {
            case .invalidPhase: return "invalidPhase"
            case .unavailable: return "unavailable"
            }
        }
        if let error = error as? ClientInteractivePrimaryChannelErrorV0 {
            switch error {
            case .invalidConfiguration: return "invalidConfiguration"
            case .unavailable: return "primaryUnavailable"
            case .initialSurfaceUnavailable: return "initialSurfaceUnavailable"
            case .initialSurfaceDeadlineExceeded: return "initialSurfaceDeadlineExceeded"
            case .surfaceTransitionDeadlineExceeded: return "surfaceTransitionDeadlineExceeded"
            case .displayCommandDeadlineExceeded: return "displayCommandDeadlineExceeded"
            case .cancelled: return "cancelled"
            }
        }
        return nil
    }
}

#if os(iOS)
private final class IOSClientRuntimeDiagnosticLogStorageV0:
    @unchecked Sendable
{
    static let shared = IOSClientRuntimeDiagnosticLogStorageV0()

    private static let maximumBytes = 512 * 1_024
    private let lock = NSLock()

    func record(_ event: String, errorType: String?, errorCode: String?) {
        lock.withLock {
            guard let url = Self.logURL() else { return }
            let manager = FileManager.default
            try? manager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if (try? manager.attributesOfItem(atPath: url.path)[.size]
                    as? NSNumber)?.intValue ?? 0 > Self.maximumBytes {
                try? Data().write(to: url, options: .atomic)
            }
            let timestamp = String(
                format: "%.3f",
                Date().timeIntervalSince1970
            )
            let suffix = (errorType.map { " errorType=\($0)" } ?? "")
                + (errorCode.map { " errorCode=\($0)" } ?? "")
            guard let data = "timestamp=\(timestamp) event=\(event)\(suffix)\n"
                .data(using: .utf8) else { return }
            if !manager.fileExists(atPath: url.path) {
                try? data.write(to: url, options: .atomic)
                return
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {}
        }
    }

    private static func logURL() -> URL? {
        FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent(
            "mac-companion-runtime-diagnostics-v0.log",
            isDirectory: false
        )
    }
}
#endif
