#!/usr/bin/env python3
"""Run the legacy feature/pairing checks under the existing compiler lease."""
import hashlib
import codecs
from contextlib import ExitStack
import json
import os
from pathlib import Path
import platform
import re
import select
import shutil
import signal
import subprocess
import sys
import time

from build_cache import BuildSession, DEFAULT_EVIDENCE, ROOT, capture, file_manifest, safe_directory, toolchain_identity

CALLERS = {
    'simulator-features': ('bash', 'verify_simulator_features.sh'),
    'pairing-reliability': ('zsh', 'verify_pairing_reliability.sh'),
}


def build_identity(caller, arguments):
    if caller not in CALLERS or (arguments and (caller != 'pairing-reliability' or arguments != ['--signed-builds'])):
        raise ValueError('Expected simulator-features, or pairing-reliability [--signed-builds].')
    signed = arguments == ['--signed-builds']
    if signed and not os.environ.get('MACCOMPANION_DEVELOPMENT_TEAM'):
        raise ValueError('MACCOMPANION_DEVELOPMENT_TEAM is required for --signed-builds')
    sdks = ('macosx', 'iphoneos') if signed else (('macosx', 'iphonesimulator') if caller == 'simulator-features' else ('macosx',))
    identity = {'kind': 'legacy-' + caller, 'toolchain': toolchain_identity(sdks),
                'configuration': 'Debug', 'architecture': platform.machine(),
                'signing': {'mode': 'development' if signed else 'unsigned',
                            'team': os.environ.get('MACCOMPANION_DEVELOPMENT_TEAM') if signed else None},
                'variant': os.environ.get('MACCOMPANION_LEGACY_CACHE_VARIANT', ''),
                'environment': {name: os.environ.get(name) for name in
                    ('SDKROOT', 'TOOLCHAINS', 'SWIFTFLAGS', 'CFLAGS', 'CPPFLAGS', 'CXXFLAGS', 'LDFLAGS')}}
    if caller == 'simulator-features':
        real_mac = os.environ.get('MACCOMPANION_LAB_SOURCE', 'generated') == 'real-mac-window'
        identity['hostSigningIdentity'] = os.environ.get('MACCOMPANION_LAB_SIGNING_IDENTITY', 'Apple Development') if real_mac else None
    return identity


def group_alive(pid):
    # Darwin can return EPERM for an empty group; inspect only group IDs/status.
    rows = capture('/bin/ps', '-axo', 'pgid=,stat=').splitlines()
    return any(len(parts := row.split()) == 2 and parts[0] == str(pid) and not parts[1].startswith('Z') for row in rows)


def send_group(pid, signum):
    try:
        os.killpg(pid, signum)
    except ProcessLookupError:
        pass
    except PermissionError:
        if group_alive(pid):
            raise


def stop_group(process):
    send_group(process.pid, signal.SIGTERM)
    deadline = time.monotonic() + 10
    while group_alive(process.pid) and time.monotonic() < deadline:
        time.sleep(.05)
    if group_alive(process.pid):
        send_group(process.pid, signal.SIGKILL)
        deadline = time.monotonic() + 5
        while group_alive(process.pid) and time.monotonic() < deadline:
            time.sleep(.05)
        if group_alive(process.pid):
            raise RuntimeError('Owned workflow workers could not be stopped.')
    process.wait()


def run_command(command, env, log):
    process = None
    received = []
    def interrupted(signum, frame):
        received.append((signum, time.monotonic()))
        if process is not None:
            send_group(process.pid, signum)
    previous = {sig: signal.signal(sig, interrupted) for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)}
    try:
        process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
        for sig, _ in received:
            send_group(process.pid, sig)
        decoder = codecs.getincrementaldecoder('utf-8')('replace')
        def retain(data, final=False):
            text = decoder.decode(data, final=final)
            log.write(text); log.flush()
            print(text, end='', flush=True)
        pipe_open = True
        while process.poll() is None:
            if pipe_open and select.select([process.stdout], [], [], .2)[0]:
                data = os.read(process.stdout.fileno(), 65536)
                pipe_open = bool(data)
                retain(data)
            elif not pipe_open:
                time.sleep(.05)
            if received and time.monotonic() - received[0][1] > 10:
                send_group(process.pid, signal.SIGKILL)
        code = process.wait()
        stop_group(process)
        while pipe_open:
            data = os.read(process.stdout.fileno(), 65536)
            pipe_open = bool(data)
            retain(data)
        retain(b'', final=True)
        return 128 + received[0][0] if received else code
    finally:
        try:
            if process is not None:
                stop_group(process)
                process.stdout.close()
        finally:
            for sig, handler in previous.items():
                signal.signal(sig, handler)


def snapshot_apps(session):
    if session.identity['kind'] == 'legacy-simulator-features':
        relatives = ['DerivedData/Build/Products/Debug-iphonesimulator/ClientUIHarness.app',
                     'DerivedData/Build/Products/Debug-iphonesimulator/ClientUIHarnessUITests-Runner.app']
        if session.identity.get('hostSigningIdentity'):
            relatives.append('Mac Companion Real Mac Lab.app')
    elif session.identity['signing']['mode'] == 'development':
        relatives = ['DerivedData/mac/Build/Products/Debug/Mac Companion.app',
                     'DerivedData/ios/Build/Products/Debug-iphoneos/Mac Companion.app']
    else:
        relatives = []
    candidates = [session.workspace / name for name in relatives if (session.workspace / name).exists()]
    snapshots = []
    for app in sorted(set(candidates)):
        if app.is_symlink() or not app.resolve().is_relative_to(session.workspace):
            raise ValueError('App snapshot must come from this compiler workspace.')
        relative = app.relative_to(session.workspace)
        before = file_manifest(app)
        destination = session.run / 'products' / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(app, destination, symlinks=True)
        if file_manifest(destination) != before or file_manifest(app) != before:
            raise RuntimeError('App changed while preserving evidence: ' + str(app))
        snapshots.append(str(destination))
    return snapshots


def evidence_root(identity):
    key = hashlib.sha256(json.dumps(dict(identity, checkout=str(ROOT)), sort_keys=True).encode()).hexdigest()[:24]
    return DEFAULT_EVIDENCE / ('legacy-' + key)


def run(caller, arguments):
    for old in ('MACCOMPANION_LAB_DERIVED_DATA', 'MACCOMPANION_PAIRING_DERIVED_DATA'):
        if os.environ.get(old):
            raise ValueError(old + ' is no longer a compiler override; use MACCOMPANION_BUILD_CACHE_ROOT and MACCOMPANION_LEGACY_EVIDENCE_ROOT.')
    developer = Path(os.environ.get('MACCOMPANION_DEVELOPER_DIR') or os.environ.get('DEVELOPER_DIR') or capture('xcode-select', '-p')).resolve()
    if developer.suffix == '.app':
        developer /= 'Contents/Developer'
    os.environ['DEVELOPER_DIR'] = os.environ['MACCOMPANION_DEVELOPER_DIR'] = str(developer)
    identity = build_identity(caller, arguments)
    evidence = os.environ.get('MACCOMPANION_LEGACY_EVIDENCE_ROOT') or evidence_root(identity)
    cold = os.environ.get('MACCOMPANION_LEGACY_COLD') == '1'
    with ExitStack() as stack:
        session = stack.enter_context(BuildSession(ROOT, evidence, identity, cold=cold, aliases=False))
        for relative in ('DerivedData', 'DerivedData/mac', 'DerivedData/ios', 'host-build', 'package-build'):
            safe_directory(session.workspace / relative)
        env = dict(os.environ, MACCOMPANION_LEGACY_MANAGED=caller,
                   MACCOMPANION_LEGACY_WORKSPACE=str(session.workspace),
                   MACCOMPANION_LEGACY_RUN=str(session.run))
        pairing = None
        if caller == 'simulator-features':
            # One supervisor owns both leases and one worker process group.
            # Killing a nested supervisor must never unlock a surviving compiler.
            pairing_identity = build_identity('pairing-reliability', [])
            pairing = stack.enter_context(BuildSession(ROOT, evidence_root(pairing_identity), pairing_identity, cold=cold, aliases=False))
            safe_directory(pairing.workspace / 'package-build')
            env.update(MACCOMPANION_PAIRING_WORKSPACE=str(pairing.workspace), MACCOMPANION_PAIRING_RUN=str(pairing.run))
        env.pop('MACCOMPANION_LEGACY_EVIDENCE_ROOT', None)
        print('Legacy build evidence:', session.run, flush=True)
        if caller == 'simulator-features':
            # Existing soak/performance callers parse this line as the report directory.
            print('Evidence:', session.run, flush=True)
        shell, script = CALLERS[caller]
        with (session.run / 'workflow.log').open('w') as log:
            code = run_command([shell, str(ROOT / 'scripts' / script), *arguments], env, log)
        if pairing:
            pairing.metadata.update(parentEvidence=str(session.run),
                                    checkpointAttempted=(pairing.run / 'checkpoint-started').exists(),
                                    checkpointPassed=(pairing.run / 'checkpoint-passed').exists())
            if (session.run / 'pairing.log').is_file():
                shutil.copy2(session.run / 'pairing.log', pairing.run / 'workflow.log')
        if caller == 'pairing-reliability' and re.search(r'Some test targets (reported failures|did not run successfully)|✘ Test|Test run with .* failed after', (session.run / 'workflow.log').read_text()):
            code = code or 1
        snapshots = snapshot_apps(session) if not code else []
        (session.run / 'products.json').write_text(json.dumps({'apps': snapshots}, indent=2) + '\n')
        if code:
            raise subprocess.CalledProcessError(code, [script, *arguments])


if __name__ == '__main__':
    try:
        if len(sys.argv) < 2:
            raise ValueError('Expected a legacy caller name.')
        run(sys.argv[1], sys.argv[2:])
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode if error.returncode >= 0 else 128 - error.returncode)
