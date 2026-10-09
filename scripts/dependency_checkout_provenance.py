"""Verify the remote source trees that SwiftPM actually supplies to a build.

Package.resolved selects revisions; it does not reject edits in reused checkouts.
This module reads the resolved workspace and Git trees without changing either.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from urllib.parse import urlsplit


class CheckoutProvenanceError(ValueError):
    pass


def _git(repository, *arguments):
    return subprocess.check_output(
        ['git', '--no-optional-locks', '--no-replace-objects', '-c', 'core.fsmonitor=false', '-c', 'core.ignorestat=false',
         '-C', str(repository), *arguments], stderr=subprocess.PIPE)


def _source_url(value):
    url = urlsplit(value)
    if (url.scheme != 'https' or not url.hostname or url.username is not None or url.password is not None
            or url.query or url.fragment):
        raise CheckoutProvenanceError('Remote dependency source must have an HTTPS repository URL.')
    path = url.path.rstrip('/')
    if path.endswith('.git'):
        path = path[:-4]
    return (url.hostname.lower(), url.port, path.lower() if url.hostname.lower() == 'github.com' else path)


def _verify_origin(checkout, packages, location):
    origin = _git(checkout, 'remote', 'get-url', 'origin').decode().strip()
    # SwiftPM clones from its local bare repository cache. Follow that one
    # indirection, constrained to this build's repository directory.
    if Path(origin).is_absolute():
        cache = Path(origin).resolve(strict=True)
        if not cache.is_relative_to((packages / 'repositories').resolve()):
            raise CheckoutProvenanceError('Dependency origin is outside its resolved repository cache.')
        origin = _git(cache, 'remote', 'get-url', 'origin').decode().strip()
    if _source_url(origin) != _source_url(location):
        raise CheckoutProvenanceError('Dependency origin does not match its admitted source URL.')
    return origin


def _source_tree(checkout):
    if _git(checkout, 'status', '--porcelain', '-z', '--untracked-files=all'):
        raise CheckoutProvenanceError('Dependency checkout has tracked or untracked changes.')
    # Ignored additions can still be picked up by a package target or generator.
    if _git(checkout, 'ls-files', '--others', '--ignored', '--exclude-standard', '-z'):
        raise CheckoutProvenanceError('Dependency checkout contains unadmitted ignored files.')
    files = {}
    for entry in _git(checkout, 'ls-tree', '-r', '-z', 'HEAD').split(b'\0'):
        if not entry:
            continue
        metadata, encoded_path = entry.split(b'\t', 1)
        mode, kind, object_id = metadata.split()
        name = os.fsdecode(encoded_path)
        path = checkout / name
        if kind != b'blob' or mode not in [b'100644', b'100755', b'120000']:
            raise CheckoutProvenanceError('Dependency tree contains an unsupported Git entry: ' + name)
        if not path.resolve(strict=True).is_relative_to(checkout):
            raise CheckoutProvenanceError('Dependency source resolves outside its checkout: ' + name)
        if mode == b'120000':
            if not path.is_symlink():
                raise CheckoutProvenanceError('Dependency symlink changed: ' + name)
            data = os.fsencode(os.readlink(path))
        else:
            if path.is_symlink() or not path.is_file():
                raise CheckoutProvenanceError('Dependency source file changed: ' + name)
            if bool(path.stat().st_mode & 0o111) != (mode == b'100755'):
                raise CheckoutProvenanceError('Dependency source executable mode changed: ' + name)
            data = path.read_bytes()
        # Comparing bytes with HEAD also catches assume-unchanged/skip-worktree
        # edits that Git status can omit. All admitted repositories use SHA-1 Git.
        blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest().encode()
        if blob != object_id:
            raise CheckoutProvenanceError('Dependency source differs from its pinned Git tree: ' + name)
        files[name] = {'mode': mode.decode(), 'sha256': hashlib.sha256(data).hexdigest()}
    encoded = json.dumps(files, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode()
    return {'sourceTreeSHA256': hashlib.sha256(encoded).hexdigest(), 'trackedFileCount': len(files)}


def verify_checkouts(source_packages, pins, *, previous=None):
    """Return actual content provenance for every admitted resolved remote package.

    Pass the pre-build result as ``previous`` after building to reject a changed
    workspace/source snapshot. No reset, checkout, fetch or cache mutation occurs.
    """
    packages = Path(source_packages).resolve(strict=True)
    state = json.loads((packages / 'workspace-state.json').read_text())
    dependencies = {}
    for dependency in state['object']['dependencies']:
        reference = dependency['packageRef']
        if reference['kind'] != 'remoteSourceControl':
            continue
        identity = reference['identity']
        if identity in dependencies:
            raise CheckoutProvenanceError('Duplicate resolved dependency identity: ' + identity)
        dependencies[identity] = dependency
    admitted = {}
    for pin in pins:
        identity = pin['identity']
        if pin['kind'] != 'remoteSourceControl' or identity in admitted:
            raise CheckoutProvenanceError('Invalid or duplicate admitted remote dependency.')
        if not re.fullmatch(r'[0-9a-f]{40}', pin['state']['revision']):
            raise CheckoutProvenanceError('Invalid admitted dependency revision: ' + identity)
        admitted[identity] = pin
    if not admitted or dependencies.keys() != admitted.keys():
        raise CheckoutProvenanceError('Resolved remote dependency identities do not match the complete lockfile.')
    snapshot = {}
    for identity, pin in sorted(admitted.items()):
        try:
            dependency = dependencies[identity]
            location = pin['location']
            if _source_url(dependency['packageRef']['location']) != _source_url(location):
                raise CheckoutProvenanceError('Resolved source URL does not match the admitted URL.')
            revision = pin['state']['revision']
            if dependency['state']['name'] != 'sourceControlCheckout' or dependency.get('basedOn') is not None:
                raise CheckoutProvenanceError('Resolved dependency is not an unedited source-control checkout.')
            if dependency['state']['checkoutState']['revision'] != revision:
                raise CheckoutProvenanceError('Resolved workspace revision does not match its pin.')
            subpath = Path(dependency['subpath'])
            if subpath.is_absolute() or len(subpath.parts) != 1 or subpath.name in ['.', '..']:
                raise CheckoutProvenanceError('Invalid resolved checkout subpath.')
            checkout_root = (packages / 'checkouts').resolve(strict=True)
            checkout = (checkout_root / subpath).resolve(strict=True)
            if checkout.parent != checkout_root:
                raise CheckoutProvenanceError('Resolved checkout is outside its package directory.')
            if Path(_git(checkout, 'rev-parse', '--show-toplevel').decode().strip()).resolve() != checkout:
                raise CheckoutProvenanceError('Resolved checkout does not own its Git worktree.')
            actual_revision = _git(checkout, 'rev-parse', 'HEAD').decode().strip()
            if actual_revision != revision:
                raise CheckoutProvenanceError('Dependency checkout HEAD does not match its pinned revision.')
            origin = _verify_origin(checkout, packages, location)
            snapshot[identity] = {'revision': actual_revision, 'location': location,
                                  'originURL': origin, 'checkoutSubpath': str(subpath), **_source_tree(checkout)}
        except (OSError, KeyError, ValueError, subprocess.CalledProcessError) as error:
            raise CheckoutProvenanceError('Dependency ' + identity + ' failed source verification: ' + str(error)) from error
    if previous is not None and snapshot != previous:
        raise CheckoutProvenanceError('Resolved dependency source provenance changed during the build.')
    return snapshot
