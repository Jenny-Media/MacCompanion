#!/usr/bin/env python3
"""Verify native Mac identity, record migration and tap choices in Debug and -O."""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / 'spec/fixtures/manifest.json').read_text())
assert any(f['path'] == 'direct-screen-sharing-v1.json' for f in manifest['fixtures'])
fixture = ROOT / 'spec/fixtures/direct-screen-sharing-v1.json'
identity_source = (ROOT / 'Native/VNC/DirectMacIdentityV1.swift').read_text()
identity_source = '\n'.join(line for line in identity_source.splitlines() if not line.startswith(('#if', '#endif')))
record_source = (ROOT / 'Native/VNC/DirectMacLibraryV1.swift').read_text()
record = record_source[record_source.index('struct DirectMacRecordV1:'):record_source.index('enum DesktopCredentialStoreV1')]
library = record_source[record_source.index('@MainActor @Observable final class DirectMacLibraryV1'):record_source.index('\n#if os(iOS)\nstruct DirectMacLibraryRootV1')]
discovery_source = (ROOT / 'Native/VNC/DirectMacDiscoveryV1.swift').read_text()
host_discovery = '\n'.join(line for line in discovery_source.splitlines() if not line.startswith(('#if', '#endif')) and line != 'import UIKit')
key_source = (ROOT / 'Native/Terminal/TerminalKeyLibrary.swift').read_text()
start = key_source.index('static func validName(')
end = key_source.index('\n        }', start) + len('\n        }')
key_name = key_source[start:end]
checks = r'''
struct LibraryFile: Codable { var version = 5; var macs: [DirectMacRecordV1] }
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let profile = try JSONSerialization.jsonObject(with: data) as! [String: Any]
let vectors = profile["macLibraryNameCases"] as! [[String: Any]]
var records: [DirectMacRecordV1] = []
for (index, vector) in vectors.enumerated() {
    let value = vector["value"] as! String
    let record = try? DirectMacRecordV1.normalized(name: value, addresses: ["synthetic.local"])
    guard (record != nil) == (vector["macValid"] as! Bool),
          KeyNames.validName(value) == (vector["keyValid"] as! Bool) else {
        print("Native name validation failed at synthetic vector \(index)"); exit(1)
    }
    if let record {
        guard record.name == vector["normalizedName"] as! String else { exit(1) }
        records.append(record)
    }
}
let decoded = try JSONDecoder().decode(LibraryFile.self, from: JSONEncoder().encode(LibraryFile(macs: records)))
guard decoded.version == 5, decoded.macs == records else { exit(1) }
for mac in decoded.macs {
    guard try mac.validated() == mac else { exit(1) }
}
for vector in profile["macModelCases"] as! [[String: String]] {
    let family = DirectMacFamily.detect(vector["model"]!)
    precondition(family.rawValue == vector["family"] && family.symbol == vector["symbol"])
}
for vector in profile["macDetectedNameCases"] as! [[String: Any]] {
    precondition(DirectMacDetectedIdentity.cleanName(vector["value"] as! String) == vector["normalized"] as? String)
}
for vector in profile["macMetadataMatchCases"] as! [[String: Any]] {
    let identity = DirectMacDetectedIdentity(name: "Synthetic Mac", host: vector["host"] as! String,
        addresses: vector["resolved"] as! [String], port: vector["servicePort"] as! Int, connection: .desktop)
    precondition(identity.matches(addresses: vector["configured"] as! [String], port: vector["savedPort"] as! Int) == vector["matches"] as! Bool)
}
let macID = UUID()
let oldJSON: [String: Any] = ["id": macID.uuidString, "name": "Custom", "address": "synthetic.local"]
let old = try JSONDecoder().decode(DirectMacRecordV1.self, from: JSONSerialization.data(withJSONObject: oldJSON))
precondition(old.preferredConnection == .desktop && !old.usesAutomaticName && old.modelIdentifier == nil)
for vector in profile["macTapDestinationCases"] as! [[String: Any]] {
    var json = oldJSON
    if let stored = vector["stored"] as? String { json["preferredConnection"] = stored }
    let record = try JSONDecoder().decode(DirectMacRecordV1.self, from: JSONSerialization.data(withJSONObject: json))
    precondition(record.preferredConnection.rawValue == vector["destination"] as! String)
    precondition(record.preferredConnection.inputOnly == vector["inputOnly"] as! Bool)
    precondition(record.preferredConnection.terminalMode == vector["terminal"] as! Bool)
}
let identity = DirectMacDetectedIdentity(name: "Detected", host: "synthetic.local.", addresses: ["192.168.1.10"], port: 5900, connection: .desktop, modelIdentifier: "Mac16,10")
let custom = old.applying(identity)
precondition(custom.name == "Custom" && custom.detectedName == "Detected" && custom.family == .macMini)
var automatic = custom; automatic.usesAutomaticName = true; automatic.preferredConnection = .trackpad
automatic = automatic.applying(identity)
precondition(automatic.name == "Detected" && automatic.id == macID)
let reopened = try JSONDecoder().decode(DirectMacRecordV1.self, from: JSONEncoder().encode(automatic))
precondition(reopened == automatic)
let other = DirectMacDetectedIdentity(name: "Wrong", host: "other.local.", addresses: ["192.168.1.20"], port: 5900, connection: .desktop)
precondition(automatic.applying(other) == automatic)
var conflicting = identity
conflicting = .init(name: "Conflict", host: "another.local.", addresses: ["192.168.1.10"], port: 5900, connection: .desktop)
let numeric = try DirectMacRecordV1.normalized(name: "Mac", addresses: ["192.168.1.10"])
precondition(DirectMacDetectedIdentity.match(numeric, in: [identity, conflicting]) == nil)
let ssh = DirectMacDetectedIdentity(name: "SSH Name", host: "synthetic.local.", addresses: [], port: 22, connection: .terminal, modelIdentifier: "Mac16,10")
precondition(DirectMacDetectedIdentity.match(old, in: [ssh, identity])?.name == "Detected")
precondition(DirectMacDetectedIdentity.endpointKey("") == "")
precondition(DirectMacDetectedIdentity.cleanModel("Mac16,10\n") == nil)
var invalid = oldJSON; invalid["preferredConnection"] = "unknown"
precondition((try? JSONDecoder().decode(DirectMacRecordV1.self, from: JSONSerialization.data(withJSONObject: invalid))) == nil)
print("Mac identity matching, icon families, legacy migration and all tap destinations passed")
@MainActor func checkLibrary() throws {
    let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("macs.json")
    var changes: [UUID] = []
    var removed: [UUID] = []
    let library = DirectMacLibraryV1(url: url, removeLogin: { removed.append($0) })
    library.localChange = { changes.append($0) }
    precondition(library.save(id: macID, name: "Custom", addresses: ["synthetic.local"], preferredConnection: .terminal))
    library.updateDetectedMetadata([identity])
    precondition(library.macs[0].name == "Custom" && library.macs[0].family == .macMini)
    precondition(library.macs[0].preferredConnection == .terminal)
    precondition(library.save(id: macID, name: "Custom", addresses: ["synthetic.local"], usesAutomaticName: true, preferredConnection: .trackpad))
    precondition(library.macs[0].name == "Detected")
    let persisted = DirectMacLibraryV1(url: url)
    precondition(persisted.readable && persisted.macs == library.macs)
    let prior = try Data(contentsOf: url)
    library.updateDetectedMetadata([other])
    precondition(try! Data(contentsOf: url) == prior)
    precondition(library.save(id: macID, name: "Renamed", addresses: ["synthetic.local"]))
    precondition(!library.macs[0].usesAutomaticName && library.macs[0].name == "Renamed")
    library.updateDetectedMetadata([identity])
    precondition(library.macs[0].name == "Renamed")
    precondition(library.save(id: macID, name: "Renamed", addresses: ["changed.local"]))
    precondition(library.macs[0].detectedName == nil && library.macs[0].modelIdentifier == nil)
    precondition(library.macs[0].preferredConnection == .trackpad)
    let envelope = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    precondition(envelope["version"] as! Int == 5 && changes.allSatisfy { $0 == macID } && removed.isEmpty)
    var corrupt = envelope
    var macs = corrupt["macs"] as! [[String: Any]]
    macs[0]["modelIdentifier"] = "invalid\nmodel"; corrupt["macs"] = macs
    let damaged = try JSONSerialization.data(withJSONObject: corrupt)
    try damaged.write(to: url)
    let unreadable = DirectMacLibraryV1(url: url)
    precondition(!unreadable.readable && !unreadable.save(id: macID, name: "Overwrite", addresses: ["changed.local"]))
    precondition(try! Data(contentsOf: url) == damaged)
    for version in 1...3 {
        let legacy: [String: Any] = ["version": version, "macs": [oldJSON]]
        try JSONSerialization.data(withJSONObject: legacy).write(to: url)
        let migrated = DirectMacLibraryV1(url: url)
        precondition(migrated.readable && migrated.macs[0].name == "Custom" && !migrated.macs[0].usesAutomaticName)
        precondition(migrated.save(id: macID, name: "Custom", addresses: ["synthetic.local"], preferredConnection: .terminal))
        precondition(DirectMacLibraryV1(url: url).macs[0].preferredConnection == .terminal)
    }
    print("Actual library persistence, migration, custom names, metadata invalidation and unreadable-file protection passed")
}
try checkLibrary()
@MainActor final class DiscoveryChanges { var count = 0 }
@MainActor func checkDiscoveryLifecycle() async throws {
    let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    var pending: [(DirectMacLibraryV1, URL, [String: Any], DiscoveryChanges, Int)] = []
    for vector in profile["macDiscoveryLifecycleCases"] as! [[String: Any]] {
        let url = folder.appendingPathComponent((vector["id"] as! String) + ".json")
        let library = DirectMacLibraryV1(url: url)
        let automatic = vector["automatic"] as! Bool
        let name = automatic ? "My Mac" : "Custom Name"
        precondition(library.save(id: macID, name: name, addresses: ["192.168.1.10"], usesAutomaticName: automatic))
        if vector["priorMetadata"] as! Bool {
            library.updateDetectedMetadata([.init(name: "Earlier Detected", host: "earlier.local.", addresses: ["192.168.1.10"], port: 5900, connection: .desktop, modelIdentifier: "Mac13,1")])
        }
        let baseline = library.macs
        var persisted = try Data(contentsOf: url)
        let changes = DiscoveryChanges()
        library.localChange = { _ in changes.count += 1 }
        library.discovery.start()
        precondition(library.discovery.scanning)
        let browser = NetServiceBrowser.created.last!
        var saves = 0
        for (index, advertised) in (vector["services"] as! [[String: String]]).enumerated() {
            let service = NetService(domain: "local.", type: "_rfb._tcp.", name: advertised["name"]!)
            service.hostName = advertised["host"]!
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            precondition(inet_pton(AF_INET, advertised["address"]!, &address.sin_addr) == 1)
            service.addresses = [withUnsafeBytes(of: &address) { Data($0) }]
            library.discovery.netServiceBrowser(browser, didFind: service, moreComing: false)
            library.discovery.netServiceDidResolveAddress(service)
            let info = NetService.created.last { $0.type == "_device-info._tcp." && $0.name == service.name }!
            let txt = Foundation.NetService.data(fromTXTRecord: ["model": Data(advertised["model"]!.utf8)])
            library.discovery.netService(info, didUpdateTXTRecord: txt)
            // Exercise the actual callbacks before a conflicting host arrives.
            precondition(library.discovery.identities.isEmpty && library.macs == baseline)
            precondition(try! Data(contentsOf: url) == persisted)
            precondition(changes.count == saves)
            if index == 0 && vector["saveAfterFirst"] as! Bool {
                precondition(library.save(id: macID, name: baseline[0].name, addresses: baseline[0].addresses, usesAutomaticName: automatic))
                saves += 1
                precondition(library.macs == baseline && DirectMacLibraryV1(url: url).macs == baseline)
                persisted = try Data(contentsOf: url)
            }
        }
        if vector["cancel"] as! Bool { library.discovery.stop() }
        pending.append((library, url, vector, changes, saves))
    }
    // All synthetic scanners run together on the production eight-second deadline.
    try await Task.sleep(for: .seconds(9))
    for (library, url, vector, changes, saves) in pending {
        let mac = library.macs[0]
        precondition(!library.discovery.scanning && mac.id == macID)
        precondition(mac.name == vector["expectedName"] as! String)
        precondition(mac.detectedName == (vector["expectedDetectedName"] as! String))
        precondition(mac.modelIdentifier == (vector["expectedModel"] as! String))
        precondition(DirectMacLibraryV1(url: url).macs == library.macs)
        precondition(changes.count == saves + (vector["id"] as! String == "unambiguous-completed-scan" ? 1 : 0))
    }
    print("Actual scanner/library: sequential ambiguity, reverse order, Save during scanning, completed and cancelled scans passed")
}
try await checkDiscoveryLifecycle()
print("Native name validation and saved-record roundtrip passed: \(vectors.count) indexed synthetic cases")
'''
# Platform adapters only: the actual record/library code runs on temporary files.
adapters = r'''
@MainActor final class DirectAppLockV1 { static let shared = DirectAppLockV1(); var canAccess = true }
@MainActor final class UIApplication {
    enum State { case active, inactive }
    static let shared = UIApplication()
    var applicationState = State.active
}
@MainActor enum DirectClientPlatformV1 {
    static var sessionAvailable: Bool { UIApplication.shared.applicationState == .active }
    static func dataURL(_ name: String) -> URL { URL.temporaryDirectory.appending(path: name) }
    static func write(_ data: Data, to url: URL) throws { try data.write(to: url, options: .atomic) }
}
protocol NetServiceBrowserDelegate: AnyObject {}
protocol NetServiceDelegate: AnyObject {}
@MainActor final class NetServiceBrowser {
    static var created: [NetServiceBrowser] = []
    weak var delegate: NetServiceBrowserDelegate?
    init() { Self.created.append(self) }
    func searchForServices(ofType: String, inDomain: String) {}
    func stop() {}
}
@MainActor final class NetService {
    static var created: [NetService] = []
    let domain: String; let type: String; let name: String
    var hostName: String?; var port = 5900; var addresses: [Data]?
    weak var delegate: NetServiceDelegate?
    init(domain: String, type: String, name: String) {
        self.domain = domain; self.type = type; self.name = name; Self.created.append(self)
    }
    func resolve(withTimeout: TimeInterval) {}
    func stop() {}
    func startMonitoring() {}
    func stopMonitoring() {}
    static func dictionary(fromTXTRecord data: Data) -> [String: Data] { Foundation.NetService.dictionary(fromTXTRecord: data) }
}
enum DesktopCredentialStoreV1 { static func remove(_ id: UUID) throws {} }
enum TerminalSecretStore { static func remove(_ id: UUID) throws {} }
enum VNCSessionPreferences { static func clear(_ id: UUID) {} }
enum DirectCloudError: Error { case invalid }
struct DirectRecoveryNotice {
    enum Reason { case saveFailed, savedDataUnavailable, removeFailed }
    var message: String
    static func make(_ reason: Reason, message: String = "Synthetic failure") -> Self { .init(message: message) }
}
'''
source = 'import Observation\n' + identity_source + '\n' + record + adapters + host_discovery + '\n' + library + '\nenum KeyNames {\n' + key_name + '\n}\n' + checks
with tempfile.TemporaryDirectory(prefix='maccompanion-native-names-') as folder:
    base = Path(folder)
    swift = base / 'Validation.swift'
    swift.write_text(source)
    for optimization in ('-Onone', '-O'):
        binary = base / ('validation' + optimization)
        subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', optimization, str(swift), '-o', str(binary)], check=True)
        subprocess.run([str(binary), str(fixture)], check=True)
    scanner = base / 'Scanner.swift'
    scanner.write_text(identity_source + '\n' + record + '\n@MainActor final class DirectAppLockV1 { static let shared = DirectAppLockV1(); var canAccess = false }\n'
        + (ROOT / 'Native/VNC/DirectClientPlatformV1.swift').read_text() + discovery_source)
    sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
    subprocess.run(['xcrun', 'swiftc', '-typecheck', '-swift-version', '6', '-D', 'MACCOMPANION_VNC_DEVELOPMENT',
        '-sdk', sdk, '-target', 'arm64-apple-ios26.0-simulator', str(scanner)], check=True)
print('Native identity checks have Debug/optimized parity; Bonjour passes iOS SDK type-checking; no real saved data used.')
