#!/usr/bin/env python3
"""Verify actual native name validation with and without Swift optimization."""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / 'spec/fixtures/manifest.json').read_text())
assert any(f['path'] == 'direct-screen-sharing-v1.json' for f in manifest['fixtures'])
fixture = ROOT / 'spec/fixtures/direct-screen-sharing-v1.json'
record_source = (ROOT / 'Native/VNC/DirectMacLibraryV1.swift').read_text()
record = record_source[record_source.index('struct DirectMacRecordV1:'):record_source.index('enum DesktopCredentialStoreV1')]
key_source = (ROOT / 'Native/Terminal/TerminalKeyLibrary.swift').read_text()
start = key_source.index('static func validName(')
end = key_source.index('\n        }', start) + len('\n        }')
key_name = key_source[start:end]
checks = r'''
struct LibraryFile: Codable { var version = 3; var macs: [DirectMacRecordV1] }
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
guard decoded.version == 3, decoded.macs == records else { exit(1) }
for mac in decoded.macs {
    guard try DirectMacRecordV1.normalized(id: mac.id, name: mac.name, addresses: mac.addresses,
                                         port: mac.port, sshPort: mac.sshPort) == mac else { exit(1) }
}
print("Native name validation and saved-record roundtrip passed: \(vectors.count) indexed synthetic cases")
'''
source = 'import Foundation\n' + record + '\nenum KeyNames {\n' + key_name + '\n}\n' + checks
with tempfile.TemporaryDirectory(prefix='maccompanion-native-names-') as folder:
    base = Path(folder)
    swift = base / 'Validation.swift'
    swift.write_text(source)
    for optimization in ('-Onone', '-O'):
        binary = base / ('validation' + optimization)
        subprocess.run(['xcrun', 'swiftc', optimization, str(swift), '-o', str(binary)], check=True)
        subprocess.run([str(binary), str(fixture)], check=True)
print('Native name validation has Debug/optimized parity; no real saved data used.')
