#if os(macOS)
import CompanionIPC
import CompanionInteractiveHost
import Foundation

/// First-party composition only. The caller supplies the trusted local artifact
/// admission policy; a remote request cannot choose executables or bypass it.
@available(macOS 26.0, *)
public enum MacManagedSunshineBackendFactoryV1 {
    public static func make(
        root: URL, sunshine: URL, supervisor: URL, openssl: URL, port: UInt16,
        opensslConfiguration: URL = URL(fileURLWithPath: "/dev/null"),
        listenerScope: MacManagedSunshineEnrollmentBackendV1.ListenerScope = .loopback,
        validateArtifacts: @escaping @Sendable () throws -> Void
    ) -> MacInteractiveNativeBackendFactoryV1 {
        { physicalDisplayID, geometry, permit, selected in
            try await MainActor.run {
                guard permit.isCurrent else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
                try validateArtifacts()
                guard permit.isCurrent else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
                return try MacManagedSunshineEnrollmentBackendV1(
                    root: root, sunshine: sunshine, supervisor: supervisor, openssl: openssl,
                    opensslConfiguration: opensslConfiguration,
                    port: port, approvedDesktopDisplayID: physicalDisplayID,
                    approvedCaptureGeometry: geometry, currentControl: { permit.isCurrent },
                    withCurrentControl: { deadline, batch in
                        try permit.withCurrentInput(beforeDeadlineNanoseconds: deadline, batch)
                    }, listenerScope: listenerScope,
                    approvedSelectedCapture: selected)
            }
        }
    }
}
#endif
