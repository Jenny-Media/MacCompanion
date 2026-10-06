#!/usr/bin/env python3
"""Prepare an optimized normal-client archive for internal TestFlight.

Requires a completed device development build and its exact source/dependency
evidence. Apple account signing/upload is a separate authorized action. This
does not admit the development dependency graph for external/public release.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def run(*args, **kwargs):
    subprocess.run([str(x) for x in args], check=True, **kwargs)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--build', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--build-number', type=int, required=True)
    parser.add_argument('--distribution-team')
    parser.add_argument('--distribution-certificate', help='Existing Apple Distribution certificate SHA-1')
    parser.add_argument('--app-profile', type=Path)
    parser.add_argument('--widget-profile', type=Path)
    args = parser.parse_args()
    base, output = args.build.resolve(strict=True), args.output.resolve()
    if output.is_relative_to(ROOT) or output.exists() or args.build_number < 1:
        raise SystemExit('Use a fresh output directory outside the checkout and a positive build number.')
    report = json.loads((base / 'build-report.json').read_text())
    if report['sdk'] != 'iphoneos' or not report['normalSourceRoot'] or report['releaseAdmitted']:
        raise SystemExit('Expected the normal device development build report.')
    for relative, sha in report['inputs'].items():
        if digest(ROOT / relative) != sha:
            raise SystemExit('Application source changed: ' + relative)
    if digest(base / 'libvncclient/libvncclient.a') != report['libVNCClientSHA256']:
        raise SystemExit('Native library changed.')
    spec = json.loads((base / 'project.json').read_text())
    signing = (args.distribution_team, args.distribution_certificate, args.app_profile, args.widget_profile)
    if any(signing) and not all(signing):
        raise SystemExit('Distribution signing requires the team, certificate and both installed App Store profiles.')
    profiles = {}
    if all(signing):
        for name, path in (('MacCompanionIOS', args.app_profile), ('MacCompanionSessionActivity', args.widget_profile)):
            profile = plistlib.loads(subprocess.check_output(['security', 'cms', '-D', '-i', str(path)]))
            bundle = spec['targets'][name]['settings']['base']['PRODUCT_BUNDLE_IDENTIFIER']
            entitlement = profile['Entitlements']
            certificate_matches = any(hashlib.sha1(cert).hexdigest().upper() == args.distribution_certificate.upper()
                                      for cert in profile['DeveloperCertificates'])
            if (profile['TeamIdentifier'] != [args.distribution_team]
                    or entitlement['application-identifier'] != args.distribution_team + '.' + bundle
                    or entitlement.get('get-task-allow', True) or not entitlement.get('beta-reports-active')
                    or profile.get('ProvisionedDevices') or profile.get('ProvisionsAllDevices')
                    or not certificate_matches):
                raise SystemExit('Expected an exact matching App Store distribution profile: ' + name)
            profiles[name] = profile['UUID']
    spec['name'] = 'InternalTestFlight'
    spec['configs'] = {'InternalTesting': 'release'}
    spec['options']['defaultConfig'] = 'InternalTesting'
    for target in spec['targets'].values():
        for source in target['sources']:
            path = Path(source['path'])
            if not path.is_absolute():
                source['path'] = str(base / path)
            if 'Experiments' in Path(source['path']).parts:
                raise SystemExit('Experimental sources cannot enter the archive.')
        settings = target['settings']['base']
        settings.update({'MARKETING_VERSION': args.version, 'CURRENT_PROJECT_VERSION': str(args.build_number),
                         'CODE_SIGNING_ALLOWED': 'NO', 'DEBUG_INFORMATION_FORMAT': 'dwarf-with-dsym',
                         'SWIFT_OPTIMIZATION_LEVEL': '-O', 'SWIFT_COMPILATION_MODE': 'wholemodule'})
    for name, uuid in profiles.items():
        spec['targets'][name]['settings']['base'].update({
            'DEVELOPMENT_TEAM': args.distribution_team, 'CODE_SIGN_STYLE': 'Manual',
            'CODE_SIGNING_ALLOWED': 'YES', 'CODE_SIGN_IDENTITY': args.distribution_certificate,
            'PROVISIONING_PROFILE_SPECIFIER': uuid,
            'CODE_SIGN_ENTITLEMENTS': str(output / (name + '.entitlements'))})
    app = spec['targets']['MacCompanionIOS']
    if app['settings']['base']['PRODUCT_BUNDLE_IDENTIFIER'] != 'media.jenny.maccompanion.ios':
        raise SystemExit('Unexpected containing app identity.')
    # The existing composition selector is required to use the normal direct
    # client; DEBUG is excluded from this optimized internal archive.
    app['settings']['base']['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'MACCOMPANION_VNC_DEVELOPMENT'
    app['settings']['base']['SKIP_INSTALL'] = 'NO'
    for action in spec['schemes']['MacCompanionIOS'].values():
        if isinstance(action, dict) and 'config' in action:
            action['config'] = 'InternalTesting'
    output.mkdir(parents=True)
    for name in profiles:
        bundle = spec['targets'][name]['settings']['base']['PRODUCT_BUNDLE_IDENTIFIER']
        (output / (name + '.entitlements')).write_bytes(plistlib.dumps({
            'keychain-access-groups': [args.distribution_team + '.' + bundle]}))
    (output / 'project.json').write_text(json.dumps(spec, indent=2))
    run('/opt/homebrew/bin/xcodegen', 'generate', '--spec', output / 'project.json', '--project', output)
    project = output / 'InternalTestFlight.xcodeproj'
    lock = project / 'project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
    lock.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / 'Native/Terminal/Package.resolved', lock)
    archive = output / 'Mac Companion.xcarchive'
    with (output / 'archive.log').open('w') as log:
        run('xcodebuild', '-project', project, '-scheme', 'MacCompanionIOS', '-configuration', 'InternalTesting',
            '-destination', 'generic/platform=iOS', '-derivedDataPath', base / 'DerivedData',
            '-onlyUsePackageVersionsFromResolvedFile', '-skipPackagePluginValidation',
            '-archivePath', archive, 'archive', stdout=log, stderr=subprocess.STDOUT)
    for relative, sha in report['inputs'].items():
        if digest(ROOT / relative) != sha:
            raise SystemExit('Sources changed during archive.')
    application = archive / 'Products/Applications/Mac Companion.app'
    if profiles:
        run('codesign', '--verify', '--deep', '--strict', application)
        for bundle in (application, application / 'PlugIns/MacCompanionSessionActivity.appex'):
            info = plistlib.loads((bundle / 'Info.plist').read_bytes())
            expected = args.distribution_team + '.' + info['CFBundleIdentifier']
            entitlement = plistlib.loads(subprocess.check_output(
                ['codesign', '-d', '--entitlements', ':-', str(bundle)], stderr=subprocess.DEVNULL))
            if (entitlement.get('application-identifier') != expected
                    or entitlement.get('com.apple.developer.team-identifier') != args.distribution_team
                    or entitlement.get('keychain-access-groups') != [expected]
                    or entitlement.get('get-task-allow', True)):
                raise SystemExit('Unexpected distribution entitlements: ' + bundle.name)
    (output / 'archive-report.json').write_text(json.dumps({
        'profile': 'maccompanion.direct-client-internal-testflight-archive.v1',
        'internalTestingOnly': True, 'releaseAdmitted': False, 'signed': bool(profiles), 'uploaded': False,
        'distributionProfileUUIDs': profiles,
        'archive': str(archive), 'version': args.version, 'build': args.build_number,
        'sourceBuildReportSHA256': digest(base / 'build-report.json'), 'inputs': report['inputs'],
        'normalApplicationBinarySHA256': digest(application / 'Mac Companion')
    }, indent=2))
    print('Internal TestFlight archive prepared:', archive)


if __name__ == '__main__':
    main()
