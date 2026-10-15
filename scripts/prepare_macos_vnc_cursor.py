"""Make an exact, admitted macOS cursor adapter without editing the pinned checkout."""
import difflib
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BEFORE = b'  if (width * height == 0)\n    return TRUE;\n'
AFTER = (b'  if (width * height == 0) {\n'
         b'    if (client->GotCursorShape != NULL)\n'
         b'      client->GotCursorShape(client, xhot, yhot, width, height, bytesPerPixel);\n'
         b'    return TRUE;\n  }\n')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def adapted_cursor(original, policy):
    """Only this exact transform, including the published patch, is admitted."""
    if policy['path'] != 'src/libvncclient/cursor.c' or policy['patchPath'] != 'Native/VNC/macos-empty-cursor.patch':
        raise ValueError('Unexpected macOS cursor adapter path.')
    if digest(original) != policy['originalSHA256'] or original.count(BEFORE) != 1:
        raise ValueError('Pinned cursor source does not match the admitted original.')
    adapted = original.replace(BEFORE, AFTER)
    patch = ''.join(difflib.unified_diff(original.decode().splitlines(True), adapted.decode().splitlines(True),
        fromfile='a/' + policy['path'], tofile='b/' + policy['path'])).encode()
    if (digest(adapted) != policy['adaptedSHA256'] or digest(patch) != policy['patchSHA256']
            or (ROOT / policy['patchPath']).read_bytes() != patch):
        raise ValueError('macOS cursor adapter differs from its admitted patch.')
    return adapted


def inventory(directory):
    """Reject links, unknown files, mode changes and changed compiled bytes."""
    directory = Path(directory)
    if directory.is_symlink() or not directory.is_dir():
        raise ValueError('macOS VNC generated source must be a real directory.')
    result = {}
    for path in sorted(directory.rglob('*')):
        mode = path.lstat().st_mode
        name = str(path.relative_to(directory))
        if stat.S_ISDIR(mode):
            result[name] = {'kind': 'directory'}
        elif stat.S_ISREG(mode):
            result[name] = {'kind': 'file', 'mode': stat.S_IMODE(mode), 'sha256': digest(path.read_bytes())}
        else:
            raise ValueError('Unsupported entry in macOS VNC generated source: ' + name)
    return result


def verify(directory, expected):
    actual = inventory(directory)
    if actual != expected:
        raise ValueError('macOS VNC generated source differs from the admitted tree.')
    return {'sourceTreeSHA256': digest(json.dumps(actual, sort_keys=True, separators=(',', ':')).encode()),
            'fileCount': sum(row['kind'] == 'file' for row in actual.values())}


def prepare(source, output, lock):
    from dependency_checkout_provenance import verify_source_checkout
    source = Path(source).resolve(strict=True)
    verify_source_checkout(source, lock['revision'])
    policy = lock['macOSCursorCallback']
    adapted = adapted_cursor((source / policy['path']).read_bytes(), policy)
    from prepare_vnc_read_service import adapted_read_service, TRANSFORMS
    read_policies = lock['desktopReadInputService']['patches']
    if len(read_policies) != len(TRANSFORMS) or {row['path'] for row in read_policies} != set(TRANSFORMS):
        raise ValueError('Missing or duplicate VNC read-service adapter policies.')
    adaptations = {policy['path']: adapted}
    for row in read_policies:
        adaptations[row['path']] = adapted_read_service((source / row['path']).read_bytes(), row)
    # Enumerate the pinned Git tree, never mutable ignored/untracked files.
    tree = subprocess.check_output(['git', '--no-replace-objects', '-C', str(source), 'ls-tree', '-r', '-z', 'HEAD'])
    files, directories = {}, set()
    for entry in tree.split(b'\0'):
        if not entry:
            continue
        metadata, encoded_name = entry.split(b'\t', 1)
        mode, kind, _ = metadata.split()
        name = os.fsdecode(encoded_name)
        if kind == b'commit' and mode == b'160000':
            # Documentation/web-client submodules are not compiled by this client.
            directories.add(name)
        elif kind == b'blob' and mode in [b'100644', b'100755']:
            files[name] = (0o755 if mode == b'100755' else 0o644,
                           adaptations[name] if name in adaptations else (source / name).read_bytes())
        else:
            raise ValueError('Unsupported pinned VNC source entry: ' + name)
        directories.update(str(parent) for parent in Path(name).parents if str(parent) != '.')
    expected = {name: {'kind': 'directory'} for name in directories}
    expected.update({name: {'kind': 'file', 'mode': mode, 'sha256': digest(data)} for name, (mode, data) in files.items()})
    adaptation_key = digest(json.dumps({name: digest(data) for name, data in adaptations.items()}, sort_keys=True).encode())
    destination = Path(output) / ('libvncclient-source-direct-' + adaptation_key)
    if not destination.exists() and not destination.is_symlink():
        with tempfile.TemporaryDirectory(prefix='macos-vnc-source-', dir=output) as temporary:
            staging = Path(temporary) / 'source'; staging.mkdir()
            for name in sorted(directories):
                (staging / name).mkdir(parents=True, exist_ok=True)
            for name, (mode, data) in files.items():
                path = staging / name; path.write_bytes(data); path.chmod(mode)
            verify(staging, expected)
            staging.rename(destination)
    provenance = verify(destination, expected)
    return destination, expected, provenance
