"""User-facing direct-client names, independent of signing and storage identities."""
from pathlib import Path
import plistlib

APP_NAME = 'Mac Companion'
APP_BUNDLE_NAME = APP_NAME + '.app'

# Retain the pre-rename executable and Swift module names. Hosted tests and
# existing build/archive consumers must not infer these from PRODUCT_NAME.
INTERNAL_NAMES = {
    'ios': ('Mac Companion', 'Mac_Companion'),
    'macos': ('MacCompanion', 'MacCompanion'),
    'visionos': ('MacCompanionVision', 'MacCompanionVision'),
}


def configure(settings, metadata, platform):
    executable, module = INTERNAL_NAMES[platform]
    settings.update(PRODUCT_NAME=APP_NAME, EXECUTABLE_NAME=executable,
                    PRODUCT_MODULE_NAME=module)
    metadata.update(CFBundleName=APP_NAME, CFBundleDisplayName=APP_NAME)


def test_host(platform):
    executable, _ = INTERNAL_NAMES[platform]
    binary = 'Contents/MacOS/' + executable if platform == 'macos' else executable
    return '$(BUILT_PRODUCTS_DIR)/' + APP_BUNDLE_NAME + '/' + binary


def verify(app, platform):
    """Check the finished artifact, including its wrapper and executable path."""
    app = Path(app)
    executable, _ = INTERNAL_NAMES[platform]
    contents = app / 'Contents' if platform == 'macos' else app
    metadata = plistlib.loads((contents / 'Info.plist').read_bytes())
    if app.name != APP_BUNDLE_NAME:
        raise ValueError('Application bundle must be named ' + APP_BUNDLE_NAME)
    for key in ['CFBundleName', 'CFBundleDisplayName']:
        if metadata.get(key) != APP_NAME:
            raise ValueError(key + ' must be ' + APP_NAME)
    if metadata.get('CFBundleExecutable') != executable:
        raise ValueError('Application executable name changed for ' + platform)
    binary = contents / 'MacOS' / executable if platform == 'macos' else app / executable
    if not binary.is_file():
        raise ValueError('Application executable is missing: ' + str(binary))
    return {key: metadata[key] for key in ['CFBundleName', 'CFBundleDisplayName', 'CFBundleExecutable']}
