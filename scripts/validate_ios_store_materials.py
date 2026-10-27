#!/usr/bin/env python3
"""Validate local iOS 1.0 copy against Apple's field sizes; never writes to ASC."""
import json
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'docs/app-store/ios/1.0'
manifest = json.loads((BASE / 'metadata.json').read_text())
assert manifest['platform'] == 'IOS' and manifest['marketingVersion'] == '1.0'
assert manifest['locales'] == ['en-US'], 'Preserve the audited localization set'
assert manifest['primaryLocale'] in manifest['locales']
assert manifest['whatsNew'] is None, 'Initial App Store release has no What\'s New field'
assert manifest['releaseType'] == 'MANUAL'
for target in ['MacCompanionIOS', 'MacCompanionSessionActivity']:
    release = json.loads((ROOT / 'Native/iOSCloud/project.json').read_text())
    assert release['targets'][target]['settings']['base']['MARKETING_VERSION'] == '1.1'
limits = {'name': (30, False), 'subtitle': (30, False), 'description': (4000, False),
          'keywords': (100, True), 'promotional-text': (170, False), 'app-review-notes': (4000, True)}
for locale in manifest['locales']:
    for field, (limit, bytes_limit) in limits.items():
        raw = (BASE / locale / (field + '.txt')).read_text()
        assert raw.endswith('\n') and not raw.endswith('\n\n'), field
        text = raw.removesuffix('\n')  # One file terminator is not part of the pasted field.
        assert text and '\r' not in text and text == text.strip(), field
        count = len(text.encode('utf-8')) if bytes_limit else len(text)
        assert count <= limit, f'{locale}/{field}: {count} > {limit}'
        if field == 'keywords':
            terms = text.split(',')
            assert all(len(term) > 2 and term == term.strip() for term in terms)
            assert len(terms) == len(set(terms))
        print(f'{locale}/{field}: {count}/{limit} {"UTF-8 bytes" if bytes_limit else "characters"}')
for field in ['supportUrl', 'marketingUrl', 'privacyPolicyUrl']:
    assert urlsplit(manifest[field]).scheme == 'https' and urlsplit(manifest[field]).netloc
copy = json.loads((BASE / 'screenshot-copy.json').read_text())
assert copy['marketingVersion'] == '1.0' and copy['locale'] in manifest['locales']
assert copy['design'] == 'Focused'
for variant in copy['variants'].values():
    assert 1 <= len(variant['headline']) <= 2
    assert all(isinstance(line, str) and line and line == line.strip() and '\n' not in line
               for line in variant['headline'])
accepted_sizes = {
    'iphone18-pro': {(1206, 2622)}, 'iphone18': {(1320, 2868)},
    'ipad': {(2064, 2752)}, 'duo': {(2853, 2007), (2007, 2853)},
}
assert set(copy['sets']) == set(accepted_sizes)
for family, shots in copy['sets'].items():
    assert 1 <= len(shots) <= 10, family
    assert len({shot['id'] for shot in shots}) == len(shots), family
    for shot in shots:
        assert shot['copyKey'] in copy['variants'], family
        assert (shot['width'], shot['height']) in accepted_sizes[family], family
print(f'Screenshot copy: {sum(len(shots) for shots in copy["sets"].values())} ordered compositions across {len(copy["sets"])} display families validated.')
print('iOS 1.0 materials validated; no App Store Connect mutation performed.')
