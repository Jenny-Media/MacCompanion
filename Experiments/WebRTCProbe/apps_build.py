#!/usr/bin/env python3
"""Generate disposable native app targets against the admitted WebRTC archive."""
import argparse
import json
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile
from build import inspect_archive


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive',required=True,type=Path)
    parser.add_argument('--with-ui-tests',action='store_true')
    args=parser.parse_args();inspect_archive(args.archive)
    root=Path(tempfile.mkdtemp(prefix='maccompanion-webrtc-apps-',dir='/private/tmp'))
    source=Path(__file__).resolve().parent
    print(root,flush=True)
    subprocess.run(['ditto','-xk',str(args.archive.resolve()),str(root/'sdk')],check=True)
    (root/'Sources').mkdir()
    hashes={}
    names=['MediaPeer.swift','SyntheticFrames.swift','Exchange.swift','CaptureApp.swift','ReceiverApp.swift']
    if args.with_ui_tests: names.append('ReceiverUITests.swift')
    for name in names:
        shutil.copy2(source/name,root/'Sources'/name)
        hashes[name]=hashlib.sha256((source/name).read_bytes()).hexdigest()
    (root/'source-hashes.json').write_text(json.dumps(hashes,indent=2)+'\n')
    shared=[{'path':'Sources/'+name} for name in ['MediaPeer.swift','SyntheticFrames.swift','Exchange.swift']]
    framework={'framework':'sdk/WebRTC.xcframework','embed':True,'codeSign':True}
    targets={}
    for name,platform,file,bundle in [
        ('WebRTCCaptureTest','macOS','CaptureApp.swift','dev.maccompanion.webrtc.capture'),
        ('WebRTCReceiverTest','iOS','ReceiverApp.swift','dev.maccompanion.webrtc.receiver')]:
        info={'CFBundleDisplayName':'WebRTC Capture Test' if platform=='macOS' else 'WebRTC Receiver Test'}
        if platform=='iOS':
            info.update({'UILaunchScreen':{},'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False},'NSLocalNetworkUsageDescription':'Connect to the explicitly prepared local WebRTC test host.',
                'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight']})
        else: info['LSUIElement']=False
        targets[name]={'type':'application','platform':platform,'deploymentTarget':'26.0',
            'sources':shared+[{'path':'Sources/'+file}],'dependencies':[framework],
            'info':{'path':str(root/(name+'-Info.plist')),'properties':info},
            'settings':{'base':{'PRODUCT_BUNDLE_IDENTIFIER':bundle,'PRODUCT_NAME':name,
                'SWIFT_VERSION':'6.0','SWIFT_STRICT_CONCURRENCY':'complete','ENABLE_APP_SANDBOX':'NO',
                'CODE_SIGN_STYLE':'Automatic','GENERATE_INFOPLIST_FILE':'NO','SWIFT_OPTIMIZATION_LEVEL':'-O',
                'TARGETED_DEVICE_FAMILY':'1,2' if platform=='iOS' else '1'}}}
    project={'name':'WebRTCExperiments','options':{'createIntermediateGroups':True},'targets':targets,
             'schemes':{name:{'build':{'targets':{name:'all'}}} for name in targets}}
    if args.with_ui_tests:
        targets['WebRTCReceiverUITests']={'type':'bundle.ui-testing','platform':'iOS','deploymentTarget':'26.0',
            'sources':[{'path':'Sources/ReceiverUITests.swift'}],'dependencies':[{'target':'WebRTCReceiverTest'}],
            'settings':{'base':{'PRODUCT_BUNDLE_IDENTIFIER':'dev.maccompanion.webrtc.receiver.uitests',
                'GENERATE_INFOPLIST_FILE':'YES','SWIFT_VERSION':'5.0','TARGETED_DEVICE_FAMILY':'1,2',
                'TEST_TARGET_NAME':'WebRTCReceiverTest'}}}
        project['schemes']['WebRTCReceiverTest']['test']={'targets':['WebRTCReceiverUITests']}
    (root/'project.json').write_text(json.dumps(project,indent=2)+'\n')
    subprocess.run(['xcodegen','generate','--spec',str(root/'project.json'),'--project',str(root)],check=True,timeout=30)
    print('Project: '+str(root/'WebRTCExperiments.xcodeproj'),flush=True)


if __name__=='__main__':main()
