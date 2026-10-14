#!/usr/bin/env python3
"""Managed development build workspaces; evidence is retained, deletion is never automatic."""
import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time
import uuid

SCHEMA = 1
ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CACHE = Path('/private/tmp') / f'maccompanion-build-cache-{os.getuid()}'
DEFAULT_EVIDENCE = Path('/private/tmp') / f'maccompanion-build-evidence-{os.getuid()}'


def write_if_changed(path, content):
    path = Path(path)
    data = content.encode() if isinstance(content, str) else content
    if not path.exists() or path.read_bytes() != data:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)


def atomic_json(path, value):
    temporary = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    os.replace(temporary, path)


def capture(*args):
    return subprocess.check_output([str(a) for a in args], text=True).strip()


def toolchain_identity(sdks=()):
    return {'xcode': capture('xcodebuild', '-version'),
            'developerDirectory': capture('xcode-select', '-p') if not os.environ.get('DEVELOPER_DIR') else str(Path(os.environ['DEVELOPER_DIR']).resolve()),
            'swift': capture('swift', '--version'),
            'sdks': {sdk: {'path': capture('xcrun', '--sdk', sdk, '--show-sdk-path'),
                           'version': capture('xcrun', '--sdk', sdk, '--show-sdk-version')} for sdk in sdks}}


def cmake_refresh_args(build, source):
    cache = Path(build) / 'CMakeCache.txt'
    if cache.exists() and ('CMAKE_HOME_DIRECTORY:INTERNAL=' + str(Path(source).resolve())) not in cache.read_text().splitlines():
        return ['--fresh']
    return []


def safe_directory(path):
    path = Path(path).expanduser()
    if path.is_symlink():
        raise ValueError('Managed directory must not be a symlink: ' + str(path))
    path = path.resolve()
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    if not path.is_dir() or path.stat().st_uid != os.getuid():
        raise ValueError('Managed directory is not owned by this user: ' + str(path))
    return path


def file_manifest(root):
    result = {}
    for path in sorted(root.rglob('*')):
        if path.is_symlink():
            if not path.resolve().is_relative_to(root.resolve()):
                raise ValueError('App contains a link outside the bundle: ' + str(path))
            result[str(path.relative_to(root))] = {'link': os.readlink(path)}
        elif path.is_file():
            result[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def acquire_lock(path, timeout=300):
    fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    handle = os.fdopen(fd, 'a+')
    deadline = time.monotonic() + timeout
    while True:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return handle
        except BlockingIOError:
            if time.monotonic() >= deadline:
                handle.close()
                raise RuntimeError('Build workspace is busy; no running build was interrupted: ' + str(path.parent))
            time.sleep(.1)


class BuildSession:
    """One exclusive compiler workspace and one immutable evidence generation."""
    def __init__(self, checkout, evidence, identity, *, cache_root=None, cold=False, timeout=300, aliases=True):
        self.checkout = Path(checkout).resolve()
        self.identity = dict(identity, checkout=str(self.checkout), schema=SCHEMA)
        self.cache_root = Path(cache_root or os.environ.get('MACCOMPANION_BUILD_CACHE_ROOT', DEFAULT_CACHE)).expanduser()
        self.evidence = Path(evidence).expanduser()
        self.cold, self.timeout, self.aliases = cold, timeout, aliases
        key = hashlib.sha256(json.dumps(self.identity, sort_keys=True).encode()).hexdigest()[:24]
        self.key = key + ('-cold-' + uuid.uuid4().hex[:12] if cold else '')
        self.run_id = time.strftime('%Y%m%dT%H%M%SZ', time.gmtime()) + '-' + uuid.uuid4().hex[:12]
        self.lock = self.evidence_lock = None
        self.started_ns = None
        self.published = False

    def acquire(self, path):
        return acquire_lock(path, self.timeout)

    def __enter__(self):
        if self.cache_root.resolve().is_relative_to(self.checkout) or self.evidence.resolve().is_relative_to(self.checkout):
            raise ValueError('Managed compiler caches and evidence must be outside the checkout.')
        if self.evidence.resolve().is_relative_to(self.cache_root.resolve()) or self.cache_root.resolve().is_relative_to(self.evidence.resolve()):
            raise ValueError('Evidence and cache roots must be separate.')
        self.cache_root = safe_directory(self.cache_root)
        self.evidence = safe_directory(self.evidence)
        root_marker = self.cache_root / '.maccompanion-cache-root.json'
        if root_marker.is_symlink():
            raise ValueError('Cache root marker must not be a symlink.')
        with self.acquire(self.cache_root / '.registry.lock'):
            if root_marker.exists():
                if json.loads(root_marker.read_text()) != {'schema': SCHEMA, 'uid': os.getuid()}:
                    raise ValueError('Unrecognized managed cache root.')
            else:
                allowed = {'.registry.lock'}
                if any(p.name not in allowed for p in self.cache_root.iterdir()):
                    raise ValueError('Refusing to adopt existing unmarked cache data.')
                atomic_json(root_marker, {'schema': SCHEMA, 'uid': os.getuid()})
            slots = safe_directory(self.cache_root / 'workspaces')
            self.workspace = safe_directory(slots / self.key)
        try:
            self.lock = self.acquire(self.workspace / '.build.lock')
            marker = self.workspace / '.workspace.json'
            if marker.is_symlink():
                raise ValueError('Workspace marker must not be a symlink.')
            if marker.exists() and json.loads(marker.read_text()).get('identity') != self.identity:
                raise ValueError('Compiler workspace identity mismatch.')
            if not marker.exists() and any(p.name != '.build.lock' for p in self.workspace.iterdir()):
                raise ValueError('Refusing to adopt unmarked compiler output.')
            self.evidence_lock = self.acquire(self.evidence / '.evidence.lock')
            evidence_marker = self.evidence / '.maccompanion-evidence.json'
            owner = {'schema': SCHEMA, 'identity': self.identity, 'uid': os.getuid()}
            if evidence_marker.is_symlink():
                raise ValueError('Evidence marker must not be a symlink.')
            if evidence_marker.exists():
                if json.loads(evidence_marker.read_text()) != owner:
                    raise ValueError('Evidence directory belongs to another build configuration.')
            else:
                if any(p.name != '.evidence.lock' for p in self.evidence.iterdir()):
                    raise ValueError('Existing output is preserved; choose a new evidence directory: ' + str(self.evidence))
                atomic_json(evidence_marker, owner)
            generations = safe_directory(self.evidence / 'runs')
            self.run = generations / self.run_id
            self.run.mkdir(mode=0o700)
            self.started_ns = time.time_ns()
            self.metadata = {'schema': SCHEMA, 'identity': self.identity, 'cold': self.cold,
                             'workspace': str(self.workspace), 'lastUsedUnix': time.time(),
                             'lastEvidence': str(self.run), 'status': 'running', 'pid': os.getpid()}
            atomic_json(marker, self.metadata)
            atomic_json(self.run / 'run.json', self.metadata)
            return self
        except BaseException:
            if self.evidence_lock:
                self.evidence_lock.close()
            if self.lock:
                self.lock.close()
            raise

    def alias(self, name, target):
        destination = self.evidence / name
        if destination.exists() or destination.is_symlink():
            if not destination.is_symlink() or not destination.resolve().is_relative_to(self.evidence / 'runs'):
                raise ValueError('Existing output is preserved; choose a new evidence directory: ' + str(destination))
        temporary = self.evidence / ('.alias-' + uuid.uuid4().hex)
        temporary.symlink_to(os.path.relpath(target, self.evidence), target_is_directory=target.is_dir())
        os.replace(temporary, destination)

    def copy_logs(self):
        paths = list(self.workspace.glob('*.log')) + list((self.workspace / 'openssl').glob('*.log'))
        for path in paths:
            if path.is_file() and not path.is_symlink() and path.stat().st_mtime_ns >= self.started_ns:
                relative = path.relative_to(self.workspace)
                destination = self.run / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, destination)

    def copy_configuration(self):
        for path in self.workspace.iterdir():
            if path.is_symlink() or path.name.startswith('.'):
                continue
            if path.is_file() and path.suffix in {'.json', '.plist', '.entitlements', '.txt'}:
                shutil.copy2(path, self.run / path.name)
            elif path.is_dir() and path.suffix == '.xcodeproj':
                shutil.copytree(path, self.run / path.name, symlinks=True)

    def prepared(self, project):
        self.copy_configuration()
        self.metadata['preparedProject'] = str(project)
        print('Preparation evidence:', self.run, flush=True)

    def publish(self, report, app):
        app = Path(app)
        if not app.is_relative_to(self.workspace) or app.is_symlink():
            raise ValueError('App snapshot must come from this compiler workspace.')
        relative = app.relative_to(self.workspace)
        snapshot = self.run / relative
        snapshot.parent.mkdir(parents=True, exist_ok=True)
        before = file_manifest(app)
        shutil.copytree(app, snapshot, symlinks=True)
        if file_manifest(snapshot) != before or file_manifest(app) != before:
            raise RuntimeError('App changed while preserving verified evidence.')
        self.copy_configuration()
        self.copy_logs()
        report = dict(report, app=str(snapshot), cacheWorkspace=str(self.workspace),
                      evidenceRun=str(self.run), managedBuildCache={'schema': SCHEMA, 'key': self.key, 'cold': self.cold})
        atomic_json(self.run / 'build-report.json', report)
        if self.aliases:
            # Check every destination before replacing any latest-run aliases.
            for path in self.run.iterdir():
                destination = self.evidence / path.name
                if path.name != 'run.json' and (destination.exists() or destination.is_symlink()):
                    if not destination.is_symlink() or not destination.resolve().is_relative_to(self.evidence / 'runs'):
                        raise ValueError('Existing output is preserved; choose a new evidence directory: ' + str(destination))
            for path in self.run.iterdir():
                if path.name != 'run.json':
                    self.alias(path.name, path)
        self.published = True
        return report

    def __exit__(self, kind, value, traceback):
        try:
            self.copy_logs()
            self.metadata.update(lastUsedUnix=time.time(), status='failed' if kind else ('prepared' if 'preparedProject' in self.metadata else 'passed'), pid=None)
            if kind:
                self.metadata['failureType'] = kind.__name__
                if isinstance(value, subprocess.CalledProcessError):
                    self.metadata['exitCode'] = value.returncode
            atomic_json(self.workspace / '.workspace.json', self.metadata)
            atomic_json(self.run / 'run.json', self.metadata)
        finally:
            self.evidence_lock.close()
            self.lock.close()
        return False


@contextmanager
def compiler_workspace(evidence, checkout=ROOT, timeout=300):
    """Lease the original compiler files for existing QA/archive consumers.

    Legacy build folders still work. A reused managed workspace must be rebuilt
    before an older report can authorize another compilation against it.
    """
    evidence = Path(evidence).resolve()
    report_path = evidence / 'build-report.json'
    report = json.loads(report_path.read_text()) if report_path.exists() else {}
    if 'managedBuildCache' not in report:
        yield evidence
        return
    workspace = Path(report['cacheWorkspace'])
    if workspace.is_symlink() or not workspace.is_dir() or workspace.stat().st_uid != os.getuid():
        raise ValueError('Managed compiler workspace is unavailable. Rebuild the development app.')
    evidence_run = Path(report['evidenceRun'])
    evidence_root = evidence_run.parent.parent
    if evidence_run.parent.name != 'runs' or not evidence_run.is_relative_to(evidence_root):
        raise ValueError('Invalid managed evidence location.')
    with acquire_lock(workspace / '.build.lock', timeout), acquire_lock(evidence_root / '.evidence.lock', timeout):
        # A cold build can use another workspace while publishing to the same
        # evidence root. Lease both and reject aliases that changed while waiting.
        if json.loads(report_path.read_text()) != report:
            raise ValueError('Build evidence changed while waiting. Retry with the current report.')
        marker = workspace / '.workspace.json'
        if marker.is_symlink():
            raise ValueError('Invalid compiler workspace marker.')
        metadata = json.loads(marker.read_text())
        if (metadata['identity']['checkout'] != str(Path(checkout).resolve())
                or metadata['lastEvidence'] != report['evidenceRun'] or metadata['status'] != 'passed'):
            raise ValueError('Compiler cache has been reused or failed since this report. Rebuild before QA/archive.')
        admitted_toolchain = metadata['identity'].get('toolchain', {})
        if 'sdks' in admitted_toolchain and toolchain_identity(admitted_toolchain['sdks']) != admitted_toolchain:
            raise ValueError('Selected toolchain changed. Rebuild before QA/archive.')
        try:
            yield workspace
        finally:
            metadata['lastUsedUnix'] = time.time()
            atomic_json(marker, metadata)


def cache_status(root, budget_gib=40, inactive_days=2):
    root = Path(root).expanduser()
    if not root.exists():
        return {'cacheRoot': str(root), 'workspaces': [], 'totalAllocatedBytes': 0, 'deletionEnabled': False}
    marker = root / '.maccompanion-cache-root.json'
    if root.is_symlink() or marker.is_symlink() or json.loads(marker.read_text()) != {'schema': SCHEMA, 'uid': os.getuid()}:
        raise ValueError('Unrecognized managed cache root.')
    rows = []
    slots = root / 'workspaces'
    if slots.is_symlink():
        raise ValueError('Unexpected linked workspace directory.')
    for path in sorted(slots.iterdir()):
        if path.is_symlink() or not path.is_dir():
            raise ValueError('Unexpected compiler workspace entry.')
        marker = path / '.workspace.json'
        if marker.is_symlink():
            raise ValueError('Unexpected linked workspace marker.')
        if not marker.exists():
            continue  # A new slot may still be waiting for its first lease.
        metadata = json.loads(marker.read_text())
        with os.fdopen(os.open(path / '.build.lock', os.O_RDONLY | os.O_NOFOLLOW)) as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                active = False
            except BlockingIOError:
                active = True
        size = int(capture('du', '-x', '-k', '-s', path).split()[0]) * 1024
        rows.append({'path': str(path), 'kind': metadata['identity'].get('kind'),
                     'checkout': metadata['identity']['checkout'], 'cold': metadata['cold'], 'active': active,
                     'lastUsedUnix': metadata['lastUsedUnix'], 'allocatedBytes': size,
                     'reviewCandidate': not active and (metadata['cold'] or time.time() - metadata['lastUsedUnix'] > inactive_days * 86400)})
    total = sum(r['allocatedBytes'] for r in rows)
    return {'cacheRoot': str(root), 'workspaces': rows, 'totalAllocatedBytes': total,
            'budgetBytes': budget_gib * 2**30, 'overBudget': total > budget_gib * 2**30,
            'deletionEnabled': False, 'note': 'Allocated sizes can overcount APFS shared blocks. Candidates require explicit approval.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    validation = commands.add_parser('validate')
    validation.add_argument('--cache-root', type=Path)
    validation.add_argument('--evidence-root', type=Path)
    validation.add_argument('--cold', action='store_true')
    status = commands.add_parser('status')
    status.add_argument('--cache-root', type=Path, default=Path(os.environ.get('MACCOMPANION_BUILD_CACHE_ROOT', DEFAULT_CACHE)))
    status.add_argument('--budget-gib', type=float, default=40)
    status.add_argument('--inactive-days', type=float, default=2)
    args = parser.parse_args()
    if args.command == 'status':
        print(json.dumps(cache_status(args.cache_root, args.budget_gib, args.inactive_days), indent=2))
        return
    evidence = args.evidence_root or os.environ.get('MACCOMPANION_VALIDATION_EVIDENCE_ROOT') or os.environ.get('MACCOMPANION_VALIDATION_SCRATCH_ROOT') or DEFAULT_EVIDENCE / hashlib.sha256(str(ROOT).encode()).hexdigest()[:12]
    with BuildSession(ROOT, evidence, {'kind': 'validation', 'toolchain': toolchain_identity(('macosx', 'iphonesimulator')),
                                      'swiftPMSandboxDisabled': os.environ.get('MACCOMPANION_DISABLE_SWIFTPM_SANDBOX') == '1'},
                      cache_root=args.cache_root, cold=args.cold, aliases=False) as session:
        env = dict(os.environ, MACCOMPANION_VALIDATION_MANAGED='1',
                   MACCOMPANION_VALIDATION_SCRATCH_ROOT=str(session.workspace))
        with (session.run / 'validation.log').open('w') as log:
            process = subprocess.Popen(['bash', str(ROOT / 'scripts/validate.sh')], cwd=ROOT, env=env,
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, start_new_session=True)
            try:
                for line in process.stdout:
                    print(line, end='', flush=True)
                    log.write(line)
                code = process.wait()
            except BaseException:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                raise
            finally:
                process.stdout.close()
        print('Validation evidence:', session.run, flush=True)
        if code:
            raise subprocess.CalledProcessError(code, ['bash', 'scripts/validate.sh'])


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode)
