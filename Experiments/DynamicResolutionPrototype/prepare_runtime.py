"""Add numeric benchmark instrumentation to owned copies of the normal client."""
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
def replace_once(text, old, new):
    if text.count(old) != 1: raise ValueError('Benchmark anchor changed: ' + old[:75])
    return text.replace(old,new,1)
def prepare(out):
    out.mkdir(parents=True,exist_ok=True)
    (out/'CompanionVNCSession.m').write_text((ROOT/'Native/VNC/CompanionVNCSession.m').read_text())
    swift = (ROOT / 'Native/VNC/VNCRemoteDesktopView.swift').read_text()
    swift = replace_once(swift, 'let viewer = CompanionVNCViewer()', 'let viewer = MCPrototypeViewer()')
    swift = replace_once(swift, 'private var diagnosticTicket = UUID()', 'private var diagnosticTicket = UUID()\n        private var probeSamplingBusy = false')
    swift = replace_once(swift, '        func recordDiagnostics(_ counters: [AnyHashable: Any]) {', '''        func recordDiagnostics(_ counters: [AnyHashable: Any]) {
            guard !probeSamplingBusy else { return }
            probeSamplingBusy = true
            let counters = viewer?.session.diagnosticCounters ?? counters''')
    swift = replace_once(swift, '                let transport = try? await owner?.diagnosticCounters()', '''                defer { self?.probeSamplingBusy = false }
                let transport = try? await owner?.diagnosticCounters()''')
    old = '''                let url = URL.cachesDirectory.appending(path: "VNCDisplayDiagnostics-v1.json")
                if let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]) {
                    try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                }'''
    swift = replace_once(swift, old, '                (self.viewer as? MCPrototypeViewer)?.recordPrototypeSnapshot(snapshot)')
    (out / 'VNCRemoteDesktopView.swift').write_text(swift)
    bridge = (ROOT / 'Native/VNC/MacCompanionVNC-Bridging-Header.h').read_text()
    (out / 'Prototype-Bridging-Header.h').write_text(bridge + '\n#import "PrototypeViewer.h"\n')
