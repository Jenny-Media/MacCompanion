#!/usr/bin/env python3
"""Run the direct client QA target plus OpenSSH and sandboxed setup checks.

Requires a completed build_vnc_ios_development.py Simulator output. All test
keys are fresh, temporary and synthetic. The user's ~/.ssh is never modified.
"""
import argparse
from build_cache import compiler_workspace
import os
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(*args, **kw):
    return subprocess.run([str(x) for x in args], check=True, **kw)


def verify_external(folder):
    key = folder / 'encrypted-key'
    public = subprocess.check_output(['/usr/bin/ssh-keygen', '-y', '-P', 'synthetic-export-only', '-f', str(key)], text=True).strip()
    assert ' '.join(public.split()[:2]) == (folder / 'expected-public').read_text()
    command = (folder / 'installation-command').read_text()
    with tempfile.TemporaryDirectory(prefix='maccompanion-key-setup-', dir='/private/tmp') as tmp:
        base = Path(tmp)
        ssh = base / '.ssh'
        def execute():
            # Redirect the fixed generated command into a dedicated fixture folder.
            assert command.count('ssh_dir="$HOME/.ssh"') == 1
            escaped = str(ssh).replace("'", "'\\''")
            script = command.replace('ssh_dir="$HOME/.ssh"', 'ssh_dir="' + escaped + '"')
            return subprocess.run(['/bin/sh', '-c', script], capture_output=True, text=True)
        ssh.mkdir(); auth = ssh / 'authorized_keys'
        original = '# preserved comment\nrestrict ssh-ed25519 AAAA synthetic-existing\n'
        auth.write_text(original)
        result = execute(); assert result.returncode == 0 and result.stdout.strip() == 'MC_KEY_INSTALLED'
        content = auth.read_text(); assert content.startswith(original) and public.split()[1] in content
        assert (ssh.stat().st_mode & 0o777) == 0o700 and (auth.stat().st_mode & 0o777) == 0o600
        result = execute(); assert result.returncode == 0 and result.stdout.strip() == 'MC_KEY_PRESENT' and auth.read_text() == content
        auth.write_text('restrict ' + public + ' another-comment\n')
        restricted = auth.read_text(); assert execute().stdout.strip() == 'MC_KEY_PRESENT' and auth.read_text() == restricted
        # An unrelated key's comment is not an installed target key.
        auth.write_text(original + 'ssh-ed25519 AAAA backup public key: ' + public + '\n')
        assert execute().stdout.strip() == 'MC_KEY_INSTALLED'
        # Quoted options can include spaces, quotes, and key-like text.
        auth.write_text('command="echo ssh-ed25519 ' + public.split()[1] + ' \\"quoted\\"",restrict ' + public + '\n')
        quoted = auth.read_text(); assert execute().stdout.strip() == 'MC_KEY_PRESENT' and auth.read_text() == quoted
        auth.unlink(); outside = base / 'outside'; outside.write_text('preserved')
        auth.symlink_to(outside); assert execute().returncode != 0 and outside.read_text() == 'preserved'; auth.unlink()
        os.link(outside, auth); assert execute().returncode != 0 and outside.read_text() == 'preserved'; auth.unlink()
        ssh.rmdir(); ssh.symlink_to(base); assert execute().returncode != 0; ssh.unlink()
    shutil.rmtree(folder)
    print('OpenSSH encrypted export and authorized_keys preservation/duplicate/link/permissions checks passed.')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--build', type=Path, required=True)
    parser.add_argument('--simulator', required=True)
    parser.add_argument('--test-diagnostics', choices=['on-failure', 'never'], default='on-failure')
    parser.add_argument('--screenshots', action='store_true', help='Capture synthetic recovery screens in the hosted Simulator tests')
    parser.add_argument('--duo-review', action='store_true', help='Run only the opt-in interactive, synthetic Duo comparison capture')
    parser.add_argument('--generate-only', action='store_true', help='Generate the private QA project without running tests')
    parser.add_argument('--composer-ui', action='store_true', help='Generate the simulator-only Maps-style composer app and native drag test scheme')
    parser.add_argument('--cold-start-ui', action='store_true', help='Generate native cold-start admission interaction tests')
    parser.add_argument('--saved-controls-ui', action='store_true', help='Check unified sync consent and concise guidance with an injected no-cloud QA app')
    parser.add_argument('--local-backup-e2e', action='store_true', help='Run opt-in two-device backup UI stages in an isolated app with production file and Keychain stores')
    parser.add_argument('--settings-ui', action='store_true', help='Also test gear navigation and live sheet appearance using native UI interactions')
    parser.add_argument('--screen-text-ui', action='store_true', help='Generate the simulator-only native/area text selection UI journey')
    parser.add_argument('--mac-shortcuts-ui', action='store_true', help='Generate the simulator-only per-Mac shortcuts and native swipe tests')
    parser.add_argument('--terminal-controls-ui', action='store_true', help='Run the simulator-only shared Terminal controls Save/Cancel UI journey')
    parser.add_argument('--terminal-controls-review', action='store_true', help='Keep the verified-Pro synthetic connected terminal open for a ten-minute interactive review')
    parser.add_argument('--only-testing', action='append', default=[], help='Run a focused XCTest identifier; repeat to select multiple suites')
    parser.add_argument('--terminal-tool-host', type=Path, help='Private descriptor from the opt-in loopback terminal-tool test host')
    args = parser.parse_args()
    with compiler_workspace(args.build, ROOT) as compiler:
        execute(args, parser, compiler)


def execute(args, parser, compiler):
    base = args.build.resolve()
    qa = compiler / 'QA'; qa.mkdir(exist_ok=True)
    evidence = base / 'QA'; evidence.mkdir(exist_ok=True)
    spec = json.loads((base / 'project.json').read_text())
    spec['name'] = 'DirectClientQA'
    app = spec['targets']['MacCompanionIOS']; settings = app['settings']['base']
    for source in app['sources']:
        if not Path(source['path']).is_absolute(): source['path'] = str(base / source['path'])
    bundle = 'dev.maccompanion.proqa.ios'
    settings['PRODUCT_BUNDLE_IDENTIFIER'] = bundle
    entitlements = qa / 'QA.entitlements'
    entitlements.write_bytes(plistlib.dumps({'application-identifier': bundle, 'keychain-access-groups': [bundle]}))
    settings['CODE_SIGN_ENTITLEMENTS'] = str(entitlements)
    widget = spec['targets']['MacCompanionSessionActivity']
    widget['settings']['base']['PRODUCT_BUNDLE_IDENTIFIER'] = bundle + '.session-status'
    for algorithm, name, secret in [('ed25519', 'synthetic-ed25519', 'synthetic-import-only'), ('rsa', 'synthetic-rsa', '')]:
        destination = qa / name
        if not destination.exists(): run('/usr/bin/ssh-keygen', '-q', '-t', algorithm, '-N', secret, '-f', destination)
    resources = [ROOT / 'spec/fixtures/manifest.json', ROOT / 'spec/fixtures/direct-screen-sharing-v1.json', ROOT / 'spec/fixtures/vnc-desktop-tunnel-v0.1.json',
                 ROOT / 'spec/fixtures/direct-files-v1.json', ROOT / 'spec/fixtures/ios-text-composer-v1.json',
                 ROOT / 'spec/fixtures/ios-dynamic-resolution-prototype-v1.json',
                 ROOT / 'spec/fixtures/terminal-compatibility-v1.json',
                 ROOT / 'spec/storekit/v0/LifetimePro.storekit', qa / 'synthetic-ed25519', qa / 'synthetic-ed25519.pub', qa / 'synthetic-rsa']
    spec['targets']['DirectClientTests'] = {
        'type': 'bundle.unit-test', 'platform': 'iOS',
        'sources': [{'path': str(ROOT / 'Experiments/NormalVNCViewportQA')}, {'path': str(ROOT / 'Native/ClientTests')}] + [{'path': str(p), 'buildPhase': 'resources'} for p in resources],
        'dependencies': [{'target': 'MacCompanionIOS'}],
        'settings': {'base': {'GENERATE_INFOPLIST_FILE': 'YES', 'PRODUCT_BUNDLE_IDENTIFIER': bundle + '.tests',
            'SWIFT_VERSION': '6.0', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG MACCOMPANION_VNC_DEVELOPMENT',
            'IPHONEOS_DEPLOYMENT_TARGET': '26.0', 'ARCHS': 'arm64', 'ONLY_ACTIVE_ARCH': 'YES',
            'CODE_SIGN_IDENTITY': '-', 'CODE_SIGNING_ALLOWED': 'YES', 'CLANG_ENABLE_OBJC_ARC': 'YES',
            'HEADER_SEARCH_PATHS': [str(ROOT / 'Native/VNC')] + settings['HEADER_SEARCH_PATHS'],
            'TEST_HOST': '$(BUILT_PRODUCTS_DIR)/Mac Companion.app/Mac Companion', 'BUNDLE_LOADER': '$(TEST_HOST)'}}}
    spec['schemes'] = {'DirectClientQA': {'build': {'targets': {'MacCompanionIOS': 'all', 'DirectClientTests': 'all'}},
        'test': {'config': 'Debug', 'macroExpansion': 'MacCompanionIOS', 'targets': [{'name': 'DirectClientTests', 'parallelizable': False}],
                 'storeKitConfiguration': str(ROOT / 'spec/storekit/v0/LifetimePro.storekit')}}}
    for action in ['run', 'profile', 'analyze', 'archive']: spec['schemes']['DirectClientQA'][action] = {'config': 'Debug'}
    if args.settings_ui:
        spec['targets']['SettingsNavigationTests'] = {
            'type': 'bundle.ui-testing', 'platform': 'iOS',
            'sources': [{'path': str(ROOT / 'Experiments/DirectClientSettingsQA')}],
            'dependencies': [{'target': 'MacCompanionIOS'}],
            'settings': {'base': {'GENERATE_INFOPLIST_FILE': 'YES', 'PRODUCT_BUNDLE_IDENTIFIER': bundle + '.settings-ui',
                'SWIFT_VERSION': '6.0', 'IPHONEOS_DEPLOYMENT_TARGET': '26.0', 'ARCHS': 'arm64', 'ONLY_ACTIVE_ARCH': 'YES',
                'CODE_SIGN_IDENTITY': '-', 'CODE_SIGNING_ALLOWED': 'YES', 'TEST_TARGET_NAME': 'MacCompanionIOS'}}}
        spec['schemes']['DirectClientQA']['build']['targets']['SettingsNavigationTests'] = 'all'
        spec['schemes']['DirectClientQA']['test']['targets'].append({'name': 'SettingsNavigationTests', 'parallelizable': False})
        spec['schemes']['DirectClientQA']['test'].setdefault('environmentVariables', {})['MACCOMPANION_SETTINGS_QA_BUNDLE'] = bundle
    shutil.copyfile(ROOT / 'spec/storekit/v0/LifetimePro.storekit', qa / 'LifetimePro.storekit')
    spec['schemes']['DirectClientQA']['run'].update({'executable': 'MacCompanionIOS', 'macroExpansion': 'MacCompanionIOS', 'storeKitConfiguration': 'LifetimePro.storekit'})
    if args.screenshots:
        spec['schemes']['DirectClientQA']['run']['environmentVariables'] = {'MACCOMPANION_SCREENSHOT_REVIEW': '1'}
        spec['schemes']['DirectClientQA']['test'].setdefault('environmentVariables', {})['MACCOMPANION_SCREENSHOT_REVIEW'] = '1'
    if args.duo_review:
        spec['schemes']['DirectClientQA']['run']['environmentVariables'] = {'MACCOMPANION_DUO_REVIEW': '1'}
    if args.composer_ui:
        import copy
        sheet = copy.deepcopy(app)
        sheet['sources'] = [row for row in sheet['sources'] if not row['path'].startswith(str(ROOT / 'Apps/MacCompanionIOS'))]
        sheet['sources'].append({'path': str(ROOT / 'Experiments/ComposerSheetQA/ComposerSheetApplication.swift')})
        sheet['settings']['base']['PRODUCT_BUNDLE_IDENTIFIER'] = 'dev.maccompanion.sheetqa.ios'
        sheet['settings']['base']['PRODUCT_NAME'] = 'ComposerSheetQA'
        sheet['settings']['base']['PRODUCT_MODULE_NAME'] = 'Mac_Companion'
        sheet['dependencies'] = [row for row in sheet['dependencies'] if row.get('target') != 'MacCompanionSessionActivity']
        spec['targets']['ComposerSheetApp'] = sheet
        spec['targets']['ComposerSheetUITests'] = {
            'type': 'bundle.ui-testing', 'platform': 'iOS',
            'sources': [{'path': str(ROOT / 'Experiments/ComposerSheetQA/ComposerSheetUITests.swift')}],
            'dependencies': [{'target': 'ComposerSheetApp'}],
            'settings': {'base': {'GENERATE_INFOPLIST_FILE': 'YES', 'PRODUCT_BUNDLE_IDENTIFIER': 'dev.maccompanion.sheetqa.ios.tests',
                'SWIFT_VERSION': '6.0', 'IPHONEOS_DEPLOYMENT_TARGET': '26.0', 'ARCHS': 'arm64', 'ONLY_ACTIVE_ARCH': 'YES',
                'CODE_SIGN_IDENTITY': '-', 'CODE_SIGNING_ALLOWED': 'YES', 'TEST_TARGET_NAME': 'ComposerSheetApp'}}}
        spec['schemes']['ComposerSheetQA'] = {'build': {'targets': {'ComposerSheetApp': 'all', 'ComposerSheetUITests': 'all'}},
            'test': {'config': 'Debug', 'macroExpansion': 'ComposerSheetApp', 'targets': [{'name': 'ComposerSheetUITests', 'parallelizable': False}]}}
        for action in ['run', 'profile', 'analyze', 'archive']:
            spec['schemes']['ComposerSheetQA'][action] = {'config': 'Debug'}
    if args.saved_controls_ui:
        import copy
        consent = copy.deepcopy(app)
        consent['sources'] = [row for row in consent['sources'] if not row['path'].startswith(str(ROOT / 'Apps/MacCompanionIOS'))]
        consent['sources'].append({'path': str(ROOT / 'Experiments/SavedControlsConsentQA/SavedControlsConsentApplication.swift')})
        consent['sources'].append({'path': str(ROOT / 'Apps/MacCompanionIOS/Assets.xcassets')})
        consent['settings']['base'].update({'PRODUCT_BUNDLE_IDENTIFIER': 'dev.maccompanion.savedcontrolsqa.ios',
                                          'PRODUCT_NAME': 'SavedControlsConsentQA', 'PRODUCT_MODULE_NAME': 'Mac_Companion'})
        consent['dependencies'] = [row for row in consent['dependencies'] if row.get('target') != 'MacCompanionSessionActivity']
        spec['targets']['SavedControlsConsentApp'] = consent
        spec['targets']['SavedControlsConsentTests'] = {
            'type': 'bundle.ui-testing', 'platform': 'iOS',
            'sources': [{'path': str(ROOT / 'Experiments/SavedControlsConsentQA/SavedControlsConsentTests.swift')}],
            'dependencies': [{'target': 'SavedControlsConsentApp'}],
            'settings': {'base': {'GENERATE_INFOPLIST_FILE': 'YES', 'PRODUCT_BUNDLE_IDENTIFIER': 'dev.maccompanion.savedcontrolsqa.ios.tests',
                'SWIFT_VERSION': '6.0', 'IPHONEOS_DEPLOYMENT_TARGET': '26.0', 'ARCHS': 'arm64', 'ONLY_ACTIVE_ARCH': 'YES',
                'CODE_SIGN_IDENTITY': '-', 'CODE_SIGNING_ALLOWED': 'YES', 'TEST_TARGET_NAME': 'SavedControlsConsentApp'}}}
        spec['schemes']['SavedControlsConsentQA'] = {'build': {'targets': {'SavedControlsConsentApp': 'all', 'SavedControlsConsentTests': 'all'}},
            'test': {'config': 'Debug', 'macroExpansion': 'SavedControlsConsentApp', 'targets': [{'name': 'SavedControlsConsentTests', 'parallelizable': False}]}}
        for action in ['run', 'profile', 'analyze', 'archive']:
            spec['schemes']['SavedControlsConsentQA'][action] = {'config': 'Debug'}
    if args.local_backup_e2e:
        import copy
        local = copy.deepcopy(app)
        local['sources'] = [row for row in local['sources'] if not row['path'].startswith(str(ROOT / 'Apps/MacCompanionIOS'))]
        local['sources'] += [{'path': str(ROOT / 'Experiments/LocalBackupE2EQA/LocalBackupApplication.swift')},
                             {'path': str(ROOT / 'Apps/MacCompanionIOS/Assets.xcassets')}]
        local_id = 'dev.maccompanion.backupe2e.ios'
        local_entitlements = qa / 'LocalBackupE2E.entitlements'
        local_entitlements.write_bytes(plistlib.dumps({'application-identifier': local_id, 'keychain-access-groups': [local_id]}))
        local_info = qa / 'LocalBackupE2E-Info.plist'
        properties = plistlib.loads(Path(settings['INFOPLIST_FILE']).read_bytes())
        properties.update({'CFBundleDisplayName': 'Mac Companion Backup QA', 'UIFileSharingEnabled': True,
                           'LSSupportsOpeningDocumentsInPlace': True})
        local_info.write_bytes(plistlib.dumps(properties))
        local['settings']['base'].update({'PRODUCT_BUNDLE_IDENTIFIER': local_id, 'PRODUCT_NAME': 'LocalBackupE2EQA',
            'PRODUCT_MODULE_NAME': 'Mac_Companion', 'CODE_SIGN_ENTITLEMENTS': str(local_entitlements), 'INFOPLIST_FILE': str(local_info)})
        local['dependencies'] = [row for row in local['dependencies'] if row.get('target') != 'MacCompanionSessionActivity']
        spec['targets']['LocalBackupE2EApp'] = local
        spec['targets']['LocalBackupE2ETests'] = {
            'type': 'bundle.ui-testing', 'platform': 'iOS',
            'sources': [{'path': str(ROOT / 'Experiments/LocalBackupE2EQA/LocalBackupE2ETests.swift')}],
            'dependencies': [{'target': 'LocalBackupE2EApp'}],
            'settings': {'base': {'GENERATE_INFOPLIST_FILE': 'YES', 'PRODUCT_BUNDLE_IDENTIFIER': local_id + '.tests',
                'SWIFT_VERSION': '6.0', 'IPHONEOS_DEPLOYMENT_TARGET': '26.0', 'ARCHS': 'arm64', 'ONLY_ACTIVE_ARCH': 'YES',
                'CODE_SIGN_IDENTITY': '-', 'CODE_SIGNING_ALLOWED': 'YES', 'TEST_TARGET_NAME': 'LocalBackupE2EApp'}}}
        spec['schemes']['LocalBackupE2EQA'] = {'build': {'targets': {'LocalBackupE2EApp': 'all', 'LocalBackupE2ETests': 'all'}},
            'test': {'config': 'Debug', 'macroExpansion': 'LocalBackupE2EApp', 'targets': [{'name': 'LocalBackupE2ETests', 'parallelizable': False}]}}
        for action in ['run', 'profile', 'analyze', 'archive']:
            spec['schemes']['LocalBackupE2EQA'][action] = {'config': 'Debug'}
    if args.cold_start_ui:
        import copy
        cold = copy.deepcopy(app)
        cold['sources'] = [row for row in cold['sources'] if not row['path'].startswith(str(ROOT / 'Apps/MacCompanionIOS'))]
        cold['sources'].append({'path': str(ROOT / 'Experiments/ColdStartQA/ColdStartApplication.swift')})
        cold['sources'].append({'path': str(ROOT / 'Apps/MacCompanionIOS/Assets.xcassets')})
        cold['settings']['base'].update({'PRODUCT_BUNDLE_IDENTIFIER': 'dev.maccompanion.coldstartqa.ios',
                                        'PRODUCT_NAME': 'ColdStartQA', 'PRODUCT_MODULE_NAME': 'Mac_Companion'})
        cold['dependencies'] = [row for row in cold['dependencies'] if row.get('target') != 'MacCompanionSessionActivity']
        spec['targets']['ColdStartApp'] = cold
        spec['targets']['ColdStartUITests'] = {
            'type': 'bundle.ui-testing', 'platform': 'iOS',
            'sources': [{'path': str(ROOT / 'Experiments/ColdStartQA/ColdStartUITests.swift')}],
            'dependencies': [{'target': 'ColdStartApp'}],
            'settings': {'base': {'GENERATE_INFOPLIST_FILE': 'YES', 'PRODUCT_BUNDLE_IDENTIFIER': 'dev.maccompanion.coldstartqa.ios.tests',
                'SWIFT_VERSION': '6.0', 'IPHONEOS_DEPLOYMENT_TARGET': '26.0', 'ARCHS': 'arm64', 'ONLY_ACTIVE_ARCH': 'YES',
                'CODE_SIGN_IDENTITY': '-', 'CODE_SIGNING_ALLOWED': 'YES', 'TEST_TARGET_NAME': 'ColdStartApp'}}}
        spec['schemes']['ColdStartQA'] = {'build': {'targets': {'ColdStartApp': 'all', 'ColdStartUITests': 'all'}},
            'test': {'config': 'Debug', 'macroExpansion': 'ColdStartApp', 'targets': [{'name': 'ColdStartUITests', 'parallelizable': False}]}}
        for action in ['run', 'profile', 'analyze', 'archive']:
            spec['schemes']['ColdStartQA'][action] = {'config': 'Debug'}
    if args.screen_text_ui:
        import copy
        screen = copy.deepcopy(app)
        screen['sources'] = [row for row in screen['sources'] if not row['path'].startswith(str(ROOT / 'Apps/MacCompanionIOS'))]
        screen['sources'].append({'path': str(ROOT / 'Experiments/ScreenTextQA/ScreenTextQAApplication.swift')})
        screen['settings']['base'].update({'PRODUCT_BUNDLE_IDENTIFIER': 'dev.maccompanion.screentextqa.ios',
                                          'PRODUCT_NAME': 'ScreenTextQA', 'PRODUCT_MODULE_NAME': 'Mac_Companion'})
        screen['dependencies'] = [row for row in screen['dependencies'] if row.get('target') != 'MacCompanionSessionActivity']
        spec['targets']['ScreenTextApp'] = screen
        spec['targets']['ScreenTextUITests'] = {
            'type': 'bundle.ui-testing', 'platform': 'iOS',
            'sources': [{'path': str(ROOT / 'Experiments/ScreenTextQA/ScreenTextUITests.swift')}],
            'dependencies': [{'target': 'ScreenTextApp'}],
            'settings': {'base': {'GENERATE_INFOPLIST_FILE': 'YES', 'PRODUCT_BUNDLE_IDENTIFIER': 'dev.maccompanion.screentextqa.ios.tests',
                'SWIFT_VERSION': '6.0', 'IPHONEOS_DEPLOYMENT_TARGET': '26.0', 'ARCHS': 'arm64', 'ONLY_ACTIVE_ARCH': 'YES',
                'CODE_SIGN_IDENTITY': '-', 'CODE_SIGNING_ALLOWED': 'YES', 'TEST_TARGET_NAME': 'ScreenTextApp'}}}
        spec['schemes']['ScreenTextQA'] = {'build': {'targets': {'ScreenTextApp': 'all', 'ScreenTextUITests': 'all'}},
            'test': {'config': 'Debug', 'macroExpansion': 'ScreenTextApp', 'targets': [{'name': 'ScreenTextUITests', 'parallelizable': False}]}}
        for action in ['run', 'profile', 'analyze', 'archive']:
            spec['schemes']['ScreenTextQA'][action] = {'config': 'Debug'}
    if args.mac_shortcuts_ui:
        import copy
        shortcuts = copy.deepcopy(app)
        shortcuts['sources'] = [row for row in shortcuts['sources'] if not row['path'].startswith(str(ROOT / 'Apps/MacCompanionIOS'))]
        shortcuts['sources'].append({'path': str(ROOT / 'Experiments/MacShortcutsQA/MacShortcutsApplication.swift')})
        shortcuts['settings']['base'].update({'PRODUCT_BUNDLE_IDENTIFIER': 'dev.maccompanion.shortcutsqa.ios',
                                            'PRODUCT_NAME': 'MacShortcutsQA', 'PRODUCT_MODULE_NAME': 'Mac_Companion'})
        shortcuts['dependencies'] = [row for row in shortcuts['dependencies'] if row.get('target') != 'MacCompanionSessionActivity']
        spec['targets']['MacShortcutsApp'] = shortcuts
        spec['targets']['MacShortcutsUITests'] = {
            'type': 'bundle.ui-testing', 'platform': 'iOS',
            'sources': [{'path': str(ROOT / 'Experiments/MacShortcutsQA/MacShortcutsUITests.swift')}],
            'dependencies': [{'target': 'MacShortcutsApp'}],
            'settings': {'base': {'GENERATE_INFOPLIST_FILE': 'YES', 'PRODUCT_BUNDLE_IDENTIFIER': 'dev.maccompanion.shortcutsqa.ios.tests',
                'SWIFT_VERSION': '6.0', 'IPHONEOS_DEPLOYMENT_TARGET': '26.0', 'ARCHS': 'arm64', 'ONLY_ACTIVE_ARCH': 'YES',
                'CODE_SIGN_IDENTITY': '-', 'CODE_SIGNING_ALLOWED': 'YES', 'TEST_TARGET_NAME': 'MacShortcutsApp'}}}
        spec['schemes']['MacShortcutsQA'] = {'build': {'targets': {'MacShortcutsApp': 'all', 'MacShortcutsUITests': 'all'}},
            'test': {'config': 'Debug', 'macroExpansion': 'MacShortcutsApp', 'targets': [{'name': 'MacShortcutsUITests', 'parallelizable': False}]}}
        for action in ['run', 'profile', 'analyze', 'archive']:
            spec['schemes']['MacShortcutsQA'][action] = {'config': 'Debug'}
    if args.terminal_controls_ui:
        import copy
        controls = copy.deepcopy(app)
        controls['sources'] = [row for row in controls['sources'] if not row['path'].startswith(str(ROOT / 'Apps/MacCompanionIOS'))]
        controls['sources'].append({'path': str(ROOT / 'Experiments/TerminalControlsQA/TerminalControlsApplication.swift')})
        controls['sources'].append({'path': str(ROOT / 'Experiments/NormalVNCViewportQA/SSHTestServer.swift')})
        controls['sources'].append({'path': str(ROOT / 'spec/storekit/v0/LifetimePro.storekit'), 'buildPhase': 'resources'})
        controls['sources'].append({'path': str(ROOT / 'spec/fixtures/terminal-compatibility-v1.json'), 'buildPhase': 'resources'})
        controls['settings']['base'].update({'PRODUCT_BUNDLE_IDENTIFIER': 'dev.maccompanion.controlsqa.ios',
                                            'PRODUCT_NAME': 'TerminalControlsQA', 'PRODUCT_MODULE_NAME': 'Mac_Companion'})
        controls_entitlements = qa / 'TerminalControlsQA.entitlements'
        controls_entitlements.write_bytes(plistlib.dumps({'application-identifier': 'dev.maccompanion.controlsqa.ios',
            'keychain-access-groups': ['dev.maccompanion.controlsqa.ios']}))
        controls['settings']['base']['CODE_SIGN_ENTITLEMENTS'] = str(controls_entitlements)
        controls['dependencies'] = [row for row in controls['dependencies'] if row.get('target') != 'MacCompanionSessionActivity']
        spec['targets']['TerminalControlsApp'] = controls
        spec['targets']['TerminalControlsJourneyTests'] = {
            'type': 'bundle.ui-testing', 'platform': 'iOS',
            'sources': [{'path': str(ROOT / 'Experiments/TerminalControlsQA/TerminalControlsJourneyTests.swift')},
                        {'path': str(ROOT / 'spec/storekit/v0/LifetimePro.storekit'), 'buildPhase': 'resources'}],
            'dependencies': [{'target': 'TerminalControlsApp'}],
            'settings': {'base': {'GENERATE_INFOPLIST_FILE': 'YES', 'PRODUCT_BUNDLE_IDENTIFIER': 'dev.maccompanion.controlsqa.ios.tests',
                'SWIFT_VERSION': '6.0', 'IPHONEOS_DEPLOYMENT_TARGET': '26.0', 'ARCHS': 'arm64', 'ONLY_ACTIVE_ARCH': 'YES',
                'CODE_SIGN_IDENTITY': '-', 'CODE_SIGNING_ALLOWED': 'YES', 'TEST_TARGET_NAME': 'TerminalControlsApp'}}}
        spec['schemes']['TerminalControlsQA'] = {'build': {'targets': {'TerminalControlsApp': 'all', 'TerminalControlsJourneyTests': 'all'}},
            'test': {'config': 'Debug', 'macroExpansion': 'TerminalControlsApp', 'targets': [{'name': 'TerminalControlsJourneyTests', 'parallelizable': False}],
                     'storeKitConfiguration': str(ROOT / 'spec/storekit/v0/LifetimePro.storekit')}}
        for action in ['run', 'profile', 'analyze', 'archive']:
            spec['schemes']['TerminalControlsQA'][action] = {'config': 'Debug'}
        spec['schemes']['TerminalControlsQA']['run'].update({'executable': 'TerminalControlsApp',
            'macroExpansion': 'TerminalControlsApp', 'storeKitConfiguration': str(ROOT / 'spec/storekit/v0/LifetimePro.storekit')})
    if args.terminal_controls_review:
        if not args.terminal_controls_ui: parser.error('--terminal-controls-review requires --terminal-controls-ui')
        spec['schemes']['TerminalControlsQA']['test']['environmentVariables'] = {'MACCOMPANION_TERMINAL_CONTROLS_REVIEW': '1'}
    if args.terminal_tool_host:
        descriptor = json.loads(args.terminal_tool_host.read_text())
        spec['schemes']['DirectClientQA']['test'].setdefault('environmentVariables', {})['MACCOMPANION_TERMINAL_TOOL_HOST'] = json.dumps(descriptor)
    spec_path = qa / 'project.json'; spec_path.write_text(json.dumps(spec, indent=2))
    run('/opt/homebrew/bin/xcodegen', 'generate', '--spec', spec_path, '--project', qa)
    lock = qa / 'DirectClientQA.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
    lock.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(ROOT / 'Native/Terminal/Package.resolved', lock)
    if args.generate_only:
        print(qa / 'DirectClientQA.xcodeproj')
        return
    import time
    result = evidence / ('Results-' + str(time.time_ns()) + '.xcresult')
    with (evidence / 'test.log').open('w') as log:
        run('xcodebuild', '-project', qa / 'DirectClientQA.xcodeproj', '-scheme', 'LocalBackupE2EQA' if args.local_backup_e2e else 'SavedControlsConsentQA' if args.saved_controls_ui else 'TerminalControlsQA' if args.terminal_controls_ui else 'DirectClientQA',
            '-destination', 'platform=iOS Simulator,id=' + args.simulator, '-derivedDataPath', compiler / 'DerivedData',
            '-onlyUsePackageVersionsFromResolvedFile', '-skipPackagePluginValidation', '-parallel-testing-enabled', 'NO', '-maximum-concurrent-test-simulator-destinations', '1',
            *(['-only-testing:DirectClientTests/DuoComparisonTests/testInteractiveCapture'] if args.duo_review else []),
            *['-only-testing:' + identifier for identifier in args.only_testing],
            '-collect-test-diagnostics', args.test_diagnostics, '-resultBundlePath', result, 'test', stdout=log, stderr=subprocess.STDOUT)
    container = subprocess.check_output(['xcrun', 'simctl', 'get_app_container', args.simulator,
        'dev.maccompanion.backupe2e.ios' if args.local_backup_e2e else 'dev.maccompanion.savedcontrolsqa.ios' if args.saved_controls_ui else 'dev.maccompanion.controlsqa.ios' if args.terminal_controls_ui else bundle, 'data'], text=True).strip()
    if not args.local_backup_e2e and not args.saved_controls_ui and not args.terminal_controls_ui and not args.duo_review and not args.only_testing:
        verify_external(Path(container) / 'Documents/synthetic-key-interop')
    for name in ['synthetic-ed25519', 'synthetic-ed25519.pub', 'synthetic-rsa', 'synthetic-rsa.pub']:
        (qa / name).unlink(missing_ok=True)
    print('Direct client Simulator QA passed. Results:', result)


if __name__ == '__main__':
    main()
