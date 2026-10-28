#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
import Observation
import CryptoKit

private final class KeyboardLayoutObserver: @unchecked Sendable {
    let tokens: [NSObjectProtocol]
    init(_ tokens: [NSObjectProtocol]) { self.tokens = tokens }
    deinit { tokens.forEach { NotificationCenter.default.removeObserver($0) } }
}

/// Only layout metadata crosses devices. Saved definitions and their placements
/// are deliberately absent, including shortcuts that contain literal text.
struct DirectCloudKeyboardLayout: Codable, Equatable {
    struct Row: Codable, Equatable {
        var id: UUID
        var kind: TerminalKeyboardRow.Kind
        var preset: TerminalRowPreset?
        var title: String
        var keys: [TerminalBarItem]
        var visibility: String
        var alignment: TerminalKeyboardRow.Alignment
        var scrollStart: TerminalKeyboardRow.ScrollStart
    }
    var rows: [Row]
    init(_ profile: TerminalControlsProfile) {
        rows = profile.resolvedRows.map { row in
            Row(id: row.id, kind: row.kind, preset: row.preset, title: row.title,
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
        var occupied = Set(retained.flatMap { $0.1.map(\.id) })
        var next = rows.map { value -> TerminalKeyboardRow in
            var row = TerminalKeyboardRow(id: value.id, kind: value.kind, title: value.title,
                preset: value.preset ?? oldRows.first(where: { $0.id == value.id })?.preset
                    ?? (value.id == TerminalKeyboardRow.numbersID ? .numbers : nil),
                alignment: value.alignment, scrollStart: value.scrollStart)
            row.visibility = TerminalKeyboardRow.Visibility(rawValue: value.visibility)!
            var placements = value.keys.enumerated().map { index, item in
                let base = "cloud-\(value.id.uuidString)-\(index)"
                var id = base, suffix = 0
                while !occupied.insert(id).inserted { suffix += 1; id = base + "-\(suffix)" }
                return TerminalBarPlacement(id: id, item: item)
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
        // Commit the final saved-button positions with the imported rows. The
        // saved-content engine may be paused and must not repair this later.
        result = try DirectCloudSavedControl.applying(DirectCloudSavedControl.project(source).mapValues { Optional($0) }, to: result)
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
    var context: [String: Int64]?
    var account: String { writer.uuidString.lowercased() + "." + family.rawValue }
    func validate() throws {
        guard schema == 1, (1...1_000_000_000).contains(revision) else { throw DirectCloudError.invalid }
        guard DirectControlsCausality.valid(context ?? [:], before: revision) else { throw DirectCloudError.invalid }
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
    static func frontier(_ versions: [Self], family: TerminalControlsFamily) -> [Self] {
        let values = versions.filter { $0.family == family }
        return values.filter { value in !values.contains { other in
            other.writer == value.writer ? other.revision > value.revision
                : DirectControlsCausality.sees(other.context, writer: value.writer, revision: value.revision)
        } }
    }
    static func winner(_ versions: [Self], family: TerminalControlsFamily) -> Self? {
        frontier(versions, family: family).max {
            $0.revision == $1.revision ? $0.writer.uuidString < $1.writer.uuidString : $0.revision < $1.revision
        }
    }
}

/// Separate service/journal keeps 1.0's Mac metadata protocol unchanged.
@MainActor @Observable final class DirectKeyboardCloudSync {
    static let service = "media.jenny.maccompanion.cloud-keyboard-layouts.v1"
    private struct Journal: Codable {
        var schema = 1
        var writer: UUID?
        var appliedImports: [String: UUID]?
        var versions: [DirectCloudKeyboardVersion]
        // Hashes identify projected changes without duplicating private definitions.
        var observed: [String: String]?
        var pending: [String]?
        var reseeding: [String]?
        var resetClocks: [String: [String: Int64]]?
    }
    private static let maximumJournalBytes = 3_145_728
    private let readJournalData: @MainActor () throws -> Data?
    private let writer: UUID
    private let transport: any DirectCloudTransport
    private let stores: [String: TerminalControlsStore]
    private let writeJournalData: @MainActor (Data) throws -> Void
    private let canAccess: @MainActor () -> Bool
    private var versions: [DirectCloudKeyboardVersion] = []
    // Validated fetches survive a failed journal write in this process. Reset
    // must durably preserve them before it is allowed to delete cloud copies.
    private var unpersistedFetch: [DirectCloudKeyboardVersion] = []
    private var observed: [String: String] = [:]
    private var appliedImports: [String: UUID] = [:]
    private var pending: Set<String> = []
    private var reseeding: Set<String> = []
    private var resetClocks: [String: [String: Int64]] = [:]
    private var journalLoaded = false
    private var readable = true
    private var enabled = false
    private var applying = false
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private var rerun = false
    private var recoveryTask: Task<Void, Never>?
    private var recoveryAttempt = 0
    private let recoveryDelays: [Duration]
    private var observer: KeyboardLayoutObserver?
    private(set) var busy = false
    private(set) var issue: DirectCloudSyncIssue?
    private(set) var status = "Keyboard layout sync is off."
    init(url: URL? = nil, writer: UUID, transport: any DirectCloudTransport = DirectCloudKeychain(service: service),
         stores: [String: TerminalControlsStore] = [
            TerminalControlsFamily.terminal.rawValue: .init(),
            TerminalControlsFamily.remoteMac.rawValue: .remoteMac()
         ], observeChanges: Bool = true,
         canAccess: @escaping @MainActor () -> Bool = { DirectAppLockV1.shared.canAccess },
         writeJournal: (@MainActor (Data, URL) throws -> Void)? = nil,
         recoveryDelays: [Duration] = [.seconds(2), .seconds(5), .seconds(15)]) {
        self.writer = writer; self.transport = transport; self.stores = stores; self.canAccess = canAccess
        self.recoveryDelays = recoveryDelays
        // File injection is for synthetic tests only. Production history shares
        // the device-only lifetime of controls and the sync writer identity.
        if let url {
            self.readJournalData = {
                guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
                return try file.read(upToCount: Self.maximumJournalBytes + 1)
            }
            self.writeJournalData = { data in
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if let writeJournal { try writeJournal(data, url) } else { try DirectClientPlatformV1.write(data, to: url) }
            }
        } else {
            self.readJournalData = { try TerminalSecretStore.read(writer, kind: "keyboard-cloud-journal-v1") }
            self.writeJournalData = { try TerminalSecretStore.write($0, id: writer, kind: "keyboard-cloud-journal-v1") }
        }
        do {
            if canAccess() { try readJournal() }
            if canAccess(), try captureBaselines() { try persist(versions) }
        } catch { readable = false; issue = .storage; status = "Keyboard sync history is unavailable. Local layouts are kept." }
        if observeChanges {
            let willChange = NotificationCenter.default.addObserver(forName: TerminalControlsStore.willChange, object: nil, queue: .main) { [weak self] note in
                guard note.userInfo?["cloudImport"] as? Bool != true, let raw = note.object as? String else { return }
                MainActor.assumeIsolated {
                    guard let self, self.stores[raw] != nil else { return }
                    self.prepareForLocalSave()
                }
            }
            let changed = NotificationCenter.default.addObserver(forName: TerminalControlsStore.changed, object: nil, queue: .main) { [weak self] note in
                guard note.userInfo?["cloudImport"] as? Bool != true, let raw = note.object as? String, let family = TerminalControlsFamily(rawValue: raw) else { return }
                MainActor.assumeIsolated { self?.localChange(family) }
            }
            let prepared = NotificationCenter.default.addObserver(forName: TerminalControlsStore.prepared, object: nil, queue: .main) { [weak self] note in
                guard let raw = note.object as? String else { return }
                MainActor.assumeIsolated {
                    guard let self, self.stores[raw] != nil, self.enabled, self.readable, !self.applying else { return }
                    if self.busy { self.rerun = true } else { self.refresh() }
                }
            }
            observer = KeyboardLayoutObserver([willChange, changed, prepared])
        }
    }
    private static func fingerprint(_ layout: DirectCloudKeyboardLayout) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data: try encoder.encode(layout)).map { String(format: "%02x", $0) }.joined()
    }
    private func readJournal() throws {
        guard canAccess() else { throw DirectCloudError.locked }
        guard let data = try readJournalData() else { journalLoaded = true; return }
        guard data.count <= Self.maximumJournalBytes else { throw DirectCloudError.invalid }
        let journal = try JSONDecoder().decode(Journal.self, from: data)
        let checked = try Self.validated(journal, writer: writer)
        versions = checked.versions; observed = checked.observed ?? [:]; pending = Set(checked.pending ?? [])
        reseeding = Set(checked.reseeding ?? []); appliedImports = checked.appliedImports ?? [:]
        resetClocks = try checked.resetClocks ?? Self.snapshotResetClocks(checked.versions, families: reseeding)
        journalLoaded = true
    }
    private static func validated(_ journal: Journal, writer: UUID) throws -> Journal {
        guard journal.writer == writer else { return Journal(writer: writer, versions: []) }
        let families = Set([TerminalControlsFamily.terminal.rawValue, TerminalControlsFamily.remoteMac.rawValue])
        let hashes = journal.observed ?? [:], waiting = journal.pending ?? [], reset = journal.reseeding ?? []
        guard journal.schema == 1, Set(hashes.keys).isSubset(of: families),
              Set((journal.appliedImports ?? [:]).keys).isSubset(of: families),
              hashes.values.allSatisfy({ $0.count == 64 && $0.allSatisfy { "0123456789abcdef".contains($0) } }),
              reset.count == Set(reset).count, Set(reset).isSubset(of: families),
              waiting.count == Set(waiting).count, Set(waiting).isSubset(of: Set(hashes.keys)) else { throw DirectCloudError.invalid }
        guard Set((journal.resetClocks ?? [:]).keys).isSubset(of: Set(reset)),
              (journal.resetClocks ?? [:]).values.allSatisfy({ DirectControlsCausality.valid($0) }) else { throw DirectCloudError.invalid }
        let checked = try DirectCloudKeyboardVersion.merge([], journal.versions)
        var result = journal; result.versions = checked; return result
    }
    private static func snapshotResetClocks(_ versions: [DirectCloudKeyboardVersion], families: Set<String>) throws -> [String: [String: Int64]] {
        let result = Dictionary(uniqueKeysWithValues: families.map { name in
            (name, DirectControlsCausality.join(versions.filter { $0.family.rawValue == name }.map {
                DirectControlsCausality.including($0.context, writer: $0.writer, revision: $0.revision)
            }))
        })
        guard result.values.allSatisfy({ DirectControlsCausality.valid($0) }) else { throw DirectCloudError.invalid }
        return result
    }
    /// Establish a baseline before the first save, including when sync is off.
    /// Old journals use their last known winner so a crash before notification
    /// or a failed write cannot turn a later local edit into an untouched default.
    private func captureBaselines() throws -> Bool {
        if !journalLoaded { try readJournal() }
        var changed = false
        for (name, store) in stores {
            guard let family = TerminalControlsFamily(rawValue: name) else { continue }
            let profile = try store.load(persistMigrations: false)
            if let receipt = profile.syncState.layoutImport, appliedImports[name] != receipt.id {
                observed[name] = receipt.observed; appliedImports[name] = receipt.id; changed = true
            }
            guard observed[name] == nil else { continue }
            let layout = DirectCloudKeyboardLayout(profile)
            let previous = try store.keyboardCloudReady() ? DirectCloudKeyboardVersion.winner(versions, family: family)?.layout : nil
            observed[name] = try Self.fingerprint(previous ?? layout)
            let value = DirectCloudKeyboardVersion(family: family, writer: writer, revision: 1, layout: layout)
            if (try? value.validate()) == nil { pending.insert(name) }
            changed = true
        }
        return changed
    }
    /// Bounded automatic recovery never replaces unreadable history. Foreground
    /// refresh and explicit retry can try again after this short backoff ends.
    private func scheduleRecovery() {
        guard enabled, !busy, issue == .storage, recoveryTask == nil, recoveryAttempt < recoveryDelays.count else { return }
        let delay = recoveryDelays[recoveryAttempt]; recoveryAttempt += 1
        recoveryTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.recoveryTask = nil; self.refresh()
        }
    }
    private func recovered() {
        recoveryAttempt = 0; recoveryTask?.cancel(); recoveryTask = nil
    }
    func setEnabled(_ value: Bool) {
        if enabled == value { if value { refresh() }; return }
        // Retain cancelled work until it drains. Keychain calls already in
        // progress cannot be cancelled, and removal must wait for their writes.
        enabled = value; generation = UUID(); task?.cancel(); busy = false; rerun = false
        recoveryTask?.cancel(); recoveryTask = nil; recoveryAttempt = 0
        if value { refresh() } else { status = "Keyboard layout sync is off. Existing cloud layouts are kept." }
    }
    func retry() {
        if busy { rerun = true; return }
        refresh()
    }
    private func persist(_ next: [DirectCloudKeyboardVersion]) throws {
        let checked = try DirectCloudKeyboardVersion.merge(next, unpersistedFetch)
        let data = try JSONEncoder().encode(Journal(writer: writer, appliedImports: appliedImports, versions: checked, observed: observed, pending: pending.sorted(), reseeding: reseeding.sorted(), resetClocks: resetClocks))
        guard data.count <= Self.maximumJournalBytes else { throw DirectCloudError.invalid }
        do {
            try writeJournalData(data)
        } catch { readable = false; throw error }
        versions = checked; unpersistedFetch = []
    }
    /// A locked startup cannot read local controls. Capture their still-stored
    /// projection before the first later save, including while cloud sync is off.
    private func prepareForLocalSave() {
        guard !applying, readable, canAccess() else { return }
        do { if try captureBaselines() { try persist(versions) } }
        catch {
            readable = false
            issue = .storage
            status = "Keyboard sync history couldn’t be saved. Local controls are kept. Retry with Refresh iCloud."
            scheduleRecovery()
        }
    }
    func localChange(_ family: TerminalControlsFamily) {
        recordLocalChange(family, scheduleRefresh: true)
    }
    private func recordLocalChange(_ family: TerminalControlsFamily, scheduleRefresh: Bool) {
        guard !applying, readable, canAccess(), let store = stores[family.rawValue] else { return }
        do {
            guard try store.keyboardCloudReady() else { return }
            if try captureBaselines() { try persist(versions) }
            let layout = DirectCloudKeyboardLayout(try store.load()), name = family.rawValue
            let hash = try Self.fingerprint(layout)
            guard observed[name] != hash || pending.contains(name) || reseeding.contains(name) else { return }
            observed[name] = hash; pending.insert(name)
            if !reseeding.contains(name), DirectCloudKeyboardVersion.winner(versions, family: family)?.layout == layout {
                pending.remove(name); try persist(versions); return
            }
            let previous = versions.filter { $0.family == family && $0.writer == writer }.map {
                DirectControlsCausality.including($0.context, writer: $0.writer, revision: $0.revision)
            }
            // Freeze reset ancestry before deletion. First-fetch offline edits are
            // concurrent alternatives, not edits the reset already observed.
            let resetClock = reseeding.contains(name) ? resetClocks[name] ?? [:] : [:]
            let context = DirectControlsCausality.join([try store.load().syncState.layoutClock, resetClock] + previous)
            let record = DirectCloudKeyboardVersion(family: family, writer: writer,
                revision: max(versions.map(\.revision).max() ?? 0, context.values.max() ?? 0) + 1, layout: layout, context: context)
            do { try record.validate() }
            catch {
                // Publication limits never authorize replacing this local edit.
                try persist(versions)
                issue = .capacity
                status = "This keyboard layout couldn’t sync. Local controls are kept; large layouts may exceed the sync limit."
                return
            }
            let wasReseeding = reseeding.remove(name) != nil
            let retainedResetClock = resetClocks.removeValue(forKey: name)
            pending.remove(name)
            do { try persist(versions.filter { $0.account != record.account } + [record]) }
            catch { pending.insert(name); if wasReseeding { reseeding.insert(name) }; resetClocks[name] = retainedResetClock; throw error }
            if scheduleRefresh { if busy { rerun = true } else { refresh() } }
        } catch {
            // Retry reads the last durable baseline and compares the current
            // profile again before any cloud value can be applied.
            readable = false
            issue = .storage
            status = "Keyboard sync history couldn’t be saved. Local controls are kept. Retry with Refresh iCloud."
            scheduleRecovery()
        }
    }
    func refresh() {
        guard enabled, !busy, canAccess(), DirectClientPlatformV1.sessionAvailable else { return }
        recoveryTask?.cancel(); recoveryTask = nil
        do {
            if !readable {
                try readJournal()
                _ = try captureBaselines()
                try persist(versions)
                readable = true
            }
            // Initialize both families before reading cloud. The app has one
            // sync switch; preparing controls never needs a Mac or a session.
            applying = true
            do { defer { applying = false }; for store in stores.values { _ = try store.load() } }
            if try captureBaselines() { try persist(versions) }
        }
        catch { readable = false; issue = .storage; status = "Keyboard sync history is unavailable. Local layouts are kept."; scheduleRecovery(); return }
        busy = true; generation = UUID(); let epoch = generation, transport = self.transport, prior = task
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.generation == epoch {
                    self.busy = false; self.task = nil
                    if self.rerun { self.rerun = false; self.refresh() }
                    self.scheduleRecovery()
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
                self.unpersistedFetch = next
                // Persist observed clocks before importing any profile. Recover
                // unjournaled edits against fetched history, not an older clock.
                try self.persist(next)
                for name in self.stores.keys {
                    if let family = TerminalControlsFamily(rawValue: name) { self.recordLocalChange(family, scheduleRefresh: false) }
                }
                guard self.current(epoch) else { return }
                next = self.versions
                // Read cloud first. A new device's untouched default must never
                // overwrite an existing customized keyboard.
                for (name, store) in self.stores {
                    guard let family = TerminalControlsFamily(rawValue: name), !self.pending.contains(name) else { continue }
                    guard try store.keyboardCloudReady() else { throw DirectCloudError.storage }
                    if DirectCloudKeyboardVersion.winner(next, family: family) == nil {
                        let profile = try store.load(), context = profile.syncState.layoutClock
                        let value = DirectCloudKeyboardVersion(family: family, writer: self.writer,
                            revision: max(next.map(\.revision).max() ?? 0, context.values.max() ?? 0) + 1,
                            layout: DirectCloudKeyboardLayout(profile), context: context)
                        try value.validate(); next.append(value)
                    }
                }
                // Validate every local result before applying either family.
                var changes: [(String, TerminalControlsStore, TerminalControlsProfile)] = []
                for (name, store) in self.stores {
                    guard let family = TerminalControlsFamily(rawValue: name), !self.pending.contains(name),
                          let winner = DirectCloudKeyboardVersion.winner(next, family: family) else { continue }
                    guard try store.keyboardCloudReady() else { throw DirectCloudError.storage }
                    let local = try store.load()
                    var profile = try winner.layout.applying(to: local)
                    var state = profile.syncState
                    let values = next.filter { $0.family == family }
                    state.layoutClock = DirectControlsCausality.join([state.layoutClock] + values.map {
                        DirectControlsCausality.including($0.context, writer: $0.writer, revision: $0.revision)
                    })
                    for value in DirectCloudKeyboardVersion.frontier(next, family: family) where value.layout != winner.layout {
                        let account = "layout." + value.account
                        state.keep(.init(id: account + "." + String(value.revision), family: family, layout: value.layout),
                            account: account, revision: value.revision)
                    }
                    profile.syncState = state
                    if profile != local { changes.append((name, store, profile)) }
                }
                do {
                    self.applying = true
                    defer { self.applying = false }
                    for (name, store, profile) in changes {
                        let saved = try store.save(profile, cloudImport: true, captureLayoutImport: true)
                        self.observed[name] = try Self.fingerprint(DirectCloudKeyboardLayout(saved))
                        self.appliedImports[name] = saved.syncState.layoutImport?.id
                    }
                }
                try self.persist(next)
                for value in next where value.writer == self.writer && !self.pending.contains(value.family.rawValue) {
                    guard self.current(epoch) else { return }
                    let bytes = try JSONEncoder().encode(value), account = value.account
                    try await Task.detached { try transport.write(bytes, account: account) }.value
                }
                if self.current(epoch) {
                    if !self.pending.isEmpty {
                        self.issue = .capacity
                        self.status = "Some keyboard layouts couldn’t sync. Local controls are kept on this device; large layouts may exceed the sync limit."
                    } else {
                        self.issue = nil
                        self.status = "Keyboard layouts and built-in keys sync."
                        self.recovered()
                    }
                }
            } catch {
                if self.generation == epoch { self.issue = .storage; self.status = "Keyboard layouts couldn’t sync. Local controls are kept. Retry with Refresh iCloud." }
            }
        }
    }
    private func current(_ epoch: UUID) -> Bool {
        enabled && readable && generation == epoch && !Task.isCancelled
            && canAccess() && DirectClientPlatformV1.sessionAvailable
    }
    /// Disabling invalidates application; admitted Keychain work still drains.
    func waitForDisabledWork() async { await task?.value }
    func removeCloudCopies() async throws {
        setEnabled(false)
        await task?.value
        task = nil
        guard canAccess() else { throw DirectCloudError.locked }
        // Commit reseeding before deletion. A storage failure must leave the
        // cloud copy intact; restart retains the same intent after deletion.
        if !journalLoaded { try readJournal() }
        let known = try DirectCloudKeyboardVersion.merge(versions, unpersistedFetch)
        let families = reseeding.union(stores.keys)
        let clocks = try Self.snapshotResetClocks(known, families: families)
        pending.formUnion(observed.keys); reseeding = families; resetClocks = clocks
        try persist(versions)
        readable = true; issue = nil
        let transport = transport
        try await Task.detached { try transport.removeAll() }.value
    }
    /// The parent can reset this independent service even when its Mac journal
    /// prevented constructing the normal controls engines. No profile is read.
    static func prepareForCloudRemoval(writer: UUID) throws {
        var reset = Journal(writer: writer, versions: [])
        if let data = try TerminalSecretStore.read(writer, kind: "keyboard-cloud-journal-v1") {
            guard data.count <= maximumJournalBytes else { throw DirectCloudError.invalid }
            reset = try validated(JSONDecoder().decode(Journal.self, from: data), writer: writer)
        }
        reset.observed = [:]; reset.pending = []; reset.appliedImports = [:]
        reset.reseeding = ["terminal", "remoteMac"]
        reset.resetClocks = try snapshotResetClocks(reset.versions, families: Set(reset.reseeding ?? []))
        let bytes = try JSONEncoder().encode(reset)
        guard bytes.count <= maximumJournalBytes else { throw DirectCloudError.invalid }
        try TerminalSecretStore.write(bytes, id: writer, kind: "keyboard-cloud-journal-v1")
    }
}
#endif
