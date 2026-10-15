#!/usr/bin/env python3
"""Build the disposable Mac workspace prototype using managed native caches.

Requires an up-to-date normal macOS build report. Neither that target nor its
generated project is edited. All artifacts and compiler work stay outside Git.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
EXPERIMENT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'scripts'))
from build_cache import BuildSession, compiler_workspace, toolchain_identity, write_if_changed
from dependency_checkout_provenance import verify_checkouts


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inputs():
    files = [p for p in sorted(EXPERIMENT.rglob('*')) if p.is_file() and '__pycache__' not in p.parts]
    files += [ROOT / 'spec/fixtures/native-macos-client-v1.json', ROOT / 'spec/fixtures/manifest.json',
              ROOT / 'scripts/build_cache.py', ROOT / 'scripts/dependency_checkout_provenance.py']
    return {str(p.relative_to(ROOT)): sha(p) for p in files}


def verify_inputs(expected):
    for relative, digest in expected.items():
        if sha(ROOT / relative) != digest:
            raise RuntimeError('Source snapshot changed: ' + relative + '. Rebuild against a stable snapshot.')


def run(*command, log):
    with log.open('w') as output:
        subprocess.run([str(x) for x in command], check=True, stdout=output, stderr=subprocess.STDOUT)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--normal-build', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--cache-root', type=Path)
    parser.add_argument('--signing-identity', help='Existing authorized Apple Development certificate SHA-1')
    parser.add_argument('--team', help='Team already authorized by the installed profile')
    parser.add_argument('--profile', type=Path, help='Existing installed Mac development profile permitting the temporary bundle')
    args = parser.parse_args()
    if any([args.signing_identity, args.team, args.profile]) and not all([args.signing_identity, args.team, args.profile]):
        parser.error('Supply --signing-identity, --team and --profile together; no profiles are created or downloaded.')
    identity = {'kind': 'macos-workspace-prototype', 'sdk': 'macosx', 'arch': 'arm64',
                'signing': 'existing-development' if args.signing_identity else 'ad-hoc-experiment',
                'toolchain': toolchain_identity(('macosx',))}
    with compiler_workspace(args.normal_build, ROOT) as normal, BuildSession(ROOT, args.output, identity, cache_root=args.cache_root) as session:
        baseline = json.loads((args.normal_build / 'build-report.json').read_text())
        if baseline['kind'] != 'native-macos-direct-client-build' or baseline['arch'] != 'arm64':
            raise RuntimeError('Use an admitted arm64 native macOS build.')
        original = baseline['sourceInputs']
        before = inputs()
        verify_inputs(original)
        work = session.workspace
        spec = json.loads((normal / 'project.json').read_text())
        if any('Experiments/' in entry['path'] for entry in spec['targets']['MacCompanion']['sources']):
            raise RuntimeError('The shipping target must not link experiments.')
        spec['name'] = 'MacWorkspacePrototype'
        target = spec['targets']['MacCompanion']
        native_mac = next(item for item in target['sources'] if item['path'] == str(ROOT / 'Native/Mac'))
        native_mac['excludes'] = ['MacCompanionDirectApplication.swift']
        target['sources'].append({'path': str(EXPERIMENT / 'Sources')})
        settings = target['settings']['base']
        for key in ['DEVELOPMENT_TEAM', 'CODE_SIGN_ENTITLEMENTS', 'PROVISIONING_PROFILE_SPECIFIER', 'PROVISIONING_PROFILE']:
            settings.pop(key, None)
        settings.update(PRODUCT_BUNDLE_IDENTIFIER='dev.maccompanion.workspaceprototype',
                        PRODUCT_NAME='Mac Workspace Prototype', PRODUCT_MODULE_NAME='MacWorkspacePrototype',
                        CODE_SIGNING_ALLOWED='YES', CODE_SIGN_IDENTITY='-', CODE_SIGN_STYLE='Manual',
                        SWIFT_OBJC_BRIDGING_HEADER=str(EXPERIMENT / 'Workspace-Bridging-Header.h'),
                        INFOPLIST_FILE=str(work / 'Info.plist'))
        metadata = plistlib.loads((normal / 'Info.plist').read_bytes())
        metadata.pop('MacCompanionSharedKeychainGroup', None)
        metadata.update(CFBundleName='Mac Workspace Prototype', CFBundleDisplayName='Mac Workspace Prototype')
        write_if_changed(work / 'Info.plist', plistlib.dumps(metadata))
        signing = None
        if args.signing_identity:
            from direct_mac_development_signing import configure
            signing = configure(settings, identity=args.signing_identity, team=args.team,
                                profile_path=args.profile, output=work,
                                bundle='dev.maccompanion.workspaceprototype')
        write_if_changed(work / 'project.json', json.dumps(spec, indent=2) + '\n')

        # Compile the actual coordinator, not a copy of its logic. The fixture
        # remains in the single authoritative specification manifest.
        tests = work / 'workspace-tests'
        run('xcrun', '--sdk', 'macosx', 'swiftc', '-swift-version', '6', '-parse-as-library',
            '-target', 'arm64-apple-macosx26.0', '-module-cache-path', work / 'TestModuleCache',
            '-import-objc-header', ROOT / 'Native/VNC/CompanionVNCDirectEndpoint.h',
            EXPERIMENT / 'Sources/WorkspaceCoordinator.swift', EXPERIMENT / 'Tests/WorkspaceTests.swift',
            '-o', tests, log=work / 'tests-build.log')
        run(tests, ROOT / 'spec/fixtures/native-macos-client-v1.json', log=work / 'tests.log')
        result = (work / 'tests.log').read_text()
        checks = re.search(r'^PASS: (\d+) workspace endpoint and lifecycle checks', result, re.MULTILINE)
        if not checks:
            raise RuntimeError('Workspace test runner did not confirm success.')

        run('/opt/homebrew/bin/xcodegen', 'generate', '--use-cache', '--cache-path', work / '.xcodegen-cache',
            '--spec', work / 'project.json', log=work / 'generate.log')
        project = work / 'MacWorkspacePrototype.xcodeproj'
        package_lock = project / 'project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
        write_if_changed(package_lock, (ROOT / 'Native/Terminal/Package.resolved').read_bytes())
        pins = json.loads(package_lock.read_text())['pins']
        packages = normal / 'DerivedData/SourcePackages'
        provenance = verify_checkouts(packages, pins)
        common = ['xcodebuild', '-project', project, '-scheme', 'MacCompanion',
                  '-derivedDataPath', work / 'DerivedData', '-clonedSourcePackagesDirPath', packages,
                  '-onlyUsePackageVersionsFromResolvedFile', '-skipPackageUpdates']
        run(*common, '-resolvePackageDependencies', log=work / 'resolve.log')
        # Preserve the original pinned generator and stable macOS host-tool path.
        generator = work / 'DerivedData/Build/Products/Debug/SwiftTermBuildInfoGenerator'
        generator.parent.mkdir(parents=True, exist_ok=True)
        run('xcrun', '--sdk', 'macosx', 'swiftc', '-parse-as-library',
            packages / 'checkouts/SwiftTerm/Sources/SwiftTermBuildInfoGenerator/BuildInfoGenerator.swift',
            '-o', generator, log=work / 'generator.log')
        run(*common, '-configuration', 'Debug', '-destination', 'generic/platform=macOS',
            '-skipPackagePluginValidation', 'build', log=work / 'build.log')
        if json.loads(package_lock.read_text())['pins'] != pins:
            raise RuntimeError('Pinned package revisions changed.')
        after_provenance = verify_checkouts(packages, pins, previous=provenance)
        verify_inputs(original)
        if before != inputs():
            raise RuntimeError('Experiment changed during validation. Rerun against a stable snapshot.')
        app = work / 'DerivedData/Build/Products/Debug/Mac Workspace Prototype.app'
        run('codesign', '--verify', '--deep', '--strict', app, log=work / 'signature.log')
        if signing:
            from direct_mac_development_signing import verify
            verify(app, signing, work)
        report = {'schema': 1, 'kind': 'macos-workspace-prototype-build', 'experiment': True,
                  'shippingTargetChanged': False, 'releaseReadiness': False, 'logicChecks': int(checks[1]),
                  'sourceRevision': subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip(),
                  'sourceInputs': original | before, 'baselineEvidence': str(args.normal_build.resolve()),
                  'packageSources': {'before': provenance, 'after': after_provenance},
                  'developmentSigning': signing or 'ad-hoc-experiment', 'liveDesktopAndSSHAcceptance': False}
        report = session.publish(report, app)
        print(report['app'])


if __name__ == '__main__':
    main()
