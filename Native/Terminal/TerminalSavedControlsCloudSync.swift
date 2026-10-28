#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
import Observation
import CryptoKit

/// The optional projection contains saved definitions and placements, never a session.
struct DirectCloudSavedControl: Codable, Equatable {
    struct Bar: Codable, Equatable { var row: UUID; var placement: String; var index: Int }
    struct Menu: Codable, Equatable { var mode: String; var placement: UUID; var index: Int }
    var action: TerminalControlAction
    var bar: [Bar]
    var menus: [Menu]
    var libraryIndex: Int
    static func eligible(_ action: TerminalControlAction) -> Bool {
        guard action.kind == .shortcut || action.kind == .text else { return false }
        // These migrated built-ins have installation-local IDs. They are app defaults,
        // not saved custom definitions; publishing them would duplicate them on every device.
        if action.kind == .shortcut, action.steps == nil, action.confirmBeforeRunning == nil,
           action.presetID == nil, action.text.isEmpty {
            if action.title == "Interrupt · Ctrl-C", action.character == 0x63, action.modifiers == [0xffe3] { return false }
            if action.title == "Return", action.character == 0xff0d, action.modifiers.isEmpty { return false }
        }
        return true
    }
    static func project(_ profile: TerminalControlsProfile) -> [UUID: Self] {
        var profile = profile; profile.captureRemoteMenu()
        let menus = profile.remoteMenus ?? ["terminal": profile.resolvedMenuPlacements]
        return Dictionary(uniqueKeysWithValues: profile.actions.filter(eligible).map { action in
            var copy = action; copy.inRow = false; copy.inMenu = false
            let section: TerminalSavedItemsSection = action.kind == .text ? .text : .shortcuts
            return (action.id, Self(action: copy, bar: profile.resolvedRows.flatMap { row in
                profile.barPlacements(in: row).enumerated().compactMap { index, placement in
                    placement.item.savedID == action.id ? Bar(row: row.id, placement: placement.id, index: index) : nil
                }
            }, menus: menus.keys.sorted().flatMap { mode in
                menus[mode]!.enumerated().compactMap { index, placement in
                    placement.actionID == action.id ? Menu(mode: mode, placement: placement.id, index: index) : nil
                }
            }, libraryIndex: profile.savedItems(section).firstIndex(where: { $0.id == action.id }) ?? 0))
        })
    }
    func validate(family: TerminalControlsFamily) throws {
        let modes: Set<String> = family == .terminal ? ["terminal"] : ["desktop", "trackpad"]
        guard Self.eligible(action), action.valid, !action.inRow, !action.inMenu,
              (0..<4096).contains(libraryIndex), bar.count <= 4096, menus.count <= 4096,
              Set(bar.map(\.placement)).count == bar.count,
              Set(menus.map { $0.mode + "." + $0.placement.uuidString }).count == menus.count,
              bar.allSatisfy({ !$0.placement.isEmpty && $0.placement.utf8.count <= 256 && (0..<4096).contains($0.index) }),
              menus.allSatisfy({ modes.contains($0.mode) && (0..<4096).contains($0.index) }) else { throw DirectCloudError.invalid }
    }
    static func applying(_ values: [UUID: Self?], to source: TerminalControlsProfile) throws -> TerminalControlsProfile {
        guard !values.isEmpty else { return source }
        // Returning a migrated control to its untouched built-in form removes
        // the shared custom definition, but must keep this device's built-in.
        let applicable = values.filter { id, value in
            guard value == nil, let local = source.actions.first(where: { $0.id == id }) else { return true }
            return eligible(local)
        }
        guard !applicable.isEmpty else { return source }
        var result = source
        let managed = Set(applicable.keys)
        for (id, wrapped) in applicable {
            if let old = source.actions.first(where: { $0.id == id }), old.kind != .shortcut && old.kind != .text { throw DirectCloudError.invalid }
            if let value = wrapped {
                guard id == value.action.id else { throw DirectCloudError.invalid }
                try value.validate(family: source.family ?? .terminal)
            }
            result.delete(id)
        }
        let incoming = applicable.values.compactMap { $0 }.sorted {
            $0.libraryIndex == $1.libraryIndex ? $0.action.id.uuidString < $1.action.id.uuidString : $0.libraryIndex < $1.libraryIndex
        }
        result.actions += incoming.map(\.action)
        var rows = result.resolvedRows
        guard let main = rows.firstIndex(where: { $0.kind == .main }) else { throw DirectCloudError.invalid }
        let rowIDs = Set(rows.map(\.id)), mainID = rows[main].id
        for index in rows.indices {
            var placements = result.barPlacements(in: rows[index]).filter { placement in
                placement.item.savedID.map { !managed.contains($0) } ?? true
            }
            let rowID = rows[index].id
            var additions: [(Int, TerminalBarPlacement)] = []
            for item in incoming {
                for position in item.bar {
                    let target = rowIDs.contains(position.row) ? position.row : mainID
                    if target == rowID {
                        additions.append((position.index, TerminalBarPlacement(id: position.placement, item: .saved(item.action.id))))
                    }
                }
            }
            additions.sort { $0.0 == $1.0 ? $0.1.id < $1.1.id : $0.0 < $1.0 }
            var last = -1
            for (position, item) in additions {
                let target = min(max(position, last + 1), placements.count)
                placements.insert(item, at: target); last = target
            }
            rows[index].placements = placements
        }
        result.keyboardRows = rows
        var menus = result.remoteMenus ?? ["terminal": result.resolvedMenuPlacements]
        for mode in menus.keys.sorted() {
            var list = menus[mode]!.filter { !managed.contains($0.actionID) }
            var additions: [(Int, TerminalMenuPlacement)] = []
            for item in incoming {
                for position in item.menus where position.mode == mode {
                    additions.append((position.index, TerminalMenuPlacement(id: position.placement, actionID: item.action.id)))
                }
            }
            additions.sort { $0.0 == $1.0 ? $0.1.id.uuidString < $1.1.id.uuidString : $0.0 < $1.0 }
            var last = -1
            for (position, item) in additions {
                let target = min(max(position, last + 1), list.count); list.insert(item, at: target); last = target
            }
            menus[mode] = list
        }
        if result.family == .remoteMac {
            result.remoteMenus = menus
            result.menuPlacements = menus[result.remoteMenuMode ?? "desktop"] ?? []
        } else { result.menuPlacements = menus["terminal"] ?? [] }
        let barIDs = Set(rows.flatMap(\.actionIDs)), menuIDs = Set(result.resolvedMenuPlacements.map(\.actionID))
        for index in result.actions.indices {
            result.actions[index].inRow = barIDs.contains(result.actions[index].id)
            result.actions[index].inMenu = menuIDs.contains(result.actions[index].id)
        }
        for section in [TerminalSavedItemsSection.shortcuts, .text] {
            var order = source.savedItems(section).map(\.id).filter { !managed.contains($0) }
            let additions = incoming.filter { $0.action.kind == section.kind }.sorted {
                $0.libraryIndex == $1.libraryIndex ? $0.action.id.uuidString < $1.action.id.uuidString : $0.libraryIndex < $1.libraryIndex
            }
            var last = -1
            for item in additions {
                let target = min(max(item.libraryIndex, last + 1), order.count)
                order.insert(item.action.id, at: target); last = target
            }
            if section == .shortcuts { result.shortcutOrder = order } else { result.textOrder = order }
        }
        guard result.valid else { throw DirectCloudError.invalid }
        return result
    }
}

struct DirectCloudSavedVersion: Codable, Equatable {
    static let maximumBytes = 32768
    var schema = 1
    var family: TerminalControlsFamily
    var id: UUID
    var writer: UUID
    var revision: Int64
    var value: DirectCloudSavedControl?
    var key: String { family.rawValue + "." + id.uuidString.lowercased() }
    var account: String { family.rawValue + "." + writer.uuidString.lowercased() + "." + id.uuidString.lowercased() }
    func encoded() throws -> Data { let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys; return try encoder.encode(self) }
    func validate() throws {
        guard schema == 1, (1...1_000_000_000).contains(revision), value?.action.id == id || value == nil else { throw DirectCloudError.invalid }
        try value?.validate(family: family)
        guard try encoded().count <= Self.maximumBytes else { throw DirectCloudError.invalid }
    }
    static func merge(_ local: [Self], _ remote: [Self]) throws -> [Self] {
        guard local.count <= 512, remote.count <= 512 else { throw DirectCloudError.invalid }
        for list in [local, remote] {
            guard Set(list.map(\.account)).count == list.count else { throw DirectCloudError.invalid }
            try list.forEach { try $0.validate() }
        }
        var result = Dictionary(uniqueKeysWithValues: local.map { ($0.account, $0) })
        for value in remote {
            if let old = result[value.account] {
                if old.revision > value.revision { continue }
                guard old.revision != value.revision || old == value else { throw DirectCloudError.invalid }
            }
            result[value.account] = value
        }
        guard result.count <= 512 else { throw DirectCloudError.invalid }
        return result.values.sorted { $0.account < $1.account }
    }
    static func winners(_ versions: [Self]) -> [String: Self] {
        versions.reduce(into: [:]) { result, value in
            if let old = result[value.key], old.revision > value.revision || old.revision == value.revision && old.writer.uuidString > value.writer.uuidString { return }
            result[value.key] = value
        }
    }
}

/// Immutable pieces plus a last-written head keep a partial write from replacing a complete version.
struct DirectSavedControlsTransport: DirectCloudTransport {
    static let service = "media.jenny.maccompanion.cloud-saved-controls.v1"
    static let pieceBytes = 2000
    struct Wire: Codable {
        var schema = 1
        var account: String
        var generation: UUID
        var index: Int?
        var pieces: Int?
        var total: Int?
        var digest: String?
        var data: Data?
        var slot: String { account + (index.map { "." + generation.uuidString.lowercased() + ".part.\($0)" } ?? ".head") }
        func validate() throws {
            let parts = account.split(separator: ".")
            guard schema == 1, parts.count == 3, TerminalControlsFamily(rawValue: String(parts[0])) != nil,
                  UUID(uuidString: String(parts[1])) != nil, UUID(uuidString: String(parts[2])) != nil else { throw DirectCloudError.invalid }
            if let index {
                guard (0..<17).contains(index), let data, (1...DirectSavedControlsTransport.pieceBytes).contains(data.count),
                      pieces == nil, total == nil, digest == nil else { throw DirectCloudError.invalid }
            } else {
                guard let pieces, (1...17).contains(pieces), let total, (1...DirectCloudSavedVersion.maximumBytes).contains(total),
                      pieces == (total + DirectSavedControlsTransport.pieceBytes - 1) / DirectSavedControlsTransport.pieceBytes,
                      let digest, digest.count == 64, digest.allSatisfy({ "0123456789abcdef".contains($0) }), data == nil else { throw DirectCloudError.invalid }
            }
        }
    }
    let base: any DirectCloudTransport
    init(base: any DirectCloudTransport = DirectCloudKeychain(service: Self.service)) { self.base = base }
    static func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    private func wires() throws -> [Wire] {
        let bytes = try base.read()
        guard bytes.count <= 512, bytes.allSatisfy({ $0.count <= 4096 }) else { throw DirectCloudError.invalid }
        let wires = try bytes.map { try JSONDecoder().decode(Wire.self, from: $0) }
        try wires.forEach { try $0.validate() }
        guard Set(wires.map(\.slot)).count == wires.count else { throw DirectCloudError.invalid }
        return wires
    }
    func read() throws -> [Data] {
        let wires = try wires()
        return try Dictionary(grouping: wires, by: \.account).keys.sorted().map { account in
            let records = wires.filter { $0.account == account }
            guard let head = records.first(where: { $0.index == nil }) else { throw DirectCloudError.storage }
            var data = Data()
            for index in 0..<head.pieces! {
                guard let part = records.first(where: { $0.generation == head.generation && $0.index == index }),
                      let bytes = part.data else { throw DirectCloudError.storage }
                data.append(bytes)
            }
            guard data.count == head.total, Self.digest(data) == head.digest else { throw DirectCloudError.storage }
            let value = try JSONDecoder().decode(DirectCloudSavedVersion.self, from: data)
            try value.validate(); guard value.account == account else { throw DirectCloudError.invalid }
            return data
        }
    }
    func write(_ data: Data, account: String) throws {
        let value = try JSONDecoder().decode(DirectCloudSavedVersion.self, from: data)
        try value.validate(); guard value.account == account, data.count <= DirectCloudSavedVersion.maximumBytes else { throw DirectCloudError.invalid }
        let digest = Self.digest(data), raw = String(digest.prefix(32))
        let formatted = "\(raw.prefix(8))-\(raw.dropFirst(8).prefix(4))-\(raw.dropFirst(12).prefix(4))-\(raw.dropFirst(16).prefix(4))-\(raw.dropFirst(20))"
        guard let generation = UUID(uuidString: formatted) else { throw DirectCloudError.invalid }
        let chunks = stride(from: 0, to: data.count, by: Self.pieceBytes).enumerated().map { index, offset in
            Wire(account: account, generation: generation, index: index, data: data.subdata(in: offset..<min(offset + Self.pieceBytes, data.count)))
        }
        let head = Wire(account: account, generation: generation, pieces: chunks.count, total: data.count, digest: digest)
        let old = try wires(), next = chunks + [head]
        guard Set((old + next).map(\.slot)).count <= 512 else { throw DirectCloudError.storage }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        for record in next {
            try record.validate(); let bytes = try encoder.encode(record)
            guard bytes.count <= 4096 else { throw DirectCloudError.invalid }
            try base.write(bytes, account: record.slot)
        }
        let kept = Set(next.map(\.slot))
        for record in old where record.account == account && !kept.contains(record.slot) { try base.remove(account: record.slot) }
    }
    func removeAll() throws { try base.removeAll() }
}

private final class SavedControlsObservers: @unchecked Sendable {
    let tokens: [NSObjectProtocol]
    init(_ tokens: [NSObjectProtocol]) { self.tokens = tokens }
    deinit { tokens.forEach { NotificationCenter.default.removeObserver($0) } }
}

@MainActor @Observable final class DirectSavedControlsCloudSync {
    private struct Pending: Codable { var family: TerminalControlsFamily; var id: UUID; var value: DirectCloudSavedControl?; var key: String { family.rawValue + "." + id.uuidString.lowercased() } }
    private struct Journal: Codable {
        var schema = 1
        var versions: [DirectCloudSavedVersion] = []
        var observed: [String: String] = [:]
        var pending: [Pending] = []
        var seeded: Set<String> = []
        var unpublished: Set<String> = []
    }
    private let writer: UUID
    private let transport: any DirectCloudTransport
    private let stores: [String: TerminalControlsStore]
    private let canAccess: @MainActor () -> Bool
    private let readJournal: @MainActor () throws -> Data?
    private let writeJournal: @MainActor (Data) throws -> Void
    private var journal = Journal()
    private var loaded = false
    private var readable = true
    private var enabled = false
    private var applying = false
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private var rerun = false
    private var observer: SavedControlsObservers?
    private(set) var busy = false
    private(set) var status = "Shortcuts and saved text stay on this device."
    init(writer: UUID, transport: any DirectCloudTransport = DirectSavedControlsTransport(),
         stores: [String: TerminalControlsStore] = ["terminal": .init(), "remoteMac": .remoteMac()],
         observeChanges: Bool = true, canAccess: @escaping @MainActor () -> Bool = { DirectAppLockV1.shared.canAccess },
         readJournal: (@MainActor () throws -> Data?)? = nil, writeJournal: (@MainActor (Data) throws -> Void)? = nil) {
        self.writer = writer; self.transport = transport; self.stores = stores; self.canAccess = canAccess
        self.readJournal = readJournal ?? { try TerminalSecretStore.read(writer, kind: "saved-controls-cloud-journal-v1") }
        self.writeJournal = writeJournal ?? { try TerminalSecretStore.write($0, id: writer, kind: "saved-controls-cloud-journal-v1") }
        if canAccess() { do { try prepare(); try observe(markChanges: true) } catch { failJournal() } }
        if observeChanges {
            var tokens: [NSObjectProtocol] = []
            for name in [TerminalControlsStore.willChange, TerminalControlsStore.changed, TerminalControlsStore.prepared] {
                tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    let cloudImport = note.userInfo?["cloudImport"] as? Bool == true
                    MainActor.assumeIsolated {
                        guard let self, !self.applying, self.canAccess(), self.readable else { return }
                        do {
                            try self.prepare()
                            let changed = try self.observe(markChanges: !cloudImport)
                            if name != TerminalControlsStore.willChange && (changed || cloudImport || name == TerminalControlsStore.prepared) {
                                if self.busy { self.rerun = true } else { self.refresh() }
                            }
                        } catch { self.failJournal() }
                    }
                })
            }
            observer = SavedControlsObservers(tokens)
        }
    }
    private func failJournal() { readable = false; status = "Saved-content sync history is unavailable. Local shortcuts and text are kept. Retry with Refresh iCloud." }
    private func prepare() throws {
        guard canAccess() else { throw DirectCloudError.locked }
        guard !loaded else { return }
        if let data = try readJournal() {
            guard data.count <= 20 * 1024 * 1024 else { throw DirectCloudError.invalid }
            let restored = try JSONDecoder().decode(Journal.self, from: data)
            guard restored.schema == 1, restored.observed.count <= 8192, restored.pending.count <= 8192,
                  restored.seeded.isSubset(of: Set(stores.keys)), Set(restored.pending.map(\.key)).count == restored.pending.count,
                  restored.observed.keys.allSatisfy({ key in
                      let pieces = key.split(separator: ".")
                      return pieces.count == 2 && stores[String(pieces[0])] != nil && UUID(uuidString: String(pieces[1])) != nil
                  }),
                  restored.observed.values.allSatisfy({ $0.count == 64 && $0.allSatisfy { "0123456789abcdef".contains($0) } }) else { throw DirectCloudError.invalid }
            _ = try DirectCloudSavedVersion.merge([], restored.versions)
            guard restored.unpublished.isSubset(of: Set(restored.versions.filter { $0.writer == writer }.map(\.account))) else { throw DirectCloudError.invalid }
            for pending in restored.pending {
                try pending.value?.validate(family: pending.family)
                guard stores[pending.family.rawValue] != nil, pending.value?.action.id == pending.id || pending.value == nil else { throw DirectCloudError.invalid }
            }
            journal = restored
        }
        loaded = true
    }
    private func persist() throws {
        guard canAccess() else { throw DirectCloudError.locked }
        do {
            let data = try JSONEncoder().encode(journal)
            guard data.count <= 20 * 1024 * 1024 else { throw DirectCloudError.invalid }
            try writeJournal(data)
        } catch { failJournal(); throw error }
    }
    private static func hash(_ value: DirectCloudSavedControl) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return DirectSavedControlsTransport.digest(try encoder.encode(value))
    }
    @discardableResult private func observe(markChanges: Bool) throws -> Bool {
        guard canAccess() else { throw DirectCloudError.locked }
        let known = DirectCloudSavedVersion.winners(journal.versions)
        var changed = false
        for name in stores.keys.sorted() {
            guard let family = TerminalControlsFamily(rawValue: name), let store = stores[name],
                  let profile = try store.savedControlsCloudProfile() else { continue }
            let current = DirectCloudSavedControl.project(profile)
            var normalized: [UUID: DirectCloudSavedControl]?, attemptedNormalization = false
            let keys = Set(current.keys.map { name + "." + $0.uuidString.lowercased() })
                .union(journal.observed.keys.filter { $0.hasPrefix(name + ".") })
            for key in keys.sorted() {
                guard let id = UUID(uuidString: String(key.dropFirst(name.count + 1))) else { throw DirectCloudError.invalid }
                let value = current[id], hash = try value.map(Self.hash)
                if journal.observed[key] != hash || !journal.seeded.contains(name) {
                    if markChanges {
                        journal.pending.removeAll { $0.key == key }
                        var imported = known[key] != nil && known[key]?.value == value
                        if !imported, known[key] != nil {
                            if !attemptedNormalization {
                                attemptedNormalization = true
                                let familyValues = Dictionary(uniqueKeysWithValues: known.values.filter { $0.family == family }.map { ($0.id, $0.value) })
                                if let applied = try? DirectCloudSavedControl.applying(familyValues, to: profile) {
                                    normalized = DirectCloudSavedControl.project(applied)
                                }
                            }
                            imported = normalized.map { $0[id] == value } ?? false
                        }
                        if !imported {
                            journal.pending.append(Pending(family: family, id: id, value: value))
                        }
                    }
                    journal.observed[key] = hash; changed = true
                }
            }
            if journal.seeded.insert(name).inserted { changed = true }
        }
        if changed { try persist() }
        return changed
    }
    func localChange() {
        guard !applying, readable, canAccess() else { return }
        do { try prepare(); if try observe(markChanges: true) { if busy { rerun = true } else { refresh() } } }
        catch { failJournal() }
    }
    func setEnabled(_ value: Bool) {
        if enabled == value { if value { refresh() }; return }
        enabled = value; generation = UUID(); task?.cancel(); busy = false; rerun = false
        if value { refresh() } else { status = "Shortcuts and saved-text sync is off. Existing cloud copies are kept." }
    }
    func retry() { readable = true; loaded = false; refresh() }
    private func current(_ epoch: UUID) -> Bool { enabled && readable && generation == epoch && !Task.isCancelled && canAccess() && DirectClientPlatformV1.sessionAvailable }
    private func publish(_ epoch: UUID) async throws {
        for account in journal.unpublished.sorted() {
            guard current(epoch), let value = journal.versions.first(where: { $0.account == account && $0.writer == writer }) else { return }
            let bytes = try value.encoded(), transport = self.transport
            try await Task.detached { try transport.write(bytes, account: account) }.value
            guard current(epoch) else { return }
            journal.unpublished.remove(account); try persist()
        }
    }
    func refresh() {
        guard enabled, readable, !busy, canAccess(), DirectClientPlatformV1.sessionAvailable else { return }
        do {
            try prepare()
            // Terminal migration has no Mac context. Commit it through its owner
            // only after effective opt-in; baseline observers never invent IDs.
            applying = true
            do { defer { applying = false }; if let terminal = stores[TerminalControlsFamily.terminal.rawValue] { _ = try terminal.load() } }
            try observe(markChanges: true)
        } catch { failJournal(); return }
        busy = true; generation = UUID(); let epoch = generation, prior = task, transport = self.transport
        task = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == epoch { self.busy = false; self.task = nil; if self.rerun { self.rerun = false; self.refresh() } } }
            await prior?.value
            guard self.current(epoch) else { return }
            do {
                // Repair only previously admitted, durably journaled writes before reading partial delivery.
                try await self.publish(epoch)
                guard self.current(epoch) else { return }
                let data = try await Task.detached { try transport.read() }.value
                guard self.current(epoch) else { return }
                guard data.count <= 512, data.allSatisfy({ $0.count <= DirectCloudSavedVersion.maximumBytes }) else { throw DirectCloudError.invalid }
                let incoming = try data.map { try JSONDecoder().decode(DirectCloudSavedVersion.self, from: $0) }
                self.journal.versions = try DirectCloudSavedVersion.merge(self.journal.versions, incoming)
                try self.persist() // Fetched clocks precede local rebasing and every import.
                try self.observe(markChanges: true)
                var retained: [Pending] = [], candidate = self.journal
                for pending in candidate.pending {
                    let revision = (candidate.versions.map(\.revision).max() ?? 0) + 1
                    let value = DirectCloudSavedVersion(family: pending.family, id: pending.id, writer: self.writer, revision: revision, value: pending.value)
                    do { try value.validate() } catch { retained.append(pending); continue }
                    candidate.versions = try DirectCloudSavedVersion.merge(candidate.versions.filter { $0.account != value.account }, [value])
                    candidate.unpublished.insert(value.account)
                }
                candidate.pending = retained
                self.journal = candidate; try self.persist()
                let winners = DirectCloudSavedVersion.winners(self.journal.versions), waiting = Set(retained.map(\.key))
                var changes: [(TerminalControlsStore, TerminalControlsProfile)] = []
                var waitingForControls = false
                for name in self.stores.keys.sorted() {
                    guard let store = self.stores[name] else { continue }
                    guard let local = try store.savedControlsCloudProfile() else { waitingForControls = true; continue }
                    let versions = winners.values.filter { $0.family.rawValue == name && !waiting.contains($0.key) }
                    let values = Dictionary(uniqueKeysWithValues: versions.map { ($0.id, $0.value) })
                    let next = try DirectCloudSavedControl.applying(values, to: local)
                    if next != local { changes.append((store, next)) }
                }
                self.applying = true
                do {
                    defer { self.applying = false }
                    for (store, profile) in changes { _ = try store.save(profile, cloudImport: true) }
                    try self.observe(markChanges: false)
                }
                try self.persist()
                try await self.publish(epoch)
                if self.current(epoch) {
                    self.status = !retained.isEmpty ? "Some saved controls exceed the sync limit. Their local content is kept."
                        : waitingForControls ? "Open the session controls once to finish preparing saved content."
                        : "Saved shortcuts, text and button positions sync."
                }
            } catch {
                if self.generation == epoch && self.readable { self.status = "Shortcuts and saved text couldn’t sync. Local content is kept. Retry with Refresh iCloud." }
            }
        }
    }
    func removeCloudCopies() async throws {
        setEnabled(false); await task?.value; task = nil
        guard canAccess() else { throw DirectCloudError.locked }
        let transport = self.transport
        try await Task.detached { try transport.removeAll() }.value
        journal = Journal(); loaded = true; readable = true; try persist()
    }
}
#endif
