"""Authorize local Mac development signing from an existing installed profile.

No registration, profile download, certificate creation or release admission.
Profiles and generated entitlements remain outside the repository.
"""
from datetime import datetime, timezone
import hashlib
import plistlib
import subprocess


def configure(settings, *, identity, team, profile_path, output, bundle, sync_group=None):
    profile = plistlib.loads(subprocess.check_output(['security', 'cms', '-D', '-i', str(profile_path)]))
    claims = profile['Entitlements']
    application = team + '.' + bundle
    groups = [application] + ([sync_group] if sync_group else [])
    allowed_app = claims.get('com.apple.application-identifier', claims.get('application-identifier', ''))
    certificates = [hashlib.sha1(der).hexdigest().upper() for der in profile['DeveloperCertificates']]
    def permitted(group):
        return group in claims.get('keychain-access-groups', []) or team + '.*' in claims.get('keychain-access-groups', [])
    if (profile.get('Platform') != ['OSX'] or profile['TeamIdentifier'] != [team]
            or allowed_app not in [application, team + '.*'] or identity.upper() not in certificates
            or profile['ExpirationDate'].replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc)
            or not all(permitted(group) for group in groups)):
        raise ValueError('The installed Mac profile must authorize the identity, team, existing app and requested Keychain groups.')
    entitlements = output / 'MacDevelopment.entitlements'
    entitlements.write_bytes(plistlib.dumps({'com.apple.application-identifier': application,
        'com.apple.developer.team-identifier': team, 'keychain-access-groups': groups}))
    settings.update({'CODE_SIGNING_ALLOWED': 'YES', 'CODE_SIGN_IDENTITY': identity, 'DEVELOPMENT_TEAM': team,
                     'CODE_SIGN_ENTITLEMENTS': str(entitlements), 'CODE_SIGN_INJECT_BASE_ENTITLEMENTS': 'NO'})
    if profile.get('IsXcodeManaged'):
        settings.update({'CODE_SIGN_STYLE': 'Automatic', 'CODE_SIGN_IDENTITY': 'Apple Development'})
        settings.pop('PROVISIONING_PROFILE_SPECIFIER', None)
    else:
        settings.update({'CODE_SIGN_STYLE': 'Manual', 'PROVISIONING_PROFILE_SPECIFIER': profile['UUID']})
    return {'profileUUID': profile['UUID'], 'profileSHA256': hashlib.sha256(profile_path.read_bytes()).hexdigest(),
            'leafSHA1': identity.upper(), 'team': team, 'application': application, 'groups': groups}


def verify(app, admission, output):
    subprocess.run(['codesign', '--verify', '--strict', '--deep', str(app)], check=True)
    prefix = output / 'verification-leaf-'
    subprocess.run(['codesign', '--display', '--extract-certificates=' + str(prefix), str(app)], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    leaf = output / 'verification-leaf-0'
    try:
        if hashlib.sha1(leaf.read_bytes()).hexdigest().upper() != admission['leafSHA1']:
            raise ValueError('Xcode selected a different signing certificate than the admitted development identity.')
    finally:
        for path in output.glob('verification-leaf-*'): path.unlink()
    result = subprocess.run(['codesign', '--display', '--entitlements', '-', '--xml', str(app)], capture_output=True, check=True)
    claims = plistlib.loads(result.stdout)
    if (claims.get('com.apple.application-identifier') != admission['application']
            or claims.get('com.apple.developer.team-identifier') != admission['team']
            or claims.get('keychain-access-groups') != admission['groups']):
        raise ValueError('The signed development app does not carry its admitted Keychain scopes.')
