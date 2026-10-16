#if (os(iOS) || os(macOS)) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
@preconcurrency import Citadel

/// A borrowed authenticated context never contains a password or private key.
@MainActor struct DirectFilesConnectionContext {
    let client: SSHClient
    let macID: UUID
    var ownerID = UUID()
    let account: String
    let keyID: UUID?
    let generation: UUID
    var isCurrent: @MainActor () -> Bool = { true }
}
#endif
