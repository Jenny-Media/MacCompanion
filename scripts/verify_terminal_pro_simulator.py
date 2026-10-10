#!/usr/bin/env python3
"""Run the direct client QA target plus OpenSSH and sandboxed setup checks.

Requires a completed build_vnc_ios_development.py Simulator output. All test
keys are fresh, temporary and synthetic. The user's ~/.ssh is never modified.
"""
import argparse
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
    args = parser.parse_args(); base = args.build.resolve()
    qa = base / 'QA'; qa.mkdir(exist_ok=True)
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
    resources = [ROOT / 'spec/fixtures/direct-screen-sharing-v1.json', ROOT / 'spec/fixtures/vnc-desktop-tunnel-v0.1.json',
                 ROOT / 'spec/storekit/v0/LifetimePro.storekit', qa / 'synthetic-ed25519', qa / 'synthetic-ed25519.pub', qa / 'synthetic-rsa']
    spec['targets']['DirectClientTests'] = {
        'type': 'bundle.unit-test', 'platform': 'iOS',
        'sources': [{'path': str(ROOT / 'Experiments/NormalVNCViewportQA')}] + [{'path': str(p), 'buildPhase': 'resources'} for p in resources],
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
    shutil.copyfile(ROOT / 'spec/storekit/v0/LifetimePro.storekit', qa / 'LifetimePro.storekit')
    spec['schemes']['DirectClientQA']['run'].update({'executable': 'MacCompanionIOS', 'macroExpansion': 'MacCompanionIOS', 'storeKitConfiguration': 'LifetimePro.storekit'})
    if args.screenshots:
        spec['schemes']['DirectClientQA']['run']['environmentVariables'] = {'MACCOMPANION_SCREENSHOT_REVIEW': '1'}
    if args.duo_review:
        spec['schemes']['DirectClientQA']['run']['environmentVariables'] = {'MACCOMPANION_DUO_REVIEW': '1'}
    spec_path = qa / 'project.json'; spec_path.write_text(json.dumps(spec, indent=2))
    run('/opt/homebrew/bin/xcodegen', 'generate', '--spec', spec_path, '--project', qa)
    lock = qa / 'DirectClientQA.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
    lock.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(ROOT / 'Native/Terminal/Package.resolved', lock)
    shutil.rmtree(qa / 'Results.xcresult', ignore_errors=True)
    with (qa / 'test.log').open('w') as log:
        run('xcodebuild', '-project', qa / 'DirectClientQA.xcodeproj', '-scheme', 'DirectClientQA',
            '-destination', 'platform=iOS Simulator,id=' + args.simulator, '-derivedDataPath', base / 'DerivedData',
            '-onlyUsePackageVersionsFromResolvedFile', '-skipPackagePluginValidation', '-parallel-testing-enabled', 'NO',
            *(['-only-testing:DirectClientTests/DuoComparisonTests/testInteractiveCapture'] if args.duo_review else []),
            '-collect-test-diagnostics', args.test_diagnostics, '-resultBundlePath', qa / 'Results.xcresult', 'test', stdout=log, stderr=subprocess.STDOUT)
    container = subprocess.check_output(['xcrun', 'simctl', 'get_app_container', args.simulator, bundle, 'data'], text=True).strip()
    if not args.duo_review:
        verify_external(Path(container) / 'Documents/synthetic-key-interop')
    for name in ['synthetic-ed25519', 'synthetic-ed25519.pub', 'synthetic-rsa', 'synthetic-rsa.pub']:
        (qa / name).unlink(missing_ok=True)
    print('Direct client Simulator QA passed. Results:', qa / 'Results.xcresult')


if __name__ == '__main__':
    main()
