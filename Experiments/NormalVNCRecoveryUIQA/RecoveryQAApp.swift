import SwiftUI

// Synthetic UI-test entry point only. Exclude the normal @main file in the
// disposable QA project; this file must never enter a development/release app.
@main struct RecoveryQAApp: App {
    @State private var session = Self.makeSession()
    @State private var library = Self.makeLibrary()
    private var arguments: [String] { ProcessInfo.processInfo.arguments }
    @MainActor private static func makeSession() -> DirectTerminalSession {
        let mac = DirectMacRecordV1(id: UUID(uuidString: "F2271743-21DD-470F-8272-EF023030CE76")!, name: "Synthetic Mac", addresses: ["synthetic.local"])
        try! TerminalSecretStore.save(.init(username: "synthetic", password: "synthetic-only"), id: mac.id)
        let session = DirectTerminalSession(mac: mac)
        if ProcessInfo.processInfo.arguments.contains("auth-rejected") {
            session.recovery = .make(.loginRejected, details: [.init(name: "Stage", value: "Authentication")])
        } else { session.connected = true }
        return session
    }
    @MainActor private static func makeLibrary() -> DirectMacLibraryV1 {
        let url = URL.applicationSupportDirectory.appending(path: "synthetic-recovery-ui-macs.json")
        try? FileManager.default.removeItem(at: url)
        let library = DirectMacLibraryV1(url: url)
        if ProcessInfo.processInfo.arguments.contains("mac-list-alignment") {
            for (name, connection, model) in [("Laptop", DirectMacConnection.trackpad, "MacBookPro18,1"),
                                              ("Desktop", .desktop, "Macmini9,1"), ("Terminal", .terminal, "MacBookAir10,1")] {
                let host = name.lowercased() + ".local"
                precondition(library.save(id: nil, name: name, addresses: [host, name.lowercased() + ".synthetic.ts.net"], preferredConnection: connection))
                library.updateDetectedMetadata([.init(name: name, host: host, addresses: [host], port: 5900, connection: .desktop, modelIdentifier: model)])
            }
        } else {
            precondition(library.save(id: nil, name: "Synthetic Mac", address: "synthetic.local"))
            library.updateDetectedMetadata([.init(name: "Synthetic Mac", host: "synthetic.local", addresses: ["synthetic.local"], port: 5900, connection: .desktop, modelIdentifier: "MacBookPro18,1")])
        }
        return library
    }
    var body: some Scene {
        WindowGroup {
            Group {
                if arguments.contains("cached-editor") {
                    DirectMacEditorV1(mac: library.macs[0], library: library)
                } else if arguments.contains("mac-list") || arguments.contains("mac-list-alignment") {
                    DirectMacLibraryRootV1(library: library)
                        .environment(\.dynamicTypeSize, arguments.contains("accessibility-text") ? .accessibility3 : arguments.contains("large-text") ? .xxxLarge : .large)
                } else {
                    DirectTerminalView(mac: session.mac, session: session, autoConnect: false, exit: {})
                        .task {
                            guard !arguments.contains("auth-rejected") else { return }
                            try? await Task.sleep(for: .seconds(1))
                            session.stop()
                            let details: [DirectRecoveryNotice.Detail] = arguments.contains("no-details") ? [] : [
                                .init(name: "Service", value: "Remote Login (SSH)"), .init(name: "Stage", value: "Original stage")]
                            session.recovery = .make(.terminalEnded, message: "Synthetic connection was lost. Open a new shell to continue.", details: details)
                            if arguments.contains("replace-issue") {
                                try? await Task.sleep(for: .seconds(8))
                                session.clearRecovery()
                                session.recovery = .make(.macUnreachable, message: "Synthetic replacement issue.", details: [.init(name: "Stage", value: "Replacement stage")])
                            }
                        }
                }
            }.directAppearance()
        }
    }
}
