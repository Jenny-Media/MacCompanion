import CompanionClient
import CompanionClientApp
import CompanionPresentation
import Dispatch
import Foundation

/// Public pairing composition for the release iOS target. Connection pinning,
/// wall/monotonic time, nonce generation, and message identifiers are fixed
/// inside package-owned implementations rather than supplied by the app.
public enum NetworkClientPairingApplicationCompositionV0 {
    public static func makeOwner(
        clientID: UUID,
        custody: any ClientIdentityKeyCustodyV0,
        persistence: any ClientPairedHostPersistenceV0,
        verificationQueue: DispatchQueue,
        connectionQueue: DispatchQueue,
        stateChanged: @escaping ClientPairingApplicationOwnerV0.StateChanged = {
            _ in
        }
    ) throws -> ClientPairingApplicationOwnerV0 {
        let networkClock: @Sendable () -> NetworkClientClockSnapshotV0 = {
            NetworkClientClockSnapshotV0(
                wallNowUnixMilliseconds: Int64(
                    Date().timeIntervalSince1970 * 1_000
                ),
                monotonicNowMilliseconds:
                    DispatchTime.now().uptimeNanoseconds / 1_000_000
            )
        }
        return try ClientPairingApplicationOwnerV0(
            clientID: clientID,
            custody: custody,
            persistence: persistence,
            connections: NetworkClientPairingConnectionFactoryV0(
                verificationQueue: verificationQueue,
                connectionQueue: connectionQueue,
                clock: networkClock
            ),
            stateChanged: stateChanged
        )
    }
}
