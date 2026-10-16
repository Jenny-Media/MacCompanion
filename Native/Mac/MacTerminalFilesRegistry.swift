#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation

@MainActor final class MacTerminalFilesRegistry {
    static let shared = MacTerminalFilesRegistry()
    private struct Entry {
        weak var session: DirectTerminalSession?
        let libraryURL: URL
    }
    private var entries: [UUID: Entry] = [:]
    func register(_ session: DirectTerminalSession, windowID: UUID, libraryURL: URL) {
        entries[windowID] = .init(session: session, libraryURL: libraryURL.standardizedFileURL)
    }
    func remove(_ session: DirectTerminalSession, windowID: UUID) {
        if entries[windowID]?.session === session { entries.removeValue(forKey: windowID) }
    }
    private func source(_ request: DirectFilesWindowRequest, libraryURL: URL) -> DirectTerminalSession? {
        guard let id = request.terminalID, let token = request.connectionGeneration,
              let entry = entries[id], entry.libraryURL == libraryURL.standardizedFileURL,
              let session = entry.session, session.mac.id == request.macID,
              let context = session.filesContext, context.generation == token else { return nil }
        return session
    }
    func record(for request: DirectFilesWindowRequest, libraryURL: URL) -> DirectMacRecordV1? {
        source(request, libraryURL: libraryURL)?.mac
    }
    func context(for request: DirectFilesWindowRequest, mac: DirectMacRecordV1, libraryURL: URL) -> DirectFilesConnectionContext? {
        guard let session = source(request, libraryURL: libraryURL),
              session.mac.id == mac.id, session.mac.addresses == mac.addresses,
              session.mac.sshPort == mac.sshPort else { return nil }
        return session.filesContext
    }
}
#endif
