#!/usr/bin/env python3
import argparse,json,pathlib,subprocess,sys,time
HERE=pathlib.Path(__file__).resolve().parent;ROOT=HERE.parents[1];sys.path.insert(0,str(ROOT/'scripts'))
from build_cache import compiler_workspace

def main():
    p=argparse.ArgumentParser();p.add_argument('--build',type=pathlib.Path,required=True);p.add_argument('--simulator',required=True);a=p.parse_args()
    build=a.build.resolve();results=build/'Tests'/str(time.time_ns());results.mkdir(parents=True)
    with compiler_workspace(build,ROOT) as cache:
        command=['xcodebuild','-project',str(cache/'DynamicResolutionPrototype.xcodeproj'),'-scheme','ResolutionPrototype','-destination','platform=iOS Simulator,id='+a.simulator,'-derivedDataPath',str(cache/'DerivedData'),'-clonedSourcePackagesDirPath',str(cache/'SourcePackages'),'-onlyUsePackageVersionsFromResolvedFile','-skipPackagePluginValidation','-parallel-testing-enabled','NO','-collect-test-diagnostics','never','-resultBundlePath',str(results/'Results.xcresult'),'ARCHS=arm64','ONLY_ACTIVE_ARCH=YES','test']
        with (results/'test.log').open('w') as log: result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT)
    passed=result.returncode==0 and '** TEST SUCCEEDED **' in (results/'test.log').read_text()
    report={'schema':1,'passed':passed,'exitCode':result.returncode,'resultBundle':str(results/'Results.xcresult'),'log':str(results/'test.log'),'physicalServerAcceptance':False}
    (build/'test-report.json').write_text(json.dumps(report,indent=2));print(json.dumps(report));sys.exit(0 if passed else 1)
if __name__=='__main__':main()
