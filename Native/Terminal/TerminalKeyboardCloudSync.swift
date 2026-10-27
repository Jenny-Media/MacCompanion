#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
import Observation

private final class KeyboardLayoutObserver: @unchecked Sendable {
    let token: NSObjectProtocol
    init(_ token: NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}

/// Only layout metadata crosses devices. Saved definitions and their placements
/// are deliberately absent, including shortcuts that contain literal text.
struct DirectCloudKeyboardLayout: Codable, Equatable {
    struct Row: Codable, Equatable {
        var id: UUID
        var kind: TerminalKeyboardRow.Kind
        var title: String
        var keys: [TerminalBarItem]
        var visibility: String
        var alignment: TerminalKeyboardRow.Alignment
        var scrollStart: TerminalKeyboardRow.ScrollStart
    }
    var rows: [Row]
    init(_ profile: TerminalControlsProfile) {
        rows = profile.resolvedRows.map { row in
            Row(id: row.id, kind: row.kind, title: row.title,
                keys: profile.barItems(in: row).filter { $0.savedID == nil },
                visibility: row.visibility.rawValue, alignment: row.resolvedAlignment,
                scrollStart: row.scrollStart ?? .automatic)
        }
    }
    func validate() throws {
        guard (1...TerminalControlsProfile.maximumKeyboardRows).contains(rows.count),
              Set(rows.map(\.id)).count == rows.count,
              rows.filter({ $0.kind == .main }).count == 1,
              rows.filter({ $0.kind == .numbers }).count <= 1,
              rows.filter({ $0.kind == .navigation }).count <= 1,
              rows.flatMap(\.keys).count <= 4096,
              rows.allSatisfy({ row in
                  !row.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && row.title.count <= 40
                  && TerminalKeyboardRow.Visibility(rawValue: row.visibility) != nil
                  && row.keys.allSatisfy { item in
                      switch item {
                      case .saved: false
                      case .control(let control): TerminalBarItem.Control.allCases.contains(control)
                      case .key(let key): TerminalKeyCatalog.key(key) != nil
                      }
                  }
              }) else { throw DirectCloudError.invalid }
    }
    func applying(to source: TerminalControlsProfile) throws -> TerminalControlsProfile {
        try validate()
        var result = source
        let oldRows = source.resolvedRows
        var retained = oldRows.map { ($0.id, source.barPlacements(in: $0).filter { $0.item.savedID != nil }) }
        var next = rows.map { value -> TerminalKeyboardRow in
            var row = TerminalKeyboardRow(id: value.id, kind: value.kind, title: value.title,
                alignment: value.alignment, scrollStart: value.scrollStart)
            row.visibility = TerminalKeyboardRow.Visibility(rawValue: value.visibility)!
            var placements = value.keys.enumerated().map {
                TerminalBarPlacement(id: "cloud-\(value.id.uuidString)-\($0.offset)", item: $0.element)
            }
            if let index = retained.firstIndex(where: { $0.0 == value.id }) {
                placements += retained[index].1
                retained[index].1 = []
            }
            row.placements = placements
            return row
        }
        // A remote row deletion must not silently delete this device's saved
        // text/shortcut buttons. Keep orphaned placements on the main row.
        let main = next.firstIndex { $0.kind == .main }!
        var placements = next[main].placements
        placements += retained.flatMap(\.1)
        next[main].placements = placements
        result.keyboardRows = next
        result.numberRow = nil; result.navigationRow = nil; result.expandedBar = nil; result.commandInBar = nil
        guard result.valid else { throw DirectCloudError.invalid }
        return result
    }
}

struct DirectCloudKeyboardVersion: Codable, Equatable {
    var schema = 1
    var family: TerminalControlsFamily
    var writer: UUID
    var revision: Int64
    var layout: DirectCloudKeyboardLayout
    var account: String { writer.uuidString.lowercased() + "." + family.rawValue }
    func validate() throws {
        guard schema == 1, (1...1_000_000_000).contains(revision) else { throw DirectCloudError.invalid }
        try layout.validate()
        // Retain the existing synchronizable-Keychain record bound. Oversized
        // local layouts remain usable; they produce a visible sync notice.
        guard try JSONEncoder().encode(self).count <= 4096 else { throw DirectCloudError.invalid }
    }
    static func merge(_ local: [Self], _ remote: [Self]) throws -> [Self] {
        guard local.count <= 512, remote.count <= 512 else { throw DirectCloudError.invalid }
        for batch in [local, remote] {
            guard Set(batch.map(\.account)).count == batch.count else { throw DirectCloudError.invalid }
            try batch.forEach { try $0.validate() }
        }
        var merged = Dictionary(uniqueKeysWithValues: local.map { ($0.account, $0) })
        for value in remote {
            if let prior = merged[value.account] {
                if prior.revision > value.revision { continue }
                guard prior.revision != value.revision || prior == value else { throw DirectCloudError.invalid }
            }
            merged[value.account] = value
        }
        guard merged.count <= 512 else { throw DirectCloudError.invalid }
        return merged.values.sorted { $0.account < $1.account }
    }
    static func winner(_ versions: [Self], family: TerminalControlsFamily) -> Self? {
        versions.filter { $0.family == family }.max {
            $0.revision == $1.revision ? $0.writer.uuidString < $1.writer.uuidString : $0.revision < $1.revision
        }
    }
}

/// Separate service/journal keeps 1.0's Mac metadata protocol unchanged.
@MainActor @Observable final class DirectKeyboardCloudSync {
    static let service = "media.jenny.maccompanion.cloud-keyboard-layouts.v1"
    private struct Journal: Codable { var schema = 1; var versions: [DirectCloudKeyboardVersion] }
    private let url: URL
    private let writer: UUID
    private let transport: any DirectCloudTransport
    private let stores: [String: TerminalControlsStore]
    private var versions: [DirectCloudKeyboardVersion] = []
    private var readable = true
    private var enabled = false
    private var applying = false
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private var rerun = false
    private var observer: KeyboardLayoutObserver?
    private(set) var busy = false
    private(set) var status = "Keyboard layout sync is off."
    init(url: URL, writer: UUID, transport: any DirectCloudTransport = DirectCloudKeychain(service: service),
         stores: [String: TerminalControlsStore] = [
            TerminalControlsFamily.terminal.rawValue: .init(),
            TerminalControlsFamily.remoteMac.rawValue: .remoteMac()
         ], observeChanges: Bool = true) {
        self.url = url; self.writer = writer; self.transport = transport; self.stores = stores
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: 2_097_153) ?? Data()
                guard data.count <= 2_097_152 else { throw DirectCloudError.invalid }
                let journal = try JSONDecoder().decode(Journal.self, from: data)
                guard journal.schema == 1 else { throw DirectCloudError.invalid }
                versions = try DirectCloudKeyboardVersion.merge([], journal.versions)
            }
        } catch { readable = false; status = "Keyboard sync history is unavailable. Local layouts are kept." }
        if observeChanges { observer = KeyboardLayoutObserver(NotificationCenter.default.addObserver(forName: TerminalControlsStore.changed, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.object as? String, let family = TerminalControlsFamily(rawValue: raw) else { return }
            MainActor.assumeIsolated { self?.localChange(family) }
        }) }
    }
    func setEnabled(_ value: Bool) {
        if enabled == value { if value { refresh() }; return }
        // Retain cancelled work until it drains. Keychain calls already in
        // progress cannot be cancelled, and removal must wait for their writes.
        enabled = value; generation = UUID(); task?.cancel(); busy = false; rerun = false
        if value { refresh() } else { status = "Keyboard layout sync is off. Existing cloud layouts are kept." }
    }
    func retry() {
        if !readable {
            do {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: 2_097_153) ?? Data()
                guard data.count <= 2_097_152 else { throw DirectCloudError.invalid }
                let journal = try JSONDecoder().decode(Journal.self, from: data)
                guard journal.schema == 1 else { throw DirectCloudError.invalid }
                versions = try DirectCloudKeyboardVersion.merge([], journal.versions)
                readable = true
            } catch { return }
        }
        refresh()
    }
    private func persist(_ next: [DirectCloudKeyboardVersion]) throws {
        let checked = try DirectCloudKeyboardVersion.merge([], next)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try DirectClientPlatformV1.write(JSONEncoder().encode(Journal(versions: checked)), to: url)
        versions = checked
    }
    func localChange(_ family: TerminalControlsFamily) {
        guard !applying, readable, DirectAppLockV1.shared.canAccess, let store = stores[family.rawValue] else { return }
        do {
            let layout = DirectCloudKeyboardLayout(try store.load())
            if DirectCloudKeyboardVersion.winner(versions, family: family)?.layout == layout { return }
            let record = DirectCloudKeyboardVersion(family: family, writer: writer,
                revision: (versions.map(\.revision).max() ?? 0) + 1, layout: layout)
            try record.validate()
            try persist(versions.filter { $0.account != record.account } + [record])
            if busy { rerun = true } else { refresh() }
        } catch { status = "This keyboard layout couldn’t sync. Local controls are kept; large layouts may exceed the sync limit." }
    }
    func refresh() {
        guard enabled, readable, !busy, DirectAppLockV1.shared.canAccess, DirectClientPlatformV1.sessionAvailable else { return }
        busy = true; generation = UUID(); let epoch = generation, transport = self.transport, prior = task
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.generation == epoch {
                    self.busy = false; self.task = nil
                    if self.rerun { self.rerun = false; self.refresh() }
                }
            }
            await prior?.value
            guard self.current(epoch) else { return }
            do {
                let data = try await Task.detached { try transport.read() }.value
                guard self.current(epoch) else { return }
                guard data.count <= 512, data.allSatisfy({ $0.count <= 4096 }) else { throw DirectCloudError.invalid }
                let incoming = try data.map { try JSONDecoder().decode(DirectCloudKeyboardVersion.self, from: $0) }
                var next = try DirectCloudKeyboardVersion.merge(self.versions, incoming)
                // Read cloud first. A new device's untouched default must never
                // overwrite an existing customized keyboard.
                for (name, store) in self.stores {
                    guard let family = TerminalControlsFamily(rawValue: name) else { continue }
                    if DirectCloudKeyboardVersion.winner(next, family: family) == nil {
                        let value = DirectCloudKeyboardVersion(family: family, writer: self.writer,
                            revision: (next.map(\.revision).max() ?? 0) + 1,
                            layout: DirectCloudKeyboardLayout(try store.load()))
                        try value.validate(); next.append(value)
                    }
                }
                // Validate every local result before applying either family.
                var changes: [(TerminalControlsStore, TerminalControlsProfile)] = []
                for (name, store) in self.stores {
                    guard let family = TerminalControlsFamily(rawValue: name),
                          let winner = DirectCloudKeyboardVersion.winner(next, family: family) else { continue }
                    let local = try store.load()
                    if DirectCloudKeyboardLayout(local) != winner.layout {
                        changes.append((store, try winner.layout.applying(to: local)))
                    }
                }
                do {
                    self.applying = true
                    defer { self.applying = false }
                    for (store, profile) in changes { _ = try store.save(profile) }
                }
                try self.persist(next)
                for value in next where value.writer == self.writer {
                    guard self.current(epoch) else { return }
                    let bytes = try JSONEncoder().encode(value), account = value.account
                    try await Task.detached { try transport.write(bytes, account: account) }.value
                }
                if self.current(epoch) { self.status = "Keyboard rows and built-in key choices sync. Saved shortcuts and text stay on this device." }
            } catch {
                if self.generation == epoch { self.status = "Keyboard layouts couldn’t sync. Local controls are kept. Retry with Refresh iCloud." }
            }
        }
    }
    private func current(_ epoch: UUID) -> Bool {
        enabled && generation == epoch && !Task.isCancelled
            && DirectAppLockV1.shared.canAccess && DirectClientPlatformV1.sessionAvailable
    }
    func removeCloudCopies() async throws {
        setEnabled(false)
        await task?.value
        task = nil
        let transport = transport
        try await Task.detached { try transport.removeAll() }.value
        try persist([])
    }
}
#endif
