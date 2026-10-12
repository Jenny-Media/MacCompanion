"""Prepare the pinned package's macOS generator for Xcode's iOS plugin path.

Xcode 27 can link the tool into Debug-iphonesimulator while the package plugin
requests Debug. Compile the original pinned tool for the host, without changing
the generator or replacing its generated source. Only native visionOS callers
may supply the separately hash-admitted key-release access adaptation.
"""
import json
from pathlib import Path
import subprocess


def prepare(derived_data: Path, *, transforms=None):
    root = Path(__file__).resolve().parents[1]
    pin = json.loads((root / 'Native/Terminal/source-lock.json').read_text())['SwiftTerm']['revision']
    package = derived_data / 'SourcePackages/checkouts/SwiftTerm'
    from dependency_checkout_provenance import verify_source_checkout
    verify_source_checkout(package, pin, transforms=transforms)
    destination = derived_data / 'Build/Products/Debug/SwiftTermBuildInfoGenerator'
    destination.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['xcrun', '--sdk', 'macosx', 'swiftc', '-parse-as-library',
                    str(package / 'Sources/SwiftTermBuildInfoGenerator/BuildInfoGenerator.swift'),
                    '-o', str(destination)], check=True)
