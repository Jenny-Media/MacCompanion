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
    assert release['targets'][target]['settings']['base']['MARKETING_VERSION'] == '1.0'
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
print('iOS 1.0 materials validated; no App Store Connect mutation performed.')
