#!/usr/bin/env python3
"""Validate versioned local iOS store materials; never writes to ASC."""
import json
import hashlib
import re
import struct
import zlib
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
MATERIALS = ROOT / 'docs/app-store/ios'
release = json.loads((ROOT / 'Native/iOSCloud/project.json').read_text())
active_versions = {release['targets'][target]['settings']['base']['MARKETING_VERSION']
                   for target in ['MacCompanionIOS', 'MacCompanionSessionActivity']}
assert len(active_versions) == 1, 'App and Live Activity must use the same version'
active_version = active_versions.pop()


def version_key(value):
    assert re.fullmatch(r'\d+\.\d+(?:\.\d+)?', value), 'Expected an Apple marketing version'
    parts = tuple(map(int, value.split('.')))
    return parts + (0,) * (3 - len(parts))


version_key(active_version)
limits = {'name': (30, False), 'subtitle': (30, False), 'description': (4000, False),
          'keywords': (100, True), 'promotional-text': (170, False), 'app-review-notes': (4000, True)}
accepted_sizes = {
    'iphone18-pro': {(1206, 2622)}, 'iphone18': {(1320, 2868)},
    'ipad': {(2064, 2752)}, 'duo': {(2853, 2007), (2007, 2853)},
}


def check_text(path, limit, bytes_limit=False):
    raw = path.read_text()
    assert raw.endswith('\n') and not raw.endswith('\n\n'), path
    text = raw.removesuffix('\n')  # The file terminator is not part of the pasted field.
    assert text and '\r' not in text and text == text.strip(), path
    count = len(text.encode('utf-8')) if bytes_limit else len(text)
    assert count <= limit, f'{path}: {count} > {limit}'
    print(f'{path.relative_to(MATERIALS)}: {count}/{limit} {"UTF-8 bytes" if bytes_limit else "characters"}')
    return text


def jpeg_dimensions(data):
    """Read final JPEG frame dimensions without an optional imaging dependency."""
    assert data.startswith(b'\xff\xd8') and data.endswith(b'\xff\xd9'), 'Invalid JPEG boundaries'
    offset, dimensions = 2, None
    while offset < len(data):
        assert data[offset] == 0xff, 'Invalid JPEG marker'
        while data[offset] == 0xff:
            offset += 1
        marker = data[offset]
        offset += 1
        if marker in [0xda, 0xd9]:  # Image data starts after the header segments.
            break
        length = int.from_bytes(data[offset:offset + 2], 'big')
        assert length >= 2 and offset + length <= len(data), 'Invalid JPEG segment'
        payload = data[offset + 2:offset + length]
        assert marker not in [0xe1, 0xfe], 'Final artwork must not contain EXIF/XMP or comments'
        if marker in [0xc0, 0xc2]:
            assert len(payload) >= 6 and payload[0] == 8 and payload[5] == 3, 'Expected an 8-bit color JPEG'
            dimensions = (int.from_bytes(payload[3:5], 'big'), int.from_bytes(payload[1:3], 'big'))
        offset += length
    assert dimensions is not None, 'Missing JPEG frame'
    return dimensions


def png_dimensions(data):
    """Check the actual creative encoding and exclude private text/EXIF metadata."""
    assert data.startswith(b'\x89PNG\r\n\x1a\n'), 'Expected an encoded PNG creative'
    offset, dimensions, profile = 8, None, False
    while offset < len(data):
        assert offset + 12 <= len(data), 'Truncated PNG chunk'
        length = int.from_bytes(data[offset:offset + 4], 'big')
        kind = data[offset + 4:offset + 8]
        end = offset + 12 + length
        assert end <= len(data), 'Truncated PNG payload'
        payload = data[offset + 8:end - 4]
        assert zlib.crc32(kind + payload) == int.from_bytes(data[end - 4:end], 'big'), 'PNG CRC mismatch'
        assert kind not in [b'eXIf', b'tEXt', b'iTXt', b'zTXt'], 'Private PNG metadata is excluded'
        if kind == b'IHDR':
            assert dimensions is None and offset == 8 and length == 13
            width, height, depth, color, compression, filtering, interlace = struct.unpack('>IIBBBBB', payload)
            assert (depth, color, compression, filtering, interlace) == (8, 2, 0, 0, 0), 'Expected opaque 8-bit RGB'
            dimensions = (width, height)
        elif kind == b'iCCP':
            _, encoded = payload.split(b'\0', 1)
            assert encoded[0] == 0 and zlib.decompress(encoded[1:])[36:40] == b'acsp', 'Invalid ICC profile'
            profile = True
        elif kind == b'sRGB':
            profile = True
        offset = end
        if kind == b'IEND':
            assert length == 0 and offset == len(data), 'Unexpected trailing PNG content'
            break
    assert kind == b'IEND' and dimensions is not None and profile, 'Incomplete or unprofiled PNG'
    return dimensions


def check_artwork(base, manifest, copy):
    artwork = json.loads((base / manifest['screenshotManifest']).read_text())
    assert artwork['schemaVersion'] == 1 and artwork['platform'] == 'IOS'
    assert artwork['marketingVersion'] == base.name and artwork['locale'] in manifest['locales']
    assert artwork['candidateBuild'] == manifest['candidateBuild']
    assert artwork['candidateSource'] == manifest['baseRevision']
    assert artwork['candidateTree'] == manifest['candidateTree']
    assert artwork['reviewedReleaseArtwork'] is True and artwork['publicOrSyntheticDemoContentOnly'] is True
    assert artwork['rawCapturesIncluded'] is False and artwork['logsIncluded'] is False
    expected = [(family, shot) for family, shots in copy['sets'].items() for shot in shots]
    assert len(artwork['exports']) == len(expected)
    paths, reused = set(), 0
    for image, (family, shot) in zip(artwork['exports'], expected):
        assert image['id'] == family + '-' + shot['id'] and image['displayFamily'] == family
        assert image['locale'] == artwork['locale'] and image['copyKey'] == shot['copyKey']
        assert image['headline'] == copy['variants'][shot['copyKey']]['headline']
        relative = Path('screenshots') / image['locale'] / family / (shot['id'] + '.jpg')
        assert image['path'] == relative.as_posix(), 'Only selected final export paths are allowed'
        path = base / relative
        assert not path.is_symlink() and path.resolve().is_relative_to((base / 'screenshots').resolve())
        data = path.read_bytes()
        assert path not in paths and len(data) == image['bytes']
        assert hashlib.sha256(data).hexdigest() == image['sha256'], f'Artwork hash mismatch: {relative}'
        assert jpeg_dimensions(data) == (image['width'], image['height']) == (shot['width'], shot['height'])
        origin = image['source']
        assert len(origin['rawCaptureSHA256']) == 64
        assert origin['physicalAcceptance'] is False and origin['realICloudDeliveryExercised'] is False
        if origin['kind'] == 'reused-approved-v10-byte-identical':
            assert origin['sourceMaterialVersion'] == '1.0' and origin['notRecapturedFromBuild167'] is True
            reused += 1
        else:
            assert origin['kind'] == 'new-native-shipping-view-capture'
            assert origin['sourceCommit'] == manifest['baseRevision']
            assert origin['simulatorOnlyHarness'] is True and origin['shippingViewsUnmodified'] is True
        paths.add(path)
    assert reused == artwork['reusedCount'] and len(paths) - reused == artwork['newCount']
    print(f'iOS {base.name}: {len(paths)} reviewed final JPEGs verified by path, SHA-256 and encoded dimensions.')
    creatives = artwork.get('creativeAssets', [])
    if manifest.get('artifactRole') == 'released-version-archive':
        assert {image['id'] for image in creatives} == {
            'main-header-universal', 'main-search-universal',
            'desktop-header-universal', 'desktop-search-universal'}
        assert len(creatives) == 4
    for image in creatives:
        relative = Path(image['path'])
        assert relative.parent == Path('screenshots/en-US/creatives') and relative.suffix == '.png'
        path = base / relative
        assert not path.is_symlink() and path.resolve().is_relative_to((base / 'screenshots').resolve())
        data = path.read_bytes()
        assert path not in paths and len(data) == image['bytes']
        assert hashlib.sha256(data).hexdigest() == image['sha256'], f'Creative hash mismatch: {relative}'
        assert png_dimensions(data) == (image['width'], image['height']) == (5244, 2950)
        assert image['encodedFormat'] == 'PNG' and image['colorMode'] == 'RGB' and image['colorProfile'] == 'sRGB'
        source = image['source']
        assert source['kind'] == 'reviewed-native-grid-creative-reuse'
        assert source['nativePixelsRepainted'] is False and source['nativeScreenUniformScale'] is True
        assert len(source['sourceTemplateSHA256']) == 64
        assert image['submissionId'] == manifest['releaseState']['submissionId']
        paths.add(path)
    assert paths == {path for path in (base / 'screenshots').rglob('*') if path.is_file()}, 'Unlisted artwork files'
    print(f'iOS {base.name}: {len(creatives)} reviewed Header/Search PNGs verified separately from screenshots.')


for metadata in sorted(MATERIALS.glob('*/metadata.json')):
    base = metadata.parent
    manifest = json.loads(metadata.read_text())
    assert manifest['platform'] == 'IOS' and manifest['marketingVersion'] == base.name
    assert manifest['locales'] == ['en-US'], 'Preserve the audited localization set'
    assert manifest['primaryLocale'] in manifest['locales']
    assert manifest['releaseType'] == 'MANUAL'
    if base.name in ['1.0', '1.1']:
        assert manifest['whatsNew'] is None, 'Do not populate an initial-release-only record with update copy'
    if manifest.get('whatsNewDraft'):
        draft = (base / manifest['whatsNewDraft']).resolve()
        assert draft.is_relative_to(base.resolve()), 'Draft must remain inside its version materials'
        check_text(draft, 4000)
    if base.name == '1.1':
        if manifest.get('artifactRole') == 'released-version-archive':
            assert manifest['preparationOnly'] is False
            state = manifest['releaseState']
            assert state['appStoreStatus'] == 'READY_FOR_DISTRIBUTION' and state['reviewStatus'] == 'REVIEW_COMPLETED'
            assert state['build'] == manifest['candidateBuild'] and state['approvedItemCount'] == 6
            assert version_key(active_version) > version_key(manifest['marketingVersion']), 'Next uploads need a higher version'
        else:
            assert manifest['preparationOnly'] is True
        assert manifest['productionMutationAuthorized'] is False and manifest['submissionAuthorized'] is False
        assert manifest['candidateBuild'].isdigit()
        assert len(manifest['baseRevision']) == 40 and len(manifest['candidateTree']) == 40
        assert manifest['screenshotManifest'] == 'artwork-manifest.json'
    for locale in manifest['locales']:
        for field, (limit, bytes_limit) in limits.items():
            text = check_text(base / locale / (field + '.txt'), limit, bytes_limit)
            if field == 'keywords':
                terms = text.split(',')
                assert all(len(term) > 2 and term == term.strip() for term in terms)
                assert len(terms) == len(set(terms))
    for field in ['supportUrl', 'marketingUrl', 'privacyPolicyUrl']:
        assert urlsplit(manifest[field]).scheme == 'https' and urlsplit(manifest[field]).netloc
    copy = json.loads((base / 'screenshot-copy.json').read_text())
    assert copy['marketingVersion'] == base.name and copy['locale'] in manifest['locales']
    assert copy['design'] == 'Focused'
    for variant in copy['variants'].values():
        assert 1 <= len(variant['headline']) <= 2
        assert all(isinstance(line, str) and line and line == line.strip() and '\n' not in line
                   for line in variant['headline'])
    assert set(copy['sets']) == set(accepted_sizes)
    for family, shots in copy['sets'].items():
        assert 1 <= len(shots) <= 10, family
        assert len({shot['id'] for shot in shots}) == len(shots), family
        for shot in shots:
            assert shot['copyKey'] in copy['variants'], family
            assert (shot['width'], shot['height']) in accepted_sizes[family], family
    print(f'iOS {base.name}: {sum(len(shots) for shots in copy["sets"].values())} screenshot compositions across {len(copy["sets"])} display families validated.')
    if base.name == '1.1':
        check_artwork(base, manifest, copy)
print('Local iOS materials validated; no App Store Connect mutation performed.')
