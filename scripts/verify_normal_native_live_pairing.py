#!/usr/bin/env python3
"""Normal Simulator app -> live pairing, saved workspace and optional native Control.

The signed Agent and consent bridge are disposable. No installed Mac product,
physical phone, privacy setting, or client approval substitution is selected.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import signal
import shutil
import socket
import sqlite3
import struct
import subprocess
import sys
import threading
import time
import uuid

from verify_agent_xpc import Probe, ROOT, source_fingerprint
from report_simulator_run import verified_counts
sys.path.insert(0, str(ROOT / 'Experiments/SunshineMoonlightIntegration'))
from reference_build import digest, native_source_inputs
from build_native_ios_development import verify_simulator_entitlements


def command(fixture, action):
    with socket.create_connection(('127.0.0.1', fixture['port']), timeout=8) as peer:
        def send(value):
            body = json.dumps(value, separators=(',', ':')).encode()
            peer.sendall(struct.pack('>I', len(body)) + body)
        def read_exact(count):
            data = bytearray()
            while len(data) < count:
                part = peer.recv(count - len(data))
                if not part:
                    raise RuntimeError('Consent bridge closed')
                data.extend(part)
            return bytes(data)
        def receive():
            size = struct.unpack('>I', read_exact(4))[0]
            assert size <= 4_194_304
            return read_exact(size)
        send({'token': fixture['token'], 'role': 'control'})
        assert receive() == b'ready'
        send({'action': action})
        return json.loads(receive())


def retain_native_host_logs(probe, output, stop):
    """Retain short lived child logs under the private disposable output."""
    while not stop.is_set():
        operations = [operation for owner in ('signed-native-owned', 'signed-native-owned-replacement')
                      for operation in (probe.state / owner).glob('managed-*')]
        for operation in operations:
            for name in ('sunshine.log', 'startup.log'):
                source = operation / name
                try:
                    if not source.is_file() or source.is_symlink():
                        continue
                    data = source.read_bytes()
                    destination = output / f'native-host-{operation.parent.name}-{operation.name}-{name}'
                    descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
                    with os.fdopen(descriptor, 'wb') as saved:
                        saved.write(data)
                except (FileNotFoundError, PermissionError):
                    # The enrollment owner may retire while a copy is in flight.
                    pass
        stop.wait(0.05)

def simulator_root(simulator):
    container = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', simulator,
        'media.jenny.maccompanion.ios', 'data'], text=True).strip())
    assert container.is_absolute() and f'/Devices/{simulator}/data/Containers/Data/Application/' in str(container)
    return container / 'Library/Application Support/dev.maccompanion.simulator/iOS/v1'


def tree_hashes(root):
    assert root.is_dir() and not root.is_symlink()
    result = {}
    for path in root.rglob('*'):
        assert not path.is_symlink()
        if path.is_file():
            result[str(path.relative_to(root))] = digest(path)
        else:
            assert path.is_dir()
    return result


def stop_app(simulator):
    subprocess.run(['xcrun', 'simctl', 'terminate', simulator, 'media.jenny.maccompanion.ios'],
                   capture_output=True, timeout=15)


class SelectedTargetProcess:
    def __init__(self, pid, binary, change_path=None):
        self.pid = pid
        self.binary = binary
        self.change_path = change_path

    def is_owned(self):
        result = subprocess.run(['ps', '-p', str(self.pid), '-o', 'command='],
                                capture_output=True, text=True, timeout=5)
        return result.returncode == 0 and result.stdout.strip().split(' ', 1)[0] == str(self.binary)

    def terminate(self):
        if self.is_owned():
            os.kill(self.pid, signal.SIGTERM)

    def request_window_change(self, change):
        assert change in ('close', 'move', 'resize')
        assert self.change_path is not None and self.is_owned()
        self.change_path.write_text(change + '\n')

    def window_change_completed(self, change):
        assert self.change_path is not None
        done = Path(str(self.change_path) + '.done')
        return done.is_file() and done.read_text() == change

    def wait(self, timeout):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if not self.is_owned():
                return
            time.sleep(.1)
        raise TimeoutError('Disposable selected target did not terminate')


def start_selected_target(output, change_window=False, other_display=False, static_target=False):
    """Own one visible, disposable AppKit target with no captured user content."""
    source = ROOT / 'Experiments/NormalNativeSimulatorQA/SelectedTarget.m'
    bundle = output / 'SelectedTarget.app'
    binary = bundle / 'Contents/MacOS/SelectedTarget'
    binary.parent.mkdir(mode=0o700, parents=True)
    info = {'CFBundleIdentifier': 'dev.maccompanion.qa-selected-target',
            'CFBundleExecutable': 'SelectedTarget',
            'CFBundleName': 'Mac Companion QA Target',
            'CFBundleDisplayName': 'Mac Companion QA Target',
            'CFBundlePackageType': 'APPL', 'LSUIElement': True}
    (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-mmacosx-version-min=26.0',
                    '-framework', 'AppKit', '-framework', 'CoreGraphics', str(source), '-o', str(binary)], check=True, timeout=45)
    subprocess.run(['codesign', '--force', '--sign', '-', '--identifier', info['CFBundleIdentifier'],
                    str(bundle)], check=True, capture_output=True, timeout=30)
    ready_path = output / 'selected-target-ready.txt'
    change_path = output / 'selected-target-change.txt' if change_window else None
    launch = ['open', '-n', '-a', str(bundle), '--args', str(ready_path)]
    if change_path is not None:
        launch.append(str(change_path))
    elif other_display or static_target:
        launch.append(str(output / 'selected-target-unused-change.txt'))
    if other_display:
        launch.append('other-display')
    elif static_target:
        launch.append('static')
    subprocess.run(launch,
                   check=True, capture_output=True, timeout=15)
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if ready_path.is_file():
            parts = ready_path.read_text().strip().split(' ')
            assert len(parts) == (4 if other_display else 2) and parts[0] == 'selected-target-ready'
            process = SelectedTargetProcess(int(parts[1]), binary, change_path)
            assert process.is_owned(), 'LaunchServices did not retain the disposable test app'
            if other_display:
                assert int(parts[2]) > 0 and int(parts[3]) > 0 and parts[2] != parts[3], \
                    'Disposable Window must be on a different physical display from the main Desktop'
            return process, None
        time.sleep(.1)
    raise RuntimeError('Disposable App/Window target did not become visible')


def verify(build, output, simulator, resume_build=False, reuse_build_project=False, complete_pairing=False,
           native_root=None, native_host_package=None, native_background=False, native_connection_loss=False,
           native_surface_replacement=False, native_real_targets=False, native_selected_target=False,
           native_selected_window=False, native_window_soak=False, native_session_soak=False,
           native_session_hold=False, native_video_continuity=False, native_window_closure=False,
           native_window_move=False, native_window_resize=False,
           native_window_resize_restart=False, native_window_resize_rapid_stop=False,
           native_selected_window_other_display=False, native_selected_target_static=False, native_picker_window_disappearance=False, native_window_auto_recovery=False):
    native = native_root is not None
    assert not native_picker_window_disappearance or (native_selected_window
        and not native_selected_window_other_display and not native_window_soak
        and not (native_window_closure or native_window_move or native_window_resize))
    assert not native_window_auto_recovery or (native_window_resize and not native_window_resize_restart)
    assert not native_window_resize_restart or native_window_resize
    assert not native_window_resize_rapid_stop or native_window_resize_restart
    assert sum((native_window_closure, native_window_move, native_window_resize)) <= 1
    window_change = ('close' if native_window_closure else 'move' if native_window_move
                     else 'resize' if native_window_resize else None)
    assert not native or (complete_pairing and native_host_package is not None)
    assert native or native_host_package is None
    assert not native_background or native
    assert not native_connection_loss or (native and native_background)
    assert not native_surface_replacement or native
    assert not native_real_targets or native_surface_replacement
    assert not native_selected_target or native_real_targets
    assert not native_selected_window or native_real_targets
    assert not (native_selected_target and native_selected_window)
    assert not native_window_soak or native_selected_window
    assert not native_selected_window_other_display or (native_selected_window and window_change is None)
    assert not native_selected_target_static or ((native_selected_target or native_selected_window)
        and not native_selected_window_other_display and window_change is None)
    assert window_change is None or (native_selected_window and not native_window_soak)
    assert not native_session_soak or (native and not native_background and not native_connection_loss
                                       and not native_surface_replacement and not native_window_soak)
    assert not native_session_hold or (native and not native_background and not native_connection_loss
                                       and not native_surface_replacement and not native_window_soak
                                       and not native_session_soak)
    assert not native_video_continuity or (native and not native_background and not native_connection_loss
                                           and not native_surface_replacement and not native_window_soak
                                           and not native_session_soak and not native_session_hold)
    simulator = str(uuid.UUID(simulator)).upper()
    booted = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'booted', '--json']))
    assert any(d['udid'].upper() == simulator and d['state'] == 'Booted'
               for runtime, entries in booted['devices'].items() if '.iOS-' in runtime for d in entries)
    baseline = json.loads((build / 'build-report.json').read_text())
    source = native_source_inputs()[1]
    assert baseline['sdk'] == 'iphonesimulator' and baseline['simulatorDevelopmentBootstrap']
    assert baseline['sourceInputSHA256'] == source
    assert baseline['builderSHA256'] == digest(ROOT / 'scripts/build_native_ios_development.py')
    baseline_report_sha = digest(build / 'build-report.json')
    app = Path(baseline['app'])
    assert baseline['normalApplicationBinarySHA256'] == digest(app / 'Mac Companion')
    assert baseline['simulatorEntitlements'] == verify_simulator_entitlements(build, app)
    frameworks = {name: digest(app / f'Frameworks/{name}.framework/{name}')
                  for name in ['CompanionMoonlightEngine', 'OpenSSL']}
    qa = ROOT / 'Experiments/NormalNativeSimulatorQA'
    test = qa / ('PairedWorkspaceUITests.swift' if complete_pairing else 'LivePairingUITests.swift')
    selected = ('PairedWorkspaceUITests/testNormalAppReturnsToDesktopAfterSelectedWindowResizes' if native_window_auto_recovery else
                'PairedWorkspaceUITests/testNormalAppRecoversDesktopWhenPickerWindowDisappears' if native_picker_window_disappearance else
                'PairedWorkspaceUITests/testNormalAppRetiresNativeVideoWhenSelectedWindowCloses' if native_window_closure else
                'PairedWorkspaceUITests/testNormalAppRetiresNativeVideoWhenSelectedWindowMoves' if native_window_move else
                'PairedWorkspaceUITests/testNormalAppRestartsControlAfterSelectedWindowResizes' if native_window_resize_restart else
                'PairedWorkspaceUITests/testNormalAppRetiresNativeVideoWhenSelectedWindowResizes' if native_window_resize else
                'PairedWorkspaceUITests/testNormalAppReenrollsNativeVideoAfterWindowSelection' if native_selected_window else
                'PairedWorkspaceUITests/testNormalAppReenrollsNativeVideoAfterAppSelection' if native_selected_target else
                'PairedWorkspaceUITests/testNormalAppReenrollsNativeVideoAfterDesktopSelection' if native_surface_replacement else
                'PairedWorkspaceUITests/testNormalAppNativeBackgroundAndConnectionRecovery' if native_connection_loss else
                'PairedWorkspaceUITests/testNormalAppNativeBackgroundFencesInputAndRequiresRestart' if native_background else
                'PairedWorkspaceUITests/testNormalAppPairsAndRunsNativeControl' if native else
                'PairedWorkspaceUITests/testNormalAppPairsAndRestartsIntoWorkspace' if complete_pairing
                else 'LivePairingUITests/testNormalAppVerifiesLivePairingAndCancels')
    test_inputs = [test, Path(__file__)] + ([qa / 'PairedIdentityCleanup.swift', qa / 'NormalConsentBridge.swift'] if complete_pairing else [])
    if native:
        test_inputs.append(ROOT / 'scripts/native_agent_probe_support.py')
    if native_selected_target or native_selected_window:
        test_inputs.append(qa / 'SelectedTarget.m')
    inputs = {str(p.relative_to(ROOT)): digest(p) for p in test_inputs}
    host_source = source_fingerprint()
    if resume_build:
        assert output.is_dir() and not output.is_symlink()
        assert not (output / 'report.json').exists() and not (output / 'result.xcresult').exists()
    else:
        output.mkdir(mode=0o700, parents=True, exist_ok=False)
    if complete_pairing:
        assert not resume_build, 'A completed-pair run cannot adopt partial state'
        shutil.copytree(app, output / 'OriginalApplication.app')
    spec = json.loads((build / 'project.json').read_text())
    shutil.copy2(build / 'SimulatorDevelopment.entitlements', output / 'SimulatorDevelopment.entitlements')
    spec['targets']['MacCompanionIOS']['settings']['base']['CODE_SIGN_ENTITLEMENTS'] = str(output / 'SimulatorDevelopment.entitlements')
    spec['targets']['NormalLivePairingUITests'] = {
        'type': 'bundle.ui-testing', 'platform': 'iOS', 'sources': [{'path': str(test)}] +
            ([{'path': str(qa / 'NormalConsentBridge.swift')}] if complete_pairing else []),
        'dependencies': [{'target': 'MacCompanionIOS'}],
        'settings': {'base': {'PRODUCT_BUNDLE_IDENTIFIER': 'dev.maccompanion.normal-live-pairing-tests',
            'GENERATE_INFOPLIST_FILE': 'YES', 'TEST_TARGET_NAME': 'MacCompanionIOS', 'CODE_SIGNING_ALLOWED': 'NO'}}}
    spec['schemes']['MacCompanionIOS']['test'] = {'config': 'Debug', 'targets': ['NormalLivePairingUITests']}
    if complete_pairing:
        spec['targets']['NormalIdentityCleanup'] = {
            'type': 'bundle.unit-test', 'platform': 'iOS', 'sources': [{'path': str(qa / 'PairedIdentityCleanup.swift')}],
            'dependencies': [{'target': 'MacCompanionIOS'},
                {'package': 'MacCompanionKit', 'product': 'CompanionClient'},
                {'package': 'MacCompanionKit', 'product': 'CompanionClientPlatform'}],
            'settings': {'base': {'PRODUCT_BUNDLE_IDENTIFIER': 'dev.maccompanion.normal-identity-cleanup',
                'GENERATE_INFOPLIST_FILE': 'YES', 'TEST_HOST': '$(BUILT_PRODUCTS_DIR)/Mac Companion.app/Mac Companion',
                'BUNDLE_LOADER': '$(TEST_HOST)', 'CODE_SIGNING_ALLOWED': 'NO'}}}
        spec['schemes']['MacCompanionIOS']['test']['targets'].append('NormalIdentityCleanup')
    project_root = build if reuse_build_project else output
    derived = project_root / 'DerivedData'
    if reuse_build_project:
        assert not resume_build and build != output
        (output / 'DerivedData').symlink_to(derived, target_is_directory=True)
    project_spec = output / 'project.json'
    if resume_build:
        assert json.loads(project_spec.read_text()) == spec, 'Resume project differs'
    project_spec.write_text(json.dumps(spec, indent=2) + '\n')
    subprocess.run(['xcodegen', 'generate', '--spec', str(project_spec), '--project', str(project_root)], check=True)
    common = ['-project', str(project_root / 'NormalNativeDevelopment.xcodeproj'), '-scheme', 'MacCompanionIOS',
        '-configuration', 'Debug', '-destination', 'platform=iOS Simulator,id=' + simulator,
        '-derivedDataPath', str(derived)]
    with (output / 'build.log').open('w') as log:
        subprocess.run(['xcodebuild', *common, 'build-for-testing'], stdout=log, stderr=subprocess.STDOUT,
                       timeout=600, check=True)
    tested_app = output / 'DerivedData/Build/Products/Debug-iphonesimulator/Mac Companion.app'
    entitlement_record = verify_simulator_entitlements(output, tested_app)
    for name in ['CompanionMoonlightEngine', 'OpenSSL']:
        assert digest(tested_app / f'Frameworks/{name}.framework/{name}') == frameworks[name]
    tested_binary_sha = digest(tested_app / 'Mac Companion')
    run_file = next((output / 'DerivedData/Build/Products').glob('*.xctestrun'))
    run = plistlib.loads(run_file.read_bytes())
    if 'TestConfigurations' in run:
        targets = [target for configuration in run['TestConfigurations'] for target in configuration['TestTargets']]
    else:
        targets = [value for key, value in run.items()
                   if key != '__xctestrun_metadata__' and isinstance(value, dict) and 'TestBundlePath' in value]
    ui_targets = [target for target in targets if target.get('IsUITestBundle')]
    assert len(ui_targets) == 1
    native_manifest_sha = None
    original_real_targets = os.environ.get('MACCOMPANION_NATIVE_LAB_SELECTED_SURFACES')
    if native:
        if native_real_targets:
            os.environ['MACCOMPANION_NATIVE_LAB_SELECTED_SURFACES'] = '1'
        else:
            os.environ.pop('MACCOMPANION_NATIVE_LAB_SELECTED_SURFACES', None)
        from native_agent_probe_support import configure_native_probe, verify_development_host_package
        verify_development_host_package(native_host_package)
        native_manifest_sha = digest(native_host_package / 'host-package.json')
        probe, _, _ = configure_native_probe(native_root, native_host_package)
    else:
        probe = Probe()
    failure = None
    counts = None
    passed = False
    cleaned = False
    client_id = None
    host_id = None
    original_state = None
    original_hashes = None
    cleanup_counts = None
    client_keys_cleaned = not complete_pairing
    state_restored = not complete_pairing
    lock = Path(f'/private/tmp/maccompanion-simulator-{simulator}.lock')
    lock_owned = False
    selected_target_process = None
    selected_target_log = None
    selected_window_change_stop = threading.Event()
    selected_window_change_thread = None
    selected_window_change_failure = []
    menu_reactivation_thread = None
    menu_reactivation_failure = []
    menu_reactivation = {}
    host_log_stop = threading.Event()
    host_log_monitor = None
    try:
        lock.mkdir()
        lock_owned = True
        if complete_pairing:
            stop_app(simulator)
            root = simulator_root(simulator)
            assert not list((root / 'paired-hosts-v1').iterdir()), 'Existing pairing must not be replaced'
            assert all(path.name == '.lock' for path in (root / 'configured-routes-v1').iterdir()), 'Existing routes must not be replaced'
            original_hashes = tree_hashes(root)
            backup = output / 'OriginalSimulatorState'
            root.rename(backup)
            original_state = backup
            subprocess.run(['xcrun', 'simctl', 'install', simulator, str(tested_app)], check=True, timeout=30)
            subprocess.run(['xcrun', 'simctl', 'launch', simulator, 'media.jenny.maccompanion.ios'],
                           check=True, stdout=subprocess.DEVNULL, timeout=15)
            root = simulator_root(simulator)
            deadline = time.monotonic() + 10
            while not (root / 'installation-v1.json').exists() and time.monotonic() < deadline:
                time.sleep(.1)
            client_id = str(uuid.UUID(json.loads((root / 'installation-v1.json').read_text())['clientID']))
            stop_app(simulator)
            os.environ['MACCOMPANION_NORMAL_SIMULATOR_CLIENT_ID'] = client_id
        probe.prepare()
        probe.start_server()
        probe.client('enable', role='bootstrap', marker='enabled-receipt-verified')
        probe.stop_server()
        probe.start_server('productionInteractive')
        menu_process, menu_log = probe.background_client('presentation-native-simulator-continuous' if native else 'presentation-simulator')
        probe.wait_marker(menu_log, 'signed-simulator-menu-ready')
        # Menu authentication precedes listener composition. Pairing commands
        # must wait for the owned Agent's actual loopback readiness.
        probe.wait_marker(probe.server_log, 'isolated-loopback-ready')
        if native:
            host_log_monitor = threading.Thread(target=retain_native_host_logs,
                args=(probe, output, host_log_stop), daemon=True)
            host_log_monitor.start()
        if native_selected_target or native_selected_window:
            selected_target_process, selected_target_log = start_selected_target(
                output, window_change is not None or native_picker_window_disappearance, native_selected_window_other_display, native_selected_target_static)
        fixture = json.loads((probe.state / 'simulator-fixture.json').read_text())
        receipt = command(fixture, 'journey-pair' if complete_pairing else 'journey-pair-preview')
        if complete_pairing:
            assert uuid.UUID(fixture['clientID']) == uuid.UUID(client_id)
            database = probe.state / 'media.jenny.maccompanion/Agent/v1/security-v1.sqlite3'
            with sqlite3.connect(f'file:{database}?mode=ro', uri=True) as db:
                rows = db.execute('SELECT host_id FROM host_identity').fetchall()
                assert len(rows) == 1
                host_id = str(uuid.UUID(rows[0][0]))
        assert receipt['pairedDevices'] == 0 and receipt['qr'].startswith('maccompanion://pair/v0.1/')
        ui_targets[0].setdefault('EnvironmentVariables', {})['MACCOMPANION_TEST_PAIRING_CODE'] = receipt['qr']
        if native:
            ui_targets[0]['EnvironmentVariables']['MACCOMPANION_TEST_CONSENT_FIXTURE'] = json.dumps(fixture)
        if native_picker_window_disappearance:
            assert selected_target_process.is_owned()
            ui_targets[0]['EnvironmentVariables']['MACCOMPANION_TEST_PICKER_WINDOW_CLOSE_PATH'] = str(selected_target_process.change_path)
        if native_window_soak:
            ui_targets[0]['EnvironmentVariables']['MACCOMPANION_TEST_WINDOW_SOAK_TRANSITIONS'] = '20'
        if native_session_soak:
            ui_targets[0]['EnvironmentVariables']['MACCOMPANION_TEST_NATIVE_SESSION_SOAK_COUNT'] = '10'
        if native_session_hold or native_video_continuity:
            ui_targets[0]['EnvironmentVariables']['MACCOMPANION_TEST_NATIVE_HOLD_SECONDS'] = (
                '1800' if native_session_hold else '60')
        if window_change is not None:
            if native_window_resize_rapid_stop:
                ui_targets[0]['EnvironmentVariables']['MACCOMPANION_TEST_RAPID_STOP_AFTER_RESTART'] = '1'
            def change_after_selected_presentation():
                try:
                    deadline = time.monotonic() + 180
                    while not selected_window_change_stop.is_set() and time.monotonic() < deadline:
                        markers = menu_log.read_text().splitlines()
                        if markers.count('native-local-presentation-input-admitted') >= 2 \
                                and 'signed-simulator-window-change-ready' in markers:
                            selected_target_process.request_window_change(window_change)
                            return
                        selected_window_change_stop.wait(.1)
                    selected_window_change_failure.append('Selected Window presentation was not observed')
                except Exception as error:
                    selected_window_change_failure.append(f'{type(error).__name__}: {error}')
            selected_window_change_thread = threading.Thread(target=change_after_selected_presentation, daemon=True)
            selected_window_change_thread.start()
        if native_window_resize_restart:
            def reactivate_disposable_menu():
                try:
                    probe.wait_marker(menu_log, 'local-xpc-invalidated', timeout=180)
                    assert menu_process.poll() is None, 'Old disposable menu exited before replacement'
                    menu_process.terminate()
                    assert menu_process.wait(timeout=10) is not None
                    fixture_path = probe.state / 'simulator-fixture.json'
                    assert fixture_path.is_file() and not fixture_path.is_symlink()
                    fixture_path.unlink()
                    replacement, replacement_log = probe.background_client(
                        'presentation-native-simulator-continuous', log_suffix='reactivated',
                        environment={'MACCOMPANION_NATIVE_LAB_OWNER_DIR':
                            str(probe.state / 'signed-native-owned-replacement')})
                    probe.wait_marker(replacement_log, 'signed-simulator-menu-ready', timeout=20)
                    assert replacement.poll() is None, 'Replacement disposable menu exited'
                    replacement_fixture = json.loads(fixture_path.read_text())
                    assert replacement_fixture['clientID'] == fixture['clientID']
                    recovered = command(replacement_fixture, 'journey-reactivate-control-admission')
                    assert recovered['pairedDevices'] == 1
                    menu_reactivation.update(log=replacement_log, fixture=replacement_fixture)
                    deadline = time.monotonic() + 120
                    while time.monotonic() < deadline:
                        if 'native-local-presentation-input-admitted' in replacement_log.read_text().splitlines():
                            current = command(replacement_fixture, 'journey-status')
                            if current['control']['captureActive'] and current['control']['mediaRecords'] > 0:
                                if not native_window_resize_rapid_stop:
                                    first_records = current['control']['mediaRecords']
                                    time.sleep(3)
                                    sustained = command(replacement_fixture, 'journey-status')
                                    assert sustained['control']['captureActive'] is True
                                    assert sustained['control']['mediaRecords'] > first_records, \
                                        'Replacement stream did not advance after presentation'
                                    menu_reactivation['sustainedMediaRecords'] = sustained['control']['mediaRecords']
                                return
                        time.sleep(.2)
                    raise TimeoutError('Replacement menu did not present a fresh native stream')
                except Exception as error:
                    menu_reactivation_failure.append(f'{type(error).__name__}: {error}')
            menu_reactivation_thread = threading.Thread(target=reactivate_disposable_menu, daemon=True)
            menu_reactivation_thread.start()
        run_file.write_bytes(plistlib.dumps(run))
        run_file.chmod(0o600)
        with (output / 'test.log').open('w') as log:
            result = subprocess.run(['xcodebuild', '-xctestrun', str(run_file), '-destination',
                'platform=iOS Simulator,id=' + simulator, '-parallel-testing-enabled', 'NO',
                '-collect-test-diagnostics', 'never',
                '-only-testing:NormalLivePairingUITests/' + selected,
                '-resultBundlePath', str(output / 'result.xcresult'), 'test-without-building'],
                stdout=log, stderr=subprocess.STDOUT, timeout=2_400 if native_session_hold else 900 if native_window_soak or native_session_soak else 360 if native else 180)
        summary = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results',
            'summary', '--path', str(output / 'result.xcresult')]))
        counts, passed = verified_counts(summary, result.returncode)
        passed = passed and counts['totalTestCount'] == 1
        if native_picker_window_disappearance:
            assert selected_target_process.window_change_completed('close')
        if window_change is not None:
            selected_window_change_thread.join(timeout=2)
            assert not selected_window_change_thread.is_alive(), 'Selected Window change trigger did not finish'
            assert not selected_window_change_failure, selected_window_change_failure
            assert selected_target_process.change_path.is_file(), 'Selected Window change was not requested'
            assert selected_target_process.window_change_completed(window_change), 'Disposable Window did not perform the change'
        if native_window_resize_restart:
            menu_reactivation_thread.join(timeout=2)
            assert not menu_reactivation_thread.is_alive(), 'Replacement menu did not finish reactivation'
            assert not menu_reactivation_failure, menu_reactivation_failure
            assert 'log' in menu_reactivation, 'Replacement menu evidence is missing'
        if native:
            container = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', simulator,
                'media.jenny.maccompanion.ios', 'data'], text=True).strip())
            diagnostics = container / 'Library/Caches/mac-companion-runtime-diagnostics-v0.log'
            if diagnostics.is_file() and not diagnostics.is_symlink():
                shutil.copy2(diagnostics, output / 'content-free-runtime-diagnostics.log')
            if native_video_continuity and passed:
                lines = (output / 'content-free-runtime-diagnostics.log').read_text().splitlines()
                progress = [index for index, line in enumerate(lines)
                            if 'event=native.launch.native.video.frames-advanced' in line]
                assert len(progress) >= 8, 'Client did not keep queuing video during the one-minute hold'
                assert not any('event=native.launch.native.video.frames-stalled' in line
                               for line in lines[progress[0]:]), 'Client video frame queue stalled during hold'
        # Changing the selected Window intentionally tears down the local
        # backend, including this disposable status bridge. The XCTest checks
        # the client screen; the signed menu and managed host logs check drain.
        if window_change is None or native_window_auto_recovery:
            status = command(fixture, 'journey-status')
            assert status['pairedDevices'] == (1 if complete_pairing else 0)
        elif native_window_resize_restart and passed:
            status = command(menu_reactivation['fixture'], 'journey-status')
            assert status['pairedDevices'] == 1
            assert status['control']['runtimeIdle'] is True
            assert status['control']['captureActive'] is False
            assert status['control']['queuedMediaRecords'] == 0
        assert ('signed-simulator-pairing-approved' in menu_log.read_text().splitlines()) == complete_pairing
        assert source == native_source_inputs()[1] and host_source == source_fingerprint()
        assert all(digest(ROOT / p) == sha for p, sha in inputs.items())
        if native:
            verify_development_host_package(native_host_package)
            assert digest(native_host_package / 'host-package.json') == native_manifest_sha
            if passed:
                markers = menu_log.read_text().splitlines()
                assert 'signed-simulator-control-granted' in markers
                assert 'signed-simulator-control-media-active' in markers
                if window_change is not None and not native_window_auto_recovery:
                    assert any(line.startswith('native-local-backend-failed ') for line in markers), 'Window loss did not fail the local backend'
                    assert 'local-xpc-invalidated' in markers, 'Window loss did not invalidate the local endpoint'
                    assert any('Terminate handler called' in path.read_text(errors='replace')
                               for path in output.glob('native-host-signed-native-owned*-managed-*-sunshine.log')), 'Managed video host did not terminate'
                    if native_window_resize_restart:
                        replacement_markers = menu_reactivation['log'].read_text().splitlines()
                        assert 'signed-simulator-control-readmitted' in replacement_markers
                        assert 'signed-simulator-control-stop-clean' in replacement_markers
                else:
                    assert 'signed-simulator-control-stop-clean' in markers
                presentations = markers.count('native-local-presentation-input-admitted')
                if native_window_resize_restart:
                    presentations += replacement_markers.count('native-local-presentation-input-admitted')
                assert presentations == (
                    (22 if native_window_soak else 10 if native_session_soak else 1 if native_session_hold or native_video_continuity else 4 if native_window_auto_recovery else 3 if native_window_resize_restart else 2 if window_change is not None else 3 if native_connection_loss or native_surface_replacement else 2)
                    + (2 if native_surface_replacement else 0)), \
                    f'Unexpected native presentations: {presentations}'
                if window_change is None or native_window_auto_recovery:
                    assert 'signed-simulator-control-input-observed' in markers
                if native_connection_loss:
                    assert 'signed-simulator-primary-connections-drained' in markers
                    assert 'signed-simulator-primary-admission-restored' in markers
        if not passed:
            failure = 'Normal app did not complete the selected live journey; inspect local test result'
    except (Exception, KeyboardInterrupt) as error:
        failure = f'{type(error).__name__}: {error}'
    finally:
        host_log_stop.set()
        selected_window_change_stop.set()
        if selected_window_change_thread is not None:
            selected_window_change_thread.join(timeout=2)
        if menu_reactivation_thread is not None:
            menu_reactivation_thread.join(timeout=2)
        if host_log_monitor is not None:
            host_log_monitor.join(timeout=2)
        if selected_target_process is not None:
            selected_target_process.terminate()
            selected_target_process.wait(timeout=10)
        if selected_target_log is not None:
            selected_target_log.close()
        if original_real_targets is None:
            os.environ.pop('MACCOMPANION_NATIVE_LAB_SELECTED_SURFACES', None)
        else:
            os.environ['MACCOMPANION_NATIVE_LAB_SELECTED_SURFACES'] = original_real_targets
        # Remove the one transient QR from the test configuration. Logs and
        # xcresult are private local diagnostics and must never be committed.
        ui_targets[0].get('EnvironmentVariables', {}).pop('MACCOMPANION_TEST_PAIRING_CODE', None)
        ui_targets[0].get('EnvironmentVariables', {}).pop('MACCOMPANION_TEST_CONSENT_FIXTURE', None)
        ui_targets[0].get('EnvironmentVariables', {}).pop('MACCOMPANION_TEST_WINDOW_SOAK_TRANSITIONS', None)
        ui_targets[0].get('EnvironmentVariables', {}).pop('MACCOMPANION_TEST_PICKER_WINDOW_CLOSE_PATH', None)
        ui_targets[0].get('EnvironmentVariables', {}).pop('MACCOMPANION_TEST_NATIVE_SESSION_SOAK_COUNT', None)
        ui_targets[0].get('EnvironmentVariables', {}).pop('MACCOMPANION_TEST_NATIVE_HOLD_SECONDS', None)
        run_file.write_bytes(plistlib.dumps(run))
        try:
            probe.cleanup()
            cleaned = True
        except Exception as error:
            failure = f'{failure or ""} Cleanup: {error}'
        if original_state is not None:
            try:
                stop_app(simulator)
                if client_id and host_id:
                    unit = next(target for target in targets if not target.get('IsUITestBundle'))
                    unit.setdefault('EnvironmentVariables', {}).update({
                        'MACCOMPANION_TEST_CLIENT_ID': client_id, 'MACCOMPANION_TEST_HOST_ID': host_id})
                    run_file.write_bytes(plistlib.dumps(run))
                    with (output / 'key-cleanup.log').open('w') as log:
                        result = subprocess.run(['xcodebuild', '-xctestrun', str(run_file), '-destination',
                            'platform=iOS Simulator,id=' + simulator, '-parallel-testing-enabled', 'NO',
                            '-collect-test-diagnostics', 'never',
                            '-only-testing:NormalIdentityCleanup/PairedIdentityCleanup/testDiscardExactOwnedPairKeys',
                            '-resultBundlePath', str(output / 'cleanup.xcresult'), 'test-without-building'],
                            stdout=log, stderr=subprocess.STDOUT, timeout=120)
                    summary = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results',
                        'summary', '--path', str(output / 'cleanup.xcresult')]))
                    cleanup_counts, client_keys_cleaned = verified_counts(summary, result.returncode)
                    assert client_keys_cleaned and cleanup_counts['totalTestCount'] == 1
            except Exception as error:
                failure = f'{failure or ""} Client key cleanup: {error}'
            try:
                stop_app(simulator)
                root = simulator_root(simulator)
                if root.exists():
                    assert tree_hashes(root) is not None
                    if client_id:
                        assert uuid.UUID(json.loads((root / 'installation-v1.json').read_text())['clientID']) == uuid.UUID(client_id)
                    shutil.rmtree(root)
                original_state.rename(root)
                assert tree_hashes(root) == original_hashes
                state_restored = True
                for target in targets:
                    for key in ['MACCOMPANION_TEST_CLIENT_ID', 'MACCOMPANION_TEST_HOST_ID']:
                        target.get('EnvironmentVariables', {}).pop(key, None)
                run_file.write_bytes(plistlib.dumps(run))
            except Exception as error:
                failure = f'{failure or ""} State restoration: {error}'
        if complete_pairing:
            try:
                # Restore the original app even if preflight failed before any
                # Simulator state was moved or any host was started.
                stop_app(simulator)
                shutil.rmtree(app)
                shutil.copytree(output / 'OriginalApplication.app', app)
                assert digest(app / 'Mac Companion') == baseline['normalApplicationBinarySHA256']
                subprocess.run(['xcrun', 'simctl', 'install', simulator, str(app)], check=True, timeout=30)
            except Exception as error:
                failure = f'{failure or ""} App restoration: {error}'
        if lock_owned:
            lock.rmdir()
    report = {'profile': 'maccompanion.normal-native-live-pairing.v1',
        'status': 'passed' if passed and cleaned and client_keys_cleaned and state_restored and failure is None else 'failed',
        'tests': counts, 'failure': failure, 'cleanupVerified': cleaned, 'hostEvidence': str(probe.evidence),
        'sourceInputSHA256': source, 'hostSourceSHA256': host_source, 'uiInputs': inputs,
        'baselineReportSHA256': baseline_report_sha,
        'applicationBinarySHA256': tested_binary_sha, 'simulatorID': simulator,
        'nativeFrameworkSHA256': frameworks,
        'normalSourceRoot': True, 'clientApprovalPresenceSubstituted': False, 'macApprovalWithheld': not complete_pairing,
        'macConsentSubstituted': complete_pairing, 'clientKeyCleanupVerified': client_keys_cleaned,
        'simulatorStateRestored': state_restored, 'keyCleanupTests': cleanup_counts,
        'reusedDevelopmentBuildProject': reuse_build_project,
        'baselineArtifactMayBeRebuilt': reuse_build_project,
        'simulatorEntitlements': entitlement_record,
        'liveTLSAndPairingProofVerified': passed and failure is None, 'paired': complete_pairing and passed,
        'workspaceRestartVerified': complete_pairing and passed,
        'nativeControlRequested': native, 'nativeSessionVerified': native and passed and failure is None,
        'nativePresentedSessions': ((22 if native_window_soak else 10 if native_session_soak else 1 if native_session_hold or native_video_continuity else 4 if native_window_auto_recovery else 3 if native_window_resize_restart else 2 if window_change is not None else 3 if native_connection_loss or native_surface_replacement else 2)
            + (2 if native_surface_replacement else 0))
            if native and passed and failure is None else 0,
        'nativeSharedDisplayPickerVerified': native_surface_replacement and passed and failure is None,
        'nativeSharedDisplayReplacementVerified': native_surface_replacement and passed and failure is None,
        'nativeDisplayLayoutContainmentVerified': native_surface_replacement and passed and failure is None,
        'nativeCompactKeyboardBarVerified': native and (window_change is None or native_window_auto_recovery) and passed and failure is None,
        'nativeSingleStopControlVerified': native and passed and failure is None,
        'nativeSurfaceTransitionsVerified': 20 if native_window_soak and passed and failure is None else 0,
        'nativeSessionStartsAndStopsVerified': 10 if native_session_soak and passed and failure is None else 0,
        'nativeSustainedMinutesVerified': (30 if native_session_hold else 1 if native_video_continuity else 0)
            if passed and failure is None else 0,
        'nativeClientFrameProgressVerified': native_video_continuity and passed and failure is None,
        'nativeKeyboardDeliveryVerified': native and (window_change is None or native_window_auto_recovery) and passed and failure is None,
        'nativePointerModifierShortcutDeliveryVerified': native and (window_change is None or native_window_auto_recovery) and passed and failure is None,
        'nativeBackgroundInputFencingVerified': native_background and passed and failure is None,
        'nativeForegroundRequiresExplicitRestartVerified': native_background and passed and failure is None,
        'nativePrimaryConnectionLossRecoveryVerified': native_connection_loss and passed and failure is None,
        'nativeRealTargetCatalogVerified': native_real_targets and passed and failure is None,
        'nativeSelectedTargetVerified': (native_selected_target or native_selected_window)
            and not native_picker_window_disappearance and passed and failure is None,
        'nativeSelectedWindowVerified': native_selected_window and not native_picker_window_disappearance and passed and failure is None,
        'nativePickerWindowDisappearanceRecoveryVerified': native_picker_window_disappearance and passed and failure is None,
        'nativeSelectedWindowOtherDisplayVerified': native_selected_window_other_display and passed and failure is None,
        'nativeSelectedStaticTargetVerified': native_selected_target_static and not native_picker_window_disappearance and passed and failure is None,
        'nativeSelectedWindowClosureVerified': native_window_closure and passed and failure is None,
        'nativeSelectedWindowMoveRecoveryVerified': native_window_move and passed and failure is None,
        'nativeSelectedWindowResizeRecoveryVerified': native_window_resize and passed and failure is None,
        'nativeSelectedWindowAutomaticDesktopRecoveryVerified': native_window_auto_recovery and passed and failure is None,
        'nativeSelectedWindowResizeRestartVerified': native_window_resize_restart and passed and failure is None,
        'nativeSelectedWindowResizeRapidStopVerified': native_window_resize_rapid_stop and passed and failure is None,
        'nativeReplacementMenuAdmissionVerified': native_window_resize_restart and passed and failure is None,
        'nativeHostPackageManifestSHA256': native_manifest_sha,
        'nativeFinalInputSynthetic': native,
        'physicalDevice': False, 'installedMacProduct': False}
    (output / 'report.json').write_text(json.dumps(report, sort_keys=True, indent=2) + '\n')
    print(json.dumps(report, sort_keys=True), flush=True)
    return report['status'] == 'passed'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--simulator', required=True)
    parser.add_argument('--resume-build', action='store_true', help='Reuse this runner’s identical project after a pre-test failure')
    parser.add_argument('--reuse-build-project', action='store_true', help='Reuse the disposable normal build project/cache; its app artifact may be rebuilt')
    parser.add_argument('--complete-pairing', action='store_true', help='Approve the disposable host pair, verify normal workspace/restart, and restore owned Simulator state')
    parser.add_argument('--native-root', type=Path, help='Use a disposable native host for normal Control, with --complete-pairing')
    parser.add_argument('--native-host-package', type=Path, help='Exact verified portable development host package')
    parser.add_argument('--native-background', action='store_true', help='Exercise real normal-app background input fencing and explicit native restart')
    parser.add_argument('--native-connection-loss', action='store_true', help='Drain/reopen the disposable primary listener during active Control and exercise normal Reconnect')
    parser.add_argument('--native-surface-replacement', action='store_true', help='Switch synthetic Desktop in normal native Control and verify fresh presentation')
    parser.add_argument('--native-real-targets', action='store_true', help='Use the real menu-owned ScreenCaptureKit target catalog during native surface replacement')
    parser.add_argument('--native-selected-target', action='store_true', help='Select the disposable AppKit application through the normal iOS picker')
    parser.add_argument('--native-selected-window', action='store_true', help='Select the disposable AppKit window through the normal iOS picker')
    parser.add_argument('--native-selected-window-other-display', action='store_true',
                        help='Place the disposable selected Window on another physical display from the main Desktop')
    parser.add_argument('--native-picker-window-disappearance', action='store_true',
                        help='Close the owned disposable Window after inventory, then verify acknowledged Desktop recovery')
    parser.add_argument('--native-selected-target-static', action='store_true',
                        help='Keep the disposable selected App/Window static to exercise a typical idle interface')
    parser.add_argument('--native-window-soak', action='store_true', help='Repeat 20 selected Window/Desktop transitions in one normal Control journey')
    parser.add_argument('--native-session-soak', action='store_true', help='Run ten normal Control start/Stop journeys with fresh video and input')
    parser.add_argument('--native-session-hold', action='store_true', help='Keep one normal Control journey active for 30 minutes with continued video and input')
    parser.add_argument('--native-video-continuity', action='store_true', help='Keep one normal Control journey active for one minute and require ongoing local video-frame progress')
    parser.add_argument('--native-window-closure', action='store_true', help='Close the disposable selected Window after native presentation and require Control retirement')
    parser.add_argument('--native-window-move', action='store_true', help='Move the disposable selected Window after native presentation and require fail-closed recovery')
    parser.add_argument('--native-window-resize', action='store_true', help='Resize the disposable selected Window after native presentation and require fail-closed recovery')
    parser.add_argument('--native-window-auto-recovery', action='store_true', help='Require one fresh Desktop replacement within the current Control session after resizing')
    parser.add_argument('--native-window-resize-restart', action='store_true', help='After resizing, replace the disposable Mac menu and require a sustained fresh Control stream')
    parser.add_argument('--native-window-resize-rapid-stop', action='store_true', help='Stop promptly after restarted input enables and require clean backend retirement')
    args = parser.parse_args()
    os.environ.setdefault('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer')
    sys.exit(0 if verify(args.build_root.resolve(), args.output.resolve(), args.simulator,
                        args.resume_build, args.reuse_build_project, args.complete_pairing,
                        args.native_root.resolve() if args.native_root else None,
                        args.native_host_package.resolve() if args.native_host_package else None,
                        args.native_background, args.native_connection_loss,
                        args.native_surface_replacement, args.native_real_targets,
                        args.native_selected_target, args.native_selected_window, args.native_window_soak,
                        args.native_session_soak, args.native_session_hold,
                        args.native_video_continuity, args.native_window_closure,
                        args.native_window_move, args.native_window_resize,
                        args.native_window_resize_restart, args.native_window_resize_rapid_stop,
                        args.native_selected_window_other_display, args.native_selected_target_static, args.native_picker_window_disappearance, args.native_window_auto_recovery) else 1)
