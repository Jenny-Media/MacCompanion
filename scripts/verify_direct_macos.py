#!/usr/bin/env python3
"""Run hosted native Mac client checks against a completed direct-client build.

Default checks use synthetic loopback SSH, temporary files, test Keychain entries
and owned AppKit windows. Opt-in --live-vm checks use an explicitly supplied
disposable fixture with built-in Screen Sharing and Remote Login. Neither lane
certifies signed iCloud delivery. Output remains outside the repository.
"""
import argparse
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', type=Path, required=True)
    parser.add_argument('--signing-identity', help='Existing local Mac signing identity for data protection Keychain QA')
    parser.add_argument('--team', help='Existing team for the signing identity; no new permanent identity is created')
    parser.add_argument('--profile', type=Path, help='Existing installed Mac development provisioning profile')
    parser.add_argument('--ui', action='store_true', help='Also launch the native app for window and keyboard UI acceptance')
    parser.add_argument('--only-ui', action='store_true', help='Run only native UI acceptance, including its macOS automation permission prompt')
    parser.add_argument('--live-vm', action='store_true', help='Run only opt-in disposable VM GUI acceptance and screenshot attachments; requires MC_LIVE_VM_HOST/ACCOUNT/PASSWORD/FINGERPRINT')
    args = parser.parse_args()
    if args.live_vm:
        args.only_ui = True
        required = ['MC_LIVE_VM_HOST', 'MC_LIVE_VM_ACCOUNT', 'MC_LIVE_VM_PASSWORD', 'MC_LIVE_VM_FINGERPRINT']
        if not all(os.environ.get(key) for key in required):
            parser.error('Live VM acceptance requires all four explicit fixture environment values.')
    if args.only_ui:
        args.ui = True
    base = args.build.resolve()
    qa = base / 'QA'
    qa.mkdir(exist_ok=True)
    # All test invocations mutate this generated project and its build products.
    # Keep the descriptor open until this invocation ends; stale lock files do
    # not block a later run because the kernel owns the actual lock lifetime.
    run_lock = (qa / 'verification.lock').open('a+')
    try:
        fcntl.flock(run_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        parser.error('Another native Mac QA invocation is running for this build. Wait for its process to finish.')
    spec = json.loads((base / 'project.json').read_text())
    spec['name'] = 'NativeMacClientQA'
    # Xcode writes user scheme metadata into local packages when opening a
    # project. Keep that generated material outside the hash-pinned vendor tree.
    from verify_direct_client_dependencies import validate
    validate()
    qa_citadel = qa / 'Dependencies/Citadel'
    shutil.copytree(ROOT / 'Native/Dependencies/Citadel', qa_citadel, dirs_exist_ok=True)
    spec['packages']['Citadel'] = {'path': str(qa_citadel)}
    app = spec['targets']['MacCompanion']
    settings = app['settings']['base']
    settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'dev.maccompanion.macqa'
    settings['PRODUCT_MODULE_NAME'] = 'MacCompanion'
    settings['CODE_SIGNING_ALLOWED'] = 'YES'
    settings['CODE_SIGN_IDENTITY'] = '-'
    admission = None
    if args.signing_identity:
        if not args.team or not args.profile:
            parser.error('--team and --profile are required with --signing-identity')
        from direct_mac_development_signing import configure
        admission = configure(settings, identity=args.signing_identity, team=args.team, profile_path=args.profile,
                              output=qa, bundle='dev.maccompanion.macqa')
    spec['targets']['NativeClientTests'] = {
        'type': 'bundle.unit-test', 'platform': 'macOS',
        'sources': [{'path': str(ROOT / 'Native/MacTests/Hosted')}],
        'dependencies': [{'target': 'MacCompanion'}],
        'settings': {'base': {
            'GENERATE_INFOPLIST_FILE': 'YES', 'PRODUCT_BUNDLE_IDENTIFIER': 'dev.maccompanion.macqa.tests',
            'SWIFT_VERSION': '6.0', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG MACCOMPANION_VNC_DEVELOPMENT',
            'MACOSX_DEPLOYMENT_TARGET': '26.0', 'ARCHS': settings['ARCHS'], 'ONLY_ACTIVE_ARCH': 'YES',
            'CODE_SIGNING_ALLOWED': 'YES', 'CODE_SIGN_IDENTITY': '-',
            'HEADER_SEARCH_PATHS': settings['HEADER_SEARCH_PATHS'],
            'CLANG_ENABLE_OBJC_ARC': 'YES',
            'TEST_HOST': '$(BUILT_PRODUCTS_DIR)/MacCompanion.app/Contents/MacOS/MacCompanion', 'BUNDLE_LOADER': '$(TEST_HOST)'}}}
    spec['schemes'] = {'NativeMacClientQA': {
        'build': {'targets': {'MacCompanion': 'all', 'NativeClientTests': 'all'}},
        'test': {'config': 'Debug', 'macroExpansion': 'MacCompanion',
                 'environmentVariables': {'MACCOMPANION_DIRECT_DATA_DIRECTORY': str(qa / 'app-data'),
                                          'MACCOMPANION_NATIVE_FIXTURE_DIRECTORY': str(ROOT / 'spec/fixtures')},
                 'targets': [{'name': 'NativeClientTests', 'parallelizable': False}]}}}
    if args.ui:
        # The UI runner is sandboxed by Xcode. Its synthetic SSH fixture binds
        # only loopback, but still needs the incoming-network entitlement.
        # This permission belongs to the temporary test runner, not the client.
        import plistlib
        ui_entitlements = qa / 'NativeWindowUI.entitlements'
        ui_entitlements.write_bytes(plistlib.dumps({'com.apple.security.network.server': True}))
        spec['targets']['NativeWindowUITests'] = {
            'type': 'bundle.ui-testing', 'platform': 'macOS',
            'sources': [{'path': str(ROOT / 'Native/MacTests/UI')},
                        {'path': str(ROOT / 'Native/MacTests/Hosted/SSHTestServer.swift')}],
            'dependencies': [{'target': 'MacCompanion'}, {'package': 'Citadel'}],
            'settings': {'base': {
                'GENERATE_INFOPLIST_FILE': 'YES', 'PRODUCT_BUNDLE_IDENTIFIER': 'dev.maccompanion.macqa.ui',
                'SWIFT_VERSION': '6.0', 'MACOSX_DEPLOYMENT_TARGET': '26.0',
                'ARCHS': settings['ARCHS'], 'ONLY_ACTIVE_ARCH': 'YES',
                'CODE_SIGNING_ALLOWED': 'YES', 'CODE_SIGN_IDENTITY': '-', 'TEST_TARGET_NAME': 'MacCompanion',
                'CODE_SIGN_ENTITLEMENTS': str(ui_entitlements)}}}
        spec['schemes']['NativeMacClientQA']['build']['targets']['NativeWindowUITests'] = 'all'
        spec['schemes']['NativeMacClientQA']['test']['targets'].append({'name': 'NativeWindowUITests', 'parallelizable': False})
        if args.live_vm:
            spec['schemes']['NativeMacClientQA']['test']['environmentVariables'].update({key: os.environ[key] for key in required})
    project = qa / 'project.json'; project.write_text(json.dumps(spec, indent=2) + '\n')
    subprocess.run(['/opt/homebrew/bin/xcodegen', 'generate', '--spec', str(project)], check=True)
    project_path = qa / 'NativeMacClientQA.xcodeproj'
    lock = project_path / 'project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
    lock.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / 'Native/Terminal/Package.resolved', lock)
    # A fresh result directory preserves previous runs as reviewable evidence.
    import time
    result = qa / ('Results-' + str(time.time_ns()) + '.xcresult')
    with (qa / 'test.log').open('w') as log:
        command = ['xcodebuild', '-project', str(project_path), '-scheme', 'NativeMacClientQA',
            '-destination', 'platform=macOS', '-derivedDataPath', str(qa / 'DerivedData'),
            '-clonedSourcePackagesDirPath', str(base / 'DerivedData/SourcePackages'),
            '-onlyUsePackageVersionsFromResolvedFile', '-skipPackagePluginValidation',
            '-parallel-testing-enabled', 'NO', '-resultBundlePath', str(result)]
        if args.live_vm:
            command.append('-only-testing:NativeWindowUITests/LiveVMUITests')
        elif args.only_ui:
            command.append('-only-testing:NativeWindowUITests')
        if args.ui:
            command += ['-test-timeouts-enabled', 'YES', '-default-test-execution-time-allowance', '180',
                        '-maximum-test-execution-time-allowance', '180']
        subprocess.run(command + ['test'],
            stdout=log, stderr=subprocess.STDOUT, check=True)
    if admission:
        from direct_mac_development_signing import verify
        verify(qa / 'DerivedData/Build/Products/Debug/MacCompanion.app', admission, qa)
    print('Native Mac hosted QA completed (inspect skipped acceptance checks):', result)


if __name__ == '__main__':
    main()
