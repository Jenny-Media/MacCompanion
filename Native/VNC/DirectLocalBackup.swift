#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation

/// Portable user configuration. Credentials, trust, sync ancestry and writer IDs
/// are deliberately absent. A restored Mac always receives a new local ID.
struct DirectLocalBackup: Codable {
    static let formatID = "media.jenny.maccompanion.backup"
    static let maximumBytes = 45 * 1024 * 1024
    static let portableRevision = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    var format = Self.formatID
    var version = 1
    var createdAt: Date
    var macs: [Mac]
    var terminal: TerminalControlsProfile
    var remoteMac: TerminalControlsProfile
    var terminalRecovered: [DirectControlsRecoveredChange]
    var remoteRecovered: [DirectControlsRecoveredChange]

    enum Failure: Error { case invalid, newerVersion, tooLarge }

    struct Mac: Codable {
        var name: String
        var addresses: [String]
        var port: Int
        var sshPort: Int
        var usesAutomaticName: Bool
        var detectedName: String?
        var modelIdentifier: String?
        var preferredConnection: DirectMacConnection
        var swipeLeft: DirectMacSwipeAction
        var swipeRight: DirectMacSwipeAction
        var pointerSpeed: Double
        var display: UInt32?
        var fullscreen: Bool
        var trackpad: Bool
        var followCursor: Bool
        var desktopSize: Int

        @MainActor init(_ record: DirectMacRecordV1) {
            name = record.name; addresses = record.addresses; port = record.port; sshPort = record.sshPort
            usesAutomaticName = record.usesAutomaticName; detectedName = record.detectedName
            modelIdentifier = record.modelIdentifier; preferredConnection = record.preferredConnection
            swipeLeft = record.swipeLeft; swipeRight = record.swipeRight
            pointerSpeed = VNCSessionPreferences.speed(record.id)
            display = VNCSessionPreferences.display(record.id)?.uint32Value
            fullscreen = VNCSessionPreferences.fullscreen(record.id)
            trackpad = VNCSessionPreferences.trackpad(record.id)
            followCursor = VNCSessionPreferences.followCursor(record.id)
            desktopSize = VNCSessionPreferences.desktopSize(record.id)
        }
        func record(id: UUID = UUID()) throws -> DirectMacRecordV1 {
            var value = try DirectMacRecordV1.normalized(id: id, name: name, addresses: addresses, port: port, sshPort: sshPort)
            guard value.name == name, value.addresses == addresses,
                  pointerSpeed.isFinite, (0.5...3).contains(pointerSpeed), (0...3).contains(desktopSize) else { throw Failure.invalid }
            value.usesAutomaticName = usesAutomaticName; value.detectedName = detectedName
            value.modelIdentifier = modelIdentifier; value.preferredConnection = preferredConnection
            value.swipeLeft = swipeLeft; value.swipeRight = swipeRight
            return try value.validated()
        }
        @MainActor func applyPreferences(to id: UUID) {
            VNCSessionPreferences.setSpeed(pointerSpeed, mac: id)
            VNCSessionPreferences.setDisplay(display.map(NSNumber.init(value:)), mac: id)
            VNCSessionPreferences.setFullscreen(fullscreen, mac: id)
            VNCSessionPreferences.setTrackpad(trackpad, mac: id)
            VNCSessionPreferences.setFollowCursor(followCursor, mac: id)
            VNCSessionPreferences.setDesktopSize(desktopSize, mac: id)
        }
    }

    @MainActor init(macs: [DirectMacRecordV1], terminal: TerminalControlsProfile,
                    remoteMac: TerminalControlsProfile, createdAt: Date = Date()) throws {
        self.createdAt = createdAt; self.macs = macs.map(Mac.init)
        self.terminal = Self.portable(terminal, family: .terminal)
        self.remoteMac = Self.portable(remoteMac, family: .remoteMac)
        self.terminalRecovered = Self.portableRecovery(terminal.syncState.recovered)
        self.remoteRecovered = Self.portableRecovery(remoteMac.syncState.recovered)
        try validate()
    }
    private static func portable(_ source: TerminalControlsProfile, family: TerminalControlsFamily) -> TerminalControlsProfile {
        var value = source
        value.family = family; value.revision = portableRevision
        value.importedMacs = []; value.localCloudState = nil
        value.freezeKeyboardLayout(); value.captureRemoteMenu()
        return value
    }
    private static func portableRecovery(_ source: [DirectControlsRecoveredChange]) -> [DirectControlsRecoveredChange] {
        source.map { original in var copy = original; copy.id = "backup-" + UUID().uuidString.lowercased(); return copy }
    }
    func validate() throws {
        guard version <= 1 else { throw Failure.newerVersion }
        guard format == Self.formatID, version == 1, (0...253_402_300_799).contains(createdAt.timeIntervalSince1970),
              macs.count <= 64 else { throw Failure.invalid }
        for mac in macs { _ = try mac.record() }
        for (copies, family) in [(terminalRecovered, TerminalControlsFamily.terminal), (remoteRecovered, .remoteMac)] {
            guard copies.count <= 512, Set(copies.map(\.id)).count == copies.count else { throw Failure.invalid }
            for copy in copies { guard copy.family == family else { throw Failure.invalid }; try copy.validate() }
        }
        for (profile, family) in [(terminal, TerminalControlsFamily.terminal), (remoteMac, .remoteMac)] {
            guard profile.version <= TerminalControlsProfile.currentVersion,
                  (profile.rowsSchema ?? 0) <= TerminalControlsProfile.currentRowsSchema else { throw Failure.newerVersion }
            guard profile.version == TerminalControlsProfile.currentVersion,
                  profile.rowsSchema == TerminalControlsProfile.currentRowsSchema,
                  profile.family == family, profile.revision == Self.portableRevision,
                  profile.importedMacs.isEmpty, profile.localCloudState == nil, profile.valid else { throw Failure.invalid }
        }
    }
    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw Failure.tooLarge }
        return data
    }
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw Failure.tooLarge }
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate(); return value
    }
    var recoveredCount: Int { terminalRecovered.count + remoteRecovered.count }
    var shortcutCount: Int { (terminal.actions + remoteMac.actions).filter { $0.kind == .shortcut }.count }
    var savedTextCount: Int { (terminal.actions + remoteMac.actions).filter { $0.kind == .text }.count }
}
#endif
