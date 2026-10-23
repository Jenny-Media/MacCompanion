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
from urllib.parse import unquote, urlsplit


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


def _cloud_origin(origin):
    # Xcode Cloud supplies authenticated HTTPS or SSH transport URLs for the
    # same public GitHub repositories. Never retain credentials in evidence.
    if origin.startswith('git@github.com:'):
        origin = 'ssh://git@github.com/' + origin[len('git@github.com:'):]
    url = urlsplit(origin)
    if (url.hostname != 'github.com' or url.query or url.fragment
            or url.scheme not in {'https', 'ssh'}
            or (url.scheme == 'https' and url.port not in {None, 443})
            or (url.scheme == 'ssh' and (url.username != 'git' or url.password is not None
                                        or url.port not in {None, 22}))):
        raise CheckoutProvenanceError('Unsupported cloud dependency transport '
                                      f'(scheme={url.scheme!r}, host={url.hostname!r}); expected the pinned GitHub source.')
    return 'https://github.com' + url.path


def _verify_origin(checkout, packages, location, allow_cloud_transport=False):
    # get-url expands insteadOf rules, which cloud workers can use to route
    # fetches through their local SCM proxy. Match the configured repository
    # identity there; the pinned tree/content checks still verify fetched bytes.
    command = ('config', '--local', '--get', 'remote.origin.url') if allow_cloud_transport else ('remote', 'get-url', 'origin')
    origin = _git(checkout, *command).decode().strip()
    if allow_cloud_transport and origin.startswith('file:'):
        url = urlsplit(origin)
        if url.netloc not in {'', 'localhost'} or url.query or url.fragment or not url.path.startswith('/'):
            raise CheckoutProvenanceError('Invalid cloud dependency cache URL.')
        origin = unquote(url.path)
    # SwiftPM clones from its local bare repository cache. Follow that one
    # indirection, constrained to this build's repository directory.
    if Path(origin).is_absolute():
        cache = Path(origin).resolve(strict=True)
        if not cache.is_relative_to((packages / 'repositories').resolve()):
            raise CheckoutProvenanceError('Dependency origin is outside its resolved repository cache.')
        origin = _git(cache, *command).decode().strip()
    if allow_cloud_transport:
        origin = _cloud_origin(origin)
    if _source_url(origin) != _source_url(location):
        raise CheckoutProvenanceError('Dependency origin does not match its admitted source URL.')
    return origin


def _source_tree(checkout, transforms):
    changes = _git(checkout, 'status', '--porcelain', '-z', '--untracked-files=all')
    admitted_changes = {b' M ' + os.fsencode(name) for name in transforms}
    if any(change not in admitted_changes for change in changes.split(b'\0') if change):
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
        if kind == b'commit' and mode == b'160000':
            if path.is_symlink() or (path.exists() and not path.resolve(strict=True).is_relative_to(checkout)):
                raise CheckoutProvenanceError('Dependency submodule path changed: ' + name)
            if not path.exists() or (path.is_dir() and not any(path.iterdir())):
                # A clean clone may leave documentation submodules uninitialized.
                # Such a gitlink contributes its pin, but no buildable bytes.
                files[name] = {'mode': mode.decode(), 'revision': object_id.decode(), 'initialized': False}
            else:
                files[name] = {'mode': mode.decode(), 'initialized': True,
                               **verify_source_checkout(path, object_id.decode())}
            continue
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
        original = data
        if name in transforms:
            before, after = transforms[name]
            if data not in (before, after):
                raise CheckoutProvenanceError('Dependency source differs from its admitted transform: ' + name)
            original = before
        blob = hashlib.sha1(b'blob ' + str(len(original)).encode() + b'\0' + original).hexdigest().encode()
        if blob != object_id:
            raise CheckoutProvenanceError('Dependency source differs from its pinned Git tree: ' + name)
        files[name] = {'mode': mode.decode(), 'sha256': hashlib.sha256(data).hexdigest()}
    encoded = json.dumps(files, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode()
    if not transforms.keys() <= files.keys():
        raise CheckoutProvenanceError('Dependency transform path is absent from its pinned tree.')
    return {'sourceTreeSHA256': hashlib.sha256(encoded).hexdigest(), 'trackedFileCount': len(files)}


def verify_source_checkout(source, revision, *, previous=None, transforms=None):
    """Verify actual bytes/modes against Git, with optional exact caller-admitted
    before/after byte transforms. Default callers require a clean pinned tree.
    The provenance digest always includes actual compiled bytes.
    """
    try:
        checkout = Path(source).resolve(strict=True)
        if not re.fullmatch(r'[0-9a-f]{40}', revision):
            raise CheckoutProvenanceError('Invalid admitted dependency revision.')
        if Path(_git(checkout, 'rev-parse', '--show-toplevel').decode().strip()).resolve() != checkout:
            raise CheckoutProvenanceError('Resolved checkout does not own its Git worktree.')
        if _git(checkout, 'rev-parse', 'HEAD').decode().strip() != revision:
            raise CheckoutProvenanceError('Dependency checkout HEAD does not match its pinned revision.')
        snapshot = {'revision': revision, **_source_tree(checkout, transforms or {})}
        if previous is not None and snapshot != previous:
            raise CheckoutProvenanceError('Dependency source provenance changed during the build.')
        return snapshot
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        raise CheckoutProvenanceError('Source checkout failed verification: ' + str(error)) from error


def verify_checkouts(source_packages, pins, *, previous=None, transforms=None, allow_cloud_transport=False):
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
            source = verify_source_checkout(checkout, revision, transforms=(transforms or {}).get(identity))
            origin = _verify_origin(checkout, packages, location, allow_cloud_transport)
            snapshot[identity] = {**source, 'location': location, 'originURL': origin, 'checkoutSubpath': str(subpath)}
        except (OSError, KeyError, ValueError, subprocess.CalledProcessError) as error:
            raise CheckoutProvenanceError('Dependency ' + identity + ' failed source verification: ' + str(error)) from error
    if previous is not None and snapshot != previous:
        raise CheckoutProvenanceError('Resolved dependency source provenance changed during the build.')
    return snapshot
