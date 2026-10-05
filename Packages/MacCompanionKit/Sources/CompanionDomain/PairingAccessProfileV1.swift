/// Locally chosen initial trust scope. Never inferred from a remote request.
public enum PairingAccessProfileV1: Sendable {
    case monitorOnly
    case remoteDesktop

    public static let remoteDesktopCapabilityID = "maccompanion.interactive.control"

    public var initialState: DeviceAuthorizationState {
        self == .remoteDesktop ? .activeGranted : .activeMonitorOnly
    }
}
