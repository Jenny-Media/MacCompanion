#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
import Observation
import CryptoKit

/// Logical ancestry is captured when an edit is made, not when it is uploaded.
/// Revision/writer ordering alone cannot distinguish offline edits from successors.
enum DirectControlsCausality {
    static func valid(_ clock: [String: Int64], before revision: Int64 = 1_000_000_001) -> Bool {
        clock.count <= 512 && clock.allSatisfy { key, value in
            UUID(uuidString: key)?.uuidString.lowercased() == key && value > 0 && value < revision
        }
    }
    static func join(_ clocks: [[String: Int64]]) -> [String: Int64] {
        clocks.reduce(into: [:]) { result, clock in
            for (writer, revision) in clock { result[writer] = max(result[writer] ?? 0, revision) }
        }
    }
    static func including(_ clock: [String: Int64]?, writer: UUID, revision: Int64) -> [String: Int64] {
        join([clock ?? [:], [writer.uuidString.lowercased(): revision]])
    }
    static func sees(_ clock: [String: Int64]?, writer: UUID, revision: Int64) -> Bool {
        (clock?[writer.uuidString.lowercased()] ?? 0) >= revision
    }
    static func fingerprint<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data: try encoder.encode(value)).map { String(format: "%02x", $0) }.joined()
    }
}

struct DirectControlsRecoveredChange: Codable, Equatable, Identifiable {
    var id: String
    var family: TerminalControlsFamily
    var layout: DirectCloudKeyboardLayout?
    var control: DirectCloudSavedControl?
    var title: String { control?.action.title ?? "Keyboard layout" }
    var location: String { family == .terminal ? "Terminal" : "Screen Sharing & Trackpad" }
    var symbol: String { layout != nil ? "keyboard" : control?.action.kind == .text ? "text.quote" : "command" }
    func validate() throws {
        guard !id.isEmpty, id.utf8.count <= 256, (layout == nil) != (control == nil) else { throw DirectCloudError.invalid }
        try layout?.validate(); try control?.validate(family: family)
    }
}

/// Device-only bookkeeping lives with the profile. An import and its baseline
/// therefore succeed or fail as one Keychain write, including across a restart.
struct DirectControlsLocalSyncState: Codable, Equatable {
    struct Import: Codable, Equatable {
        var id = UUID()
        var observed: [String: String]
    }
    struct LayoutImport: Codable, Equatable {
        var id = UUID()
        var observed: String
    }
    var layoutImport: LayoutImport?
    var savedImport: Import?
    var savedClocks: [String: [String: Int64]] = [:]
    var layoutClock: [String: Int64] = [:]
    var recovered: [DirectControlsRecoveredChange] = []
    // Per-writer high-water marks keep dismissed copies from returning on refresh.
    var recoverySeen: [String: Int64] = [:]
    mutating func keep(_ change: DirectControlsRecoveredChange, account: String, revision: Int64) {
        guard (recoverySeen[account] ?? 0) < revision else { return }
        recoverySeen[account] = revision
        if !recovered.contains(where: { $0.layout == change.layout && $0.control == change.control }) {
            recovered.append(change)
        }
    }
    func validate(family: TerminalControlsFamily) throws {
        guard DirectControlsCausality.valid(layoutClock), savedClocks.count <= 8192,
              savedClocks.allSatisfy({ UUID(uuidString: $0.key) != nil && DirectControlsCausality.valid($0.value) }),
              recovered.count <= 512, Set(recovered.map(\.id)).count == recovered.count,
              recoverySeen.count <= 8192, recoverySeen.allSatisfy({ !$0.key.isEmpty && $0.key.utf8.count <= 256 && (1...1_000_000_000).contains($0.value) }) else { throw DirectCloudError.invalid }
        if let layoutImport {
            guard layoutImport.observed.count == 64,
                  layoutImport.observed.allSatisfy({ "0123456789abcdef".contains($0) }) else { throw DirectCloudError.invalid }
        }
        if let savedImport {
            guard savedImport.observed.count <= 8192, savedImport.observed.allSatisfy({ key, hash in
                UUID(uuidString: key) != nil && hash.count == 64 && hash.allSatisfy { "0123456789abcdef".contains($0) }
            }) else { throw DirectCloudError.invalid }
        }
        for change in recovered { guard change.family == family else { throw DirectCloudError.invalid }; try change.validate() }
    }
}

@MainActor @Observable final class DirectControlsRecoveryLibrary {
    private static let readError = "Recovered changes couldn’t be read. Existing data is kept."
    private let stores: [TerminalControlsFamily: TerminalControlsStore]
    private let canAccess: @MainActor () -> Bool
    private var observer: RecoveryObservers?
    private(set) var entries: [DirectControlsRecoveredChange] = []
    private(set) var error: String?
    init(stores: [TerminalControlsFamily: TerminalControlsStore] = [.terminal: .init(), .remoteMac: .remoteMac()],
         canAccess: @escaping @MainActor () -> Bool = { DirectAppLockV1.shared.canAccess }) {
        self.stores = stores; self.canAccess = canAccess
        let tokens = [TerminalControlsStore.changed, TerminalControlsStore.prepared, DirectAppLockV1.unlocked, DirectAppLockV1.locked].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            }
        }
        observer = RecoveryObservers(tokens); reload()
    }
    func reload() {
        guard canAccess() else { entries = []; return }
        do {
            var next: [DirectControlsRecoveredChange] = []
            for family in [TerminalControlsFamily.terminal, .remoteMac] {
                if let store = stores[family], let profile = try store.savedControlsCloudProfile() {
                    next += profile.syncState.recovered
                }
            }
            entries = next.sorted { $0.location == $1.location ? $0.id < $1.id : $0.location < $1.location }
            if error == Self.readError { error = nil }
        } catch { self.error = Self.readError }
    }
    @discardableResult func restore(_ entry: DirectControlsRecoveredChange) -> Bool {
        update(entry.family) { profile in
            guard let stored = profile.syncState.recovered.first(where: { $0.id == entry.id }) else { throw DirectCloudError.storage }
            if let layout = stored.layout {
                let previous = DirectCloudKeyboardLayout(profile)
                profile = try layout.applying(to: profile)
                if previous != layout {
                    var state = profile.syncState
                    state.recovered.append(.init(id: "previous." + UUID().uuidString, family: entry.family, layout: previous))
                    profile.syncState = state
                }
            } else if var value = stored.control {
                value.action.id = UUID()
                value.action.title = String(value.action.title.prefix(23)) + " (Recovered copy)"
                for index in value.bar.indices { value.bar[index].placement = UUID().uuidString }
                for index in value.menus.indices { value.menus[index].placement = UUID() }
                profile = try DirectCloudSavedControl.applying([value.action.id: value], to: profile)
            }
            var state = profile.syncState; state.recovered.removeAll { $0.id == entry.id }; profile.syncState = state
        }
    }
    @discardableResult func discard(_ entry: DirectControlsRecoveredChange) -> Bool {
        update(entry.family, cloudImport: true) { profile in
            var state = profile.syncState; state.recovered.removeAll { $0.id == entry.id }; profile.syncState = state
        }
    }
    func discardAll() {
        for family in [TerminalControlsFamily.terminal, .remoteMac] where stores[family] != nil {
            if !update(family, cloudImport: true, edit: { profile in
                var state = profile.syncState; state.recovered = []; profile.syncState = state
            }) { return }
        }
    }
    private func update(_ family: TerminalControlsFamily, cloudImport: Bool = false,
                        edit: (inout TerminalControlsProfile) throws -> Void) -> Bool {
        guard canAccess(), let store = stores[family] else { error = "Unlock the app to change recovered items."; return false }
        do {
            var profile = try store.load(); try edit(&profile)
            _ = try store.save(profile, cloudImport: cloudImport)
            error = nil; reload(); return true
        } catch { self.error = "The change couldn’t be saved. Existing data is kept. Try again."; reload(); return false }
    }
}

private final class RecoveryObservers: @unchecked Sendable {
    let tokens: [NSObjectProtocol]
    init(_ tokens: [NSObjectProtocol]) { self.tokens = tokens }
    deinit { tokens.forEach { NotificationCenter.default.removeObserver($0) } }
}
#endif
