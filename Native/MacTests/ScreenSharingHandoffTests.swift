import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw TestFailure(description: message) }
}

private actor Gate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var released = false
    private(set) var entered = false
    func wait() async {
        entered = true
        if released { return }
        await withCheckedContinuation { continuations.append($0) }
    }
    func release() { released = true; continuations.forEach { $0.resume() }; continuations = [] }
}

@MainActor private final class Harness {
    let first = MacToolMachine(id: UUID(), name: "Synthetic Mac", addresses: ["127.0.0.1"], desktopPort: 5900, sshPort: 22)
    let second = MacToolMachine(id: UUID(), name: "Other Synthetic Mac", addresses: ["192.168.1.25"], desktopPort: 5901, sshPort: 2222)
    var allowed = true
    var current: [UUID: MacToolMachine] = [:]
    var urls: [URL] = []
    var terminals: [(UUID, UUID)] = []
    init() { current = [first.id: first, second.id: second] }
    func coordinator(timeout: Duration = .seconds(2), gate: Gate? = nil,
                     launchGate: Gate? = nil, failure: MacScreenSharingFailure? = nil) -> MacToolCoordinator {
        MacToolCoordinator(timeout: timeout, resolve: { addresses in
            if let gate { await gate.wait() }
            return addresses[0]
        }, openDesktop: { [self] url in
            urls.append(url)
            if let launchGate { await launchGate.wait() }
            if let failure { throw failure }
        }, openTerminal: { [self] id, token in terminals.append((id, token)) },
            canAccess: { [self] in allowed }, isCurrent: { [self] value in current[value.id] == value })
    }
}

@MainActor private func eventually(_ message: String, _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !condition() {
        if ContinuousClock.now >= deadline { throw TestFailure(description: message) }
        try await Task.sleep(for: .milliseconds(1))
    }
}
@MainActor private func settle() async throws { try await Task.sleep(for: .milliseconds(20)) }

@main struct MacScreenSharingHandoffTests {
    @MainActor static func main() async {
        do {
            var count = 0
            let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(filePath: CommandLine.arguments[1]))) as! [String: Any]
            let contract = fixture["workspacePrototype"] as! [String: Any]
            let shipping = fixture["screenSharingHandoff"] as! [String: Any]
            try expect(shipping["launch"] as? String == "explicitUserActionOnly", "Restoration must not launch an external app")
            try expect(shipping["dataLibrary"] as? String == "existingDirectMacLibrary", "Shipping must preserve the existing Mac library")
            for entry in contract["urlCases"] as! [[String: Any]] {
                let allowed = entry["allowed"] as! Bool
                do {
                    let url = try MacScreenSharingEndpoint.url(host: entry["host"] as! String, port: entry["port"] as! Int)
                    try expect(allowed, "Rejected endpoint was admitted")
                    try expect(url.absoluteString == entry["url"] as? String, "Endpoint URL differs from authoritative fixture")
                    let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                    try expect(parts.user == nil && parts.password == nil && parts.query == nil && parts.fragment == nil && parts.path.isEmpty, "URL carries extra fields")
                } catch is MacScreenSharingFailure {
                    try expect(!allowed, "Private endpoint was rejected")
                }
                count += 1
            }

            // The real resolver admits numeric private addresses and rejects public
            // addresses without requiring any network or real saved-machine data.
            let numeric = try await MacScreenSharingEndpoint.resolve(["8.8.8.8", "127.0.0.1"])
            try expect(numeric == "127.0.0.1", "Resolver did not skip public endpoint")
            do {
                _ = try await MacScreenSharingEndpoint.resolve([])
                throw TestFailure(description: "Empty address list accepted")
            } catch is MacScreenSharingFailure { }
            count += 2

            do {
                let h = Harness()
                let owner = h.coordinator()
                owner.open(h.first, action: .desktop)
                try await eventually("Workspace handoff did not finish") { owner.states[h.first.id] == .openedExternally }
                try expect(h.terminals.isEmpty, "Screen Sharing implicitly opened Terminal")
                owner.open(h.first, action: .terminal)
                try expect(h.terminals.count == 1 && h.terminals[0].0 == h.first.id, "Terminal targets a different Mac")
                try expect(h.urls.map(\.absoluteString) == ["vnc://127.0.0.1:5900"], "Desktop targets a different Mac")
                try expect(owner.states[h.first.id]?.title == "Opened in Screen Sharing", "External handoff claims a connection")
                count += 1
            }
            for failure in [MacScreenSharingFailure.missingApplication, .launchFailed] {
                let h = Harness(), c = h.coordinator(failure: failure)
                c.open(h.first, action: .desktop)
                try await eventually("Failure was not reported") { c.states[h.first.id] == .failed(failure) }
                try expect(h.terminals.isEmpty, "Failed Screen Sharing implicitly opened Terminal")
                c.open(h.first, action: .terminal)
                c.open(h.first, action: .terminal)
                try expect(h.terminals.count == 2 && h.terminals[0].1 == h.terminals[1].1, "Terminal was closed by Desktop failure")
                count += 1
            }
            do {
                let h = Harness(), gate = Gate(), c = h.coordinator(gate: gate)
                c.open(h.first, action: .desktop); c.open(h.first, action: .desktop)
                try expect(h.terminals.isEmpty, "Pending Screen Sharing opened Terminal")
                c.open(h.first, action: .terminal)
                await gate.release()
                try await eventually("Pending handoff did not finish") { c.states[h.first.id] == .openedExternally }
                c.open(h.first, action: .desktop)
                try await eventually("Repeated completed handoff did not run") { h.urls.count == 2 }
                try expect(h.terminals.count == 1, "Repeated Screen Sharing reopened Terminal")
                c.open(h.first, action: .terminal)
                try expect(h.terminals.count == 2 && h.terminals[0].1 == h.terminals[1].1, "Terminal did not reuse its window")
                c.terminalClosed(macID: h.first.id, windowID: h.terminals[0].1)
                c.open(h.first, action: .terminal)
                let replacement = h.terminals[2].1
                try expect(replacement != h.terminals[0].1, "Closed Terminal window token reused")
                c.terminalClosed(macID: h.first.id, windowID: h.terminals[0].1)
                c.open(h.first, action: .terminal)
                try expect(h.terminals[3].1 == replacement, "Late close retired replacement Terminal")
                count += 3
            }
            do {
                let h = Harness(), c = h.coordinator()
                h.allowed = false; c.open(h.first, action: .desktop)
                h.allowed = true; h.current[h.first.id] = nil; c.open(h.first, action: .desktop)
                try await settle()
                try expect(h.terminals.isEmpty && h.urls.isEmpty && c.states.isEmpty, "Locked or removed Mac launched work")
                count += 2
            }
            for retirement in 0..<4 {
                let h = Harness(), gate = Gate(), c = h.coordinator(gate: gate)
                c.open(h.first, action: .terminal)
                c.open(h.first, action: .desktop)
                if retirement == 0 { h.allowed = false; c.invalidate() }
                if retirement == 1 { h.current[h.first.id] = nil; c.recordsChanged(validIDs: Set(h.current.keys)) }
                if retirement == 2 {
                    h.current[h.first.id] = MacToolMachine(id: h.first.id, name: h.first.name, addresses: ["192.168.1.2"], desktopPort: h.first.desktopPort, sshPort: 22)
                    c.recordsChanged(validIDs: Set(h.current.keys))
                }
                if retirement == 3 {
                    h.current[h.first.id] = MacToolMachine(id: h.first.id, name: h.first.name, addresses: h.first.addresses, desktopPort: 5902, sshPort: 22)
                    c.recordsChanged(validIDs: Set(h.current.keys))
                }
                await gate.release(); try await settle()
                try expect(h.urls.isEmpty && c.states[h.first.id] != .opening && c.states[h.first.id] != .openedExternally, "Retired resolution launched Desktop")
                try expect(h.terminals.count == 1, "Retirement changed Terminal ownership")
                count += 1
            }
            do {
                let h = Harness(), gate = Gate(), c = h.coordinator(gate: gate)
                c.open(h.first, action: .desktop); c.open(h.second, action: .desktop)
                await gate.release()
                try await eventually("Replacement request did not complete") { c.states[h.second.id] == .openedExternally }
                try expect(h.urls.map(\.absoluteString) == ["vnc://192.168.1.25:5901"], "Replaced request launched stale Desktop")
                try expect(c.states[h.first.id] == .idle, "Replaced request left opening state")
                count += 1
            }
            for phase in 0..<2 {
                let h = Harness(), gate = Gate()
                let c = h.coordinator(timeout: .milliseconds(20), gate: phase == 0 ? gate : nil, launchGate: phase == 1 ? gate : nil)
                c.open(h.first, action: .terminal)
                c.open(h.first, action: .desktop)
                try await eventually("Timed-out request stayed pending") { c.states[h.first.id] == .failed(.timedOut) }
                await gate.release(); try await settle()
                try expect(c.states[h.first.id] == .failed(.timedOut), "Late completion resurrected timed-out state")
                try expect(h.urls.count == phase, "Timed-out DNS launched Desktop")
                try expect(h.terminals.count == 1, "Timeout removed Terminal")
                count += 1
            }
            do {
                let h = Harness(), gate = Gate(), c = h.coordinator(launchGate: gate)
                c.open(h.first, action: .desktop)
                try await eventually("Launch callback not held") { h.urls.count == 1 }
                h.allowed = false; c.invalidate(); await gate.release(); try await settle()
                try expect(c.states[h.first.id] == .idle, "Late launch callback overwrote locked state")
                count += 1
            }
            do {
                let h = Harness(), c = h.coordinator()
                c.open(h.first, action: .terminal); try await settle()
                try expect(h.urls.isEmpty && h.terminals.count == 1 && c.states.isEmpty, "Terminal-only opened Desktop")
                c.open(h.second, action: .desktop)
                try await eventually("Desktop-only did not finish") { c.states[h.second.id] == .openedExternally }
                try expect(h.terminals.count == 1, "Desktop-only opened Terminal")
                count += 2
            }
            do {
                let h = Harness(), c = h.coordinator(), restored = UUID(), other = UUID()
                c.terminalOpened(macID: h.first.id, windowID: restored)
                c.terminalOpened(macID: h.first.id, windowID: restored)
                try expect(h.terminals.isEmpty && h.urls.isEmpty, "Restoration launched new work")
                c.open(h.first, action: .terminal)
                try expect(h.terminals.last?.1 == restored, "Restored Terminal was duplicated")
                c.terminalOpened(macID: h.first.id, windowID: other)
                c.terminalClosed(macID: h.first.id, windowID: restored)
                c.terminalClosed(macID: h.first.id, windowID: restored)
                c.open(h.first, action: .terminal)
                try expect(h.terminals.last?.1 == other, "Closing one restored window lost another")
                c.terminalClosed(macID: h.first.id, windowID: other)
                c.open(h.first, action: .terminal)
                try expect(h.terminals.last?.1 != restored && h.terminals.last?.1 != other, "Closed restored window was reused")
                count += 4
            }
            do {
                let h = Harness(), c = h.coordinator(), restored = UUID()
                h.allowed = false
                c.terminalOpened(macID: h.first.id, windowID: restored)
                c.open(h.first, action: .terminal)
                try expect(h.terminals.isEmpty, "Restored Terminal bypassed app lock")
                h.allowed = true
                c.open(h.first, action: .terminal)
                try expect(h.terminals.last?.1 == restored, "Unlock forgot the restored Terminal")
                h.current[h.first.id] = nil
                c.recordsChanged(validIDs: Set(h.current.keys))
                h.current[h.first.id] = h.first
                c.open(h.first, action: .terminal)
                try expect(h.terminals.last?.1 != restored, "Removed Mac kept an old restored window")
                count += 3
            }
            do {
                let h = Harness(), c = h.coordinator()
                c.open(h.first, action: .terminal)
                let preferred = h.terminals[0].1
                c.open(h.first, action: .newTerminal)
                let extra = h.terminals[1].1
                try expect(extra != preferred, "New Terminal Window reused the primary window")
                c.open(h.first, action: .terminal)
                try expect(h.terminals.last?.1 == preferred, "Explicit new window changed the default Terminal owner")
                c.terminalClosed(macID: h.first.id, windowID: preferred)
                c.open(h.first, action: .terminal)
                try expect(h.terminals.last?.1 == extra, "Surviving extra Terminal was forgotten")
                count += 3
            }
            print("PASS: \(count) native Screen Sharing endpoint and lifecycle checks (no GUI or credentials)")
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }
}
