import Darwin
import Foundation
import Observation

struct WorkspaceMachine: Equatable, Sendable {
    let id: UUID
    let name: String
    let addresses: [String]
    let desktopPort: Int
    let sshPort: Int
}

enum WorkspaceFailure: Error, Equatable {
    case invalidAddress, unavailableAddress, missingApplication, launchFailed, timedOut
    var message: String {
        switch self {
        case .invalidAddress: "Use a local or private VPN address and a port from 1 to 65535."
        case .unavailableAddress: "No local or private VPN address could be resolved. Check the addresses and VPN connection, then retry."
        case .missingApplication: "Apple Screen Sharing could not be found on this Mac. Terminal is still available."
        case .launchFailed: "Screen Sharing could not be opened. Terminal is still available; you can retry Screen Sharing."
        case .timedOut: "Opening Screen Sharing took too long. Terminal is still available; retry when ready."
        }
    }
}

enum WorkspaceDesktopState: Equatable {
    case idle, opening, openedExternally, failed(WorkspaceFailure)
    var title: String {
        switch self {
        case .idle: "Opens Apple Screen Sharing"
        case .opening: "Opening Screen Sharing…"
        case .openedExternally: "Opened in Screen Sharing"
        case .failed: "Screen Sharing could not be opened"
        }
    }
}

enum WorkspaceEndpoint {
    private static func numericCandidates(_ host: String, numericOnly: Bool) -> [String] {
        let permitted = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._:%")
        guard !host.isEmpty, host.utf8.count <= 255, host.unicodeScalars.allSatisfy(permitted.contains) else { return [] }
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC; hints.ai_socktype = SOCK_STREAM; hints.ai_protocol = IPPROTO_TCP
        if numericOnly { hints.ai_flags = AI_NUMERICHOST }
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return [] }
        defer { freeaddrinfo(first) }
        var output: [String] = [], cursor: UnsafeMutablePointer<addrinfo>? = first
        while let current = cursor {
            let address = current.pointee
            if CompanionVNCLocalEndpoint(address.ai_addr, Int(address.ai_addrlen)) {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let code = buffer.withUnsafeMutableBufferPointer {
                    getnameinfo(address.ai_addr, address.ai_addrlen, $0.baseAddress, socklen_t($0.count), nil, 0, NI_NUMERICHOST)
                }
                if code == 0 { output.append(String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)) }
            }
            cursor = address.ai_next
        }
        return output
    }
    static func resolve(_ addresses: [String]) async throws -> String {
        guard (1...8).contains(addresses.count) else { throw WorkspaceFailure.invalidAddress }
        // DNS never blocks the UI actor. The coordinator owns the bounded wait
        // and retires late output; the resolver owns its independent lifetime.
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                for host in addresses {
                    if let numeric = numericCandidates(host, numericOnly: false).first {
                        continuation.resume(returning: numeric); return
                    }
                }
                continuation.resume(throwing: WorkspaceFailure.unavailableAddress)
            }
        }
    }
    static func url(host: String, port: Int) throws -> URL {
        guard CompanionVNCPortValid(Int32(clamping: port)), let numeric = numericCandidates(host, numericOnly: true).first else {
            throw WorkspaceFailure.invalidAddress
        }
        var components = URLComponents()
        components.scheme = "vnc"
        components.host = numeric.contains(":") ? "[\(numeric)]" : numeric
        components.port = port
        guard let url = components.url, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil, components.path.isEmpty else { throw WorkspaceFailure.invalidAddress }
        return url
    }
}

/// Experiment-only handoff owner. Opening an external app is never proof of a
/// remote connection; no credentials or per-session control cross this boundary.
@MainActor @Observable final class WorkspaceCoordinator {
    enum Action { case desktop, terminal }
    private(set) var states: [UUID: WorkspaceDesktopState] = [:]
    private var terminalWindows: [UUID: UUID] = [:]
    private var pending: (token: UUID, machine: WorkspaceMachine)?
    private var work: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private let timeout: Duration
    private let resolve: @Sendable ([String]) async throws -> String
    private let openDesktop: @MainActor (URL) async throws -> Void
    private let openTerminal: @MainActor (UUID, UUID) -> Void
    private let canAccess: @MainActor () -> Bool
    private let isCurrent: @MainActor (WorkspaceMachine) -> Bool
    init(timeout: Duration = .seconds(10),
         resolve: @escaping @Sendable ([String]) async throws -> String = WorkspaceEndpoint.resolve,
         openDesktop: @escaping @MainActor (URL) async throws -> Void,
         openTerminal: @escaping @MainActor (UUID, UUID) -> Void,
         canAccess: @escaping @MainActor () -> Bool,
         isCurrent: @escaping @MainActor (WorkspaceMachine) -> Bool) {
        self.timeout = timeout; self.resolve = resolve; self.openDesktop = openDesktop
        self.openTerminal = openTerminal; self.canAccess = canAccess; self.isCurrent = isCurrent
    }
    func open(_ machine: WorkspaceMachine, action: Action) {
        guard canAccess(), isCurrent(machine) else { return }
        if action == .terminal {
            let window = terminalWindows[machine.id] ?? UUID()
            terminalWindows[machine.id] = window; openTerminal(machine.id, window)
            return
        }
        if pending?.machine == machine { return }
        invalidate()
        let token = UUID(); pending = (token, machine); states[machine.id] = .opening
        let resolver = resolve, opener = openDesktop
        work = Task { [weak self] in
            do {
                let numeric = try await resolver(machine.addresses)
                guard self?.admit(token, machine) == true, !Task.isCancelled else { return }
                let url = try WorkspaceEndpoint.url(host: numeric, port: machine.desktopPort)
                try await opener(url)
                guard self?.admit(token, machine) == true, !Task.isCancelled else { return }
                self?.finish(token, machine.id, .openedExternally)
            } catch {
                guard self?.admit(token, machine) == true, !Task.isCancelled else { return }
                self?.finish(token, machine.id, .failed(error as? WorkspaceFailure ?? .launchFailed))
            }
        }
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: self?.timeout ?? .seconds(10)) } catch { return }
            guard !Task.isCancelled, self?.admit(token, machine) == true else { return }
            self?.finish(token, machine.id, .failed(.timedOut))
        }
    }
    private func admit(_ token: UUID, _ machine: WorkspaceMachine) -> Bool {
        guard pending?.token == token else { return false }
        guard canAccess(), isCurrent(machine) else { invalidate(); return false }
        return true
    }
    private func finish(_ token: UUID, _ machineID: UUID, _ state: WorkspaceDesktopState) {
        guard pending?.token == token else { return }
        pending = nil; work?.cancel(); work = nil; deadline?.cancel(); deadline = nil
        states[machineID] = state
    }
    func invalidate() {
        if let pending { states[pending.machine.id] = .idle }
        pending = nil; work?.cancel(); work = nil; deadline?.cancel(); deadline = nil
    }
    func recordsChanged(validIDs: Set<UUID>) {
        if let pending, !isCurrent(pending.machine) { invalidate() }
        states = states.filter { validIDs.contains($0.key) }
        terminalWindows = terminalWindows.filter { validIDs.contains($0.key) }
    }
    func terminalClosed(macID: UUID, windowID: UUID) {
        if terminalWindows[macID] == windowID { terminalWindows[macID] = nil }
    }
    isolated deinit { work?.cancel(); deadline?.cancel() }
}
