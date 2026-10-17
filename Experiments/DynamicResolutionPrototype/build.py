#!/usr/bin/env python3
"""Managed isolated iOS experiment, using an admitted normal build's dependencies."""
import argparse, copy, hashlib, json, pathlib, plistlib, subprocess, sys
HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from build_cache import BuildSession, compiler_workspace, toolchain_identity, write_if_changed
from prepare_runtime import prepare

def run(*args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, **kwargs)

def main():
    p=argparse.ArgumentParser();p.add_argument('--base',type=pathlib.Path,required=True);p.add_argument('--output',type=pathlib.Path,required=True);p.add_argument('--sdk',choices=['iphonesimulator','iphoneos'],required=True)
    a=p.parse_args();base=a.base.resolve();report=json.loads((base/'build-report.json').read_text())
    if report['sdk'] != a.sdk: p.error('Base SDK does not match prototype SDK')
    sha=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
    def prototype_inputs():
        return {str(x.relative_to(ROOT)):sha(x) for x in HERE.rglob('*') if x.is_file() and '__pycache__' not in str(x)}
    inputs=prototype_inputs()
    for name,digest in report['inputs'].items():
        if sha(ROOT/name)!=digest: p.error('Base source fingerprint changed: '+name)
    identity={'kind':'dynamic-resolution-prototype','sdk':a.sdk,'arch':'arm64','toolchain':toolchain_identity((a.sdk,))}
    with compiler_workspace(base,ROOT), BuildSession(ROOT,a.output,identity) as build:
        out=build.workspace;prepare(out/'Runtime')
        spec=json.loads((base/'project.json').read_text());target=copy.deepcopy(spec['targets']['MacCompanionIOS']);sources=[]
        for row in target['sources']:
            path=pathlib.Path(row['path']);path=path if path.is_absolute() else base/path
            if path==ROOT/'Native/VNC':
                for source in sorted(path.iterdir()):
                    if source.name in ['CompanionVNCTransport.h','CompanionVNCTransport.m'] or source.suffix not in ['.swift','.m','.h']: continue
                    if source.name in ['CompanionVNCSession.m','VNCRemoteDesktopView.swift']: source=out/'Runtime'/source.name
                    sources.append({'path':str(source)})
            else:
                sources.append({**row,'path':str(path)})
        sources += [{'path':str(HERE/n)} for n in ['PrototypeViewer.h','PrototypeViewer.m','BenchmarkJournal.h','BenchmarkJournal.m','DynamicDisplay.h']]
        target['sources']=sources
        target['dependencies']=[d for d in target['dependencies'] if d.get('target')!='MacCompanionSessionActivity']
        settings=target['settings']['base'];bundle='dev.maccompanion.resolutionlab'
        settings.update({'PRODUCT_BUNDLE_IDENTIFIER':bundle,'PRODUCT_NAME':'Screen Resolution Lab','PRODUCT_MODULE_NAME':'Mac_Companion','SWIFT_OBJC_BRIDGING_HEADER':str(out/'Runtime/Prototype-Bridging-Header.h'),'CODE_SIGNING_ALLOWED':'YES' if a.sdk=='iphonesimulator' else 'NO','CODE_SIGN_IDENTITY':'-'})
        settings['HEADER_SEARCH_PATHS']=[str(ROOT/'Native/VNC'),str(HERE)]+settings['HEADER_SEARCH_PATHS']
        info=plistlib.loads(pathlib.Path(settings['INFOPLIST_FILE']).read_bytes());info.update({'CFBundleName':'Screen Resolution Lab','CFBundleDisplayName':'Screen Resolution Lab','CFBundleURLTypes':[{'CFBundleURLSchemes':['maccompanion-resolution-lab']}]});info.pop('NSSupportsLiveActivities',None)
        write_if_changed(out/'Prototype-Info.plist',plistlib.dumps(info));settings['INFOPLIST_FILE']=str(out/'Prototype-Info.plist')
        entitlements=out/'Prototype.entitlements';write_if_changed(entitlements,plistlib.dumps({'application-identifier':bundle,'keychain-access-groups':[bundle]}));settings['CODE_SIGN_ENTITLEMENTS']=str(entitlements)
        spec['name']='DynamicResolutionPrototype';spec['targets']={'MacCompanionIOS':target};spec['schemes']={'ResolutionPrototype':{'build':{'targets':{'MacCompanionIOS':'all'}},'run':{'config':'Debug'}}}
        if a.sdk=='iphonesimulator':
            spec['targets']['ResolutionTests']={'type':'bundle.unit-test','platform':'iOS','sources':[{'path':str(HERE/'Tests')},{'path':str(ROOT/'spec/fixtures/ios-dynamic-resolution-prototype-v1.json'),'buildPhase':'resources'}],'dependencies':[{'target':'MacCompanionIOS'}],'settings':{'base':{'GENERATE_INFOPLIST_FILE':'YES','PRODUCT_BUNDLE_IDENTIFIER':bundle+'.tests','IPHONEOS_DEPLOYMENT_TARGET':'26.0','ARCHS':'arm64','ONLY_ACTIVE_ARCH':'YES','CODE_SIGNING_ALLOWED':'YES','CODE_SIGN_IDENTITY':'-','CLANG_ENABLE_OBJC_ARC':'YES','HEADER_SEARCH_PATHS':settings['HEADER_SEARCH_PATHS'],'TEST_HOST':'$(BUILT_PRODUCTS_DIR)/Screen Resolution Lab.app/Screen Resolution Lab','BUNDLE_LOADER':'$(TEST_HOST)'}}}
            spec['schemes']['ResolutionPrototype']['build']['targets']['ResolutionTests']='all'
            spec['schemes']['ResolutionPrototype']['test']={'config':'Debug','targets':[{'name':'ResolutionTests','parallelizable':False}]}
        for action in ['run','test','profile','analyze','archive']:
            spec['schemes']['ResolutionPrototype'].setdefault(action,{})['config']='Debug'
        write_if_changed(out/'project.json',json.dumps(spec,indent=2))
        run('/opt/homebrew/bin/xcodegen','generate','--spec',out/'project.json','--project',out)
        package_lock=out/'DynamicResolutionPrototype.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
        write_if_changed(package_lock,(ROOT/'Native/Terminal/Package.resolved').read_bytes())
        with (out/'resolve.log').open('w') as stream:
            run('xcodebuild','-project',out/'DynamicResolutionPrototype.xcodeproj','-scheme','ResolutionPrototype','-derivedDataPath',out/'DerivedData','-clonedSourcePackagesDirPath',out/'SourcePackages','-onlyUsePackageVersionsFromResolvedFile','-resolvePackageDependencies',stdout=stream,stderr=subprocess.STDOUT)
        # Match the normal builder's Xcode 27 workaround: the pinned generator
        # must be a host executable in Debug, not an iOS executable.
        from dependency_checkout_provenance import verify_source_checkout
        tool_source=out/'SourcePackages/checkouts/SwiftTerm'
        verify_source_checkout(tool_source,json.loads((ROOT/'Native/Terminal/source-lock.json').read_text())['SwiftTerm']['revision'])
        tool=out/'DerivedData/Build/Products/Debug/SwiftTermBuildInfoGenerator';tool.parent.mkdir(parents=True,exist_ok=True)
        run('xcrun','--sdk','macosx','swiftc','-parse-as-library',tool_source/'Sources/SwiftTermBuildInfoGenerator/BuildInfoGenerator.swift','-o',tool)
        log=out/'build.log'
        with log.open('w') as stream:
            run('xcodebuild','-project',out/'DynamicResolutionPrototype.xcodeproj','-scheme','ResolutionPrototype','-configuration','Debug','-sdk',a.sdk,'-destination','generic/platform=iOS Simulator' if a.sdk=='iphonesimulator' else 'generic/platform=iOS','-derivedDataPath',out/'DerivedData','-clonedSourcePackagesDirPath',out/'SourcePackages','-onlyUsePackageVersionsFromResolvedFile','-skipPackagePluginValidation','ARCHS=arm64','ONLY_ACTIVE_ARCH=YES','build',stdout=stream,stderr=subprocess.STDOUT)
        app=out/'DerivedData/Build/Products'/('Debug-iphonesimulator' if a.sdk=='iphonesimulator' else 'Debug-iphoneos')/'Screen Resolution Lab.app'
        if inputs!=prototype_inputs(): raise RuntimeError('Prototype sources changed during build; rebuild final sources')
        if any(sha(ROOT/name)!=digest for name,digest in report['inputs'].items()): raise RuntimeError('Normal sources changed during prototype build')
        if json.loads(package_lock.read_text())['pins']!=json.loads((ROOT/'Native/Terminal/Package.resolved').read_text())['pins']: raise RuntimeError('Dependency pins changed during prototype build')
        profile={'profile':'maccompanion.dynamic-resolution-prototype.v1','sdk':a.sdk,'releaseAdmitted':False,'app':str(app),'baseBuild':str(base),'inputs':inputs,'normalSourcesUnmodified':True}
        build.publish(profile,app)
        print('Prototype:',a.output/'build-report.json')

if __name__=='__main__':main()
