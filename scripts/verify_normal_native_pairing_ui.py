#!/usr/bin/env python3
"""Verify normal-app Simulator bootstrap and pairing paste without connecting."""
import argparse
import hashlib
import json
import os
import shutil
from pathlib import Path
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'Experiments/SunshineMoonlightIntegration'))
from reference_build import digest, native_source_inputs
from report_simulator_run import verified_counts
from build_native_ios_development import verify_simulator_entitlements


def verify(build, output, simulator):
    simulator = str(uuid.UUID(simulator)).upper()
    booted = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'booted', '--json']))
    assert any(d['udid'].upper() == simulator and d['state'] == 'Booted'
               for runtime, entries in booted['devices'].items() if '.iOS-' in runtime for d in entries)
    baseline = json.loads((build / 'build-report.json').read_text())
    source = native_source_inputs()[1]
    assert baseline['sdk'] == 'iphonesimulator' and baseline['simulatorDevelopmentBootstrap']
    assert baseline['sourceInputSHA256'] == source
    assert baseline['builderSHA256'] == digest(ROOT / 'scripts/build_native_ios_development.py')
    app = Path(baseline['app'])
    assert baseline['normalApplicationBinarySHA256'] == digest(app / 'Mac Companion')
    ui_test = ROOT / 'Experiments/NormalNativeSimulatorQA/PairingPasteUITests.swift'
    fixture = ROOT / 'spec/fixtures/valid/pairing-qr-payload.json'
    manifest = ROOT / 'spec/fixtures/manifest.json'
    entry = next(e for e in json.loads(manifest.read_text())['fixtures']
                 if e['path'] == 'valid/pairing-qr-payload.json')
    canonical = json.dumps(json.loads(fixture.read_text()), ensure_ascii=False, sort_keys=True,
                           separators=(',', ':'), allow_nan=False).encode()
    assert hashlib.sha256(canonical).hexdigest() == entry['canonicalSHA256']
    inputs = {str(p.relative_to(ROOT)): digest(p) for p in [ui_test, fixture, manifest, Path(__file__)]}
    output.mkdir(parents=True, exist_ok=False)
    specification = json.loads((build / 'project.json').read_text())
    shutil.copy2(build / 'SimulatorDevelopment.entitlements', output / 'SimulatorDevelopment.entitlements')
    specification['targets']['MacCompanionIOS']['settings']['base']['CODE_SIGN_ENTITLEMENTS'] = str(output / 'SimulatorDevelopment.entitlements')
    assert specification['configs'] == {'Debug': 'debug'}
    assert specification['targets']['MacCompanionIOS']['settings']['base']['ENABLE_DEBUG_DYLIB'] == 'NO'
    specification['targets']['NormalPairingUITests'] = {
        'type': 'bundle.ui-testing', 'platform': 'iOS',
        'sources': [{'path': str(ui_test)}, {'path': str(fixture), 'buildPhase': 'resources'}],
        'dependencies': [{'target': 'MacCompanionIOS'}],
        'settings': {'base': {'PRODUCT_BUNDLE_IDENTIFIER': 'dev.maccompanion.normal-pairing-tests',
            'GENERATE_INFOPLIST_FILE': 'YES', 'TEST_TARGET_NAME': 'MacCompanionIOS',
            'CODE_SIGNING_ALLOWED': 'NO'}}}
    specification['schemes']['MacCompanionIOS']['test'] = {'config': 'Debug', 'targets': ['NormalPairingUITests']}
    project_spec = output / 'project.json'
    project_spec.write_text(json.dumps(specification, indent=2) + '\n')
    subprocess.run(['xcodegen', 'generate', '--spec', str(project_spec), '--project', str(output)], check=True)
    with (output / 'test.log').open('w') as log:
        result = subprocess.run(['xcodebuild', '-project', str(output / 'NormalNativeDevelopment.xcodeproj'),
            '-scheme', 'MacCompanionIOS', '-configuration', 'Debug', '-destination',
            'platform=iOS Simulator,id=' + simulator, '-derivedDataPath', str(output / 'DerivedData'),
            '-resultBundlePath', str(output / 'result.xcresult'),
            '-only-testing:NormalPairingUITests/PairingPasteUITests/testNormalAppRejectsInvalidCodeAndShowsUnverifiedPreview',
            'test'], stdout=log, stderr=subprocess.STDOUT, timeout=360)
    assert source == native_source_inputs()[1], 'Source changed during UI verification'
    assert all(digest(ROOT / p) == sha for p, sha in inputs.items()), 'UI test/fixture changed'
    tested_app = output / 'DerivedData/Build/Products/Debug-iphonesimulator/Mac Companion.app'
    entitlement_record = verify_simulator_entitlements(output, tested_app)
    for name in ['CompanionMoonlightEngine', 'OpenSSL']:
        assert digest(tested_app / f'Frameworks/{name}.framework/{name}') == digest(app / f'Frameworks/{name}.framework/{name}')
    summary = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
                                                  '--path', str(output / 'result.xcresult')]))
    counts, passed = verified_counts(summary, result.returncode)
    report = {'profile': 'maccompanion.normal-native-pairing-ui.v1', 'status': 'passed' if passed else 'failed', 'tests': counts,
        'simulatorID': simulator, 'sourceInputSHA256': source, 'uiInputs': inputs,
        'simulatorEntitlements': entitlement_record,
        'applicationBinarySHA256': digest(tested_app / 'Mac Companion'),
        'baselineReportSHA256': digest(build / 'build-report.json'), 'normalSourceRoot': True,
        'simulatorDevelopmentBootstrap': True, 'invalidManualCodeRejected': passed,
        'unverifiedPreviewVerified': passed, 'cancellationVerified': passed,
        'approvalUserPresenceSubstituted': False, 'connected': False, 'nativeSessionVerified': False,
        'physicalDevice': False, 'releaseAdmitted': False}
    (output / 'report.json').write_text(json.dumps(report, sort_keys=True, indent=2) + '\n')
    if not passed:
        raise RuntimeError('Normal pairing UI test failed; inspect the local test log')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--simulator', required=True)
    args = parser.parse_args()
    os.environ.setdefault('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer')
    print(json.dumps(verify(args.build_root.resolve(), args.output.resolve(), args.simulator), sort_keys=True))
