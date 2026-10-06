"""Prepare the pinned package's macOS generator for Xcode's iOS plugin path.

Xcode 27 can link the tool into Debug-iphonesimulator while the package plugin
requests Debug. Compile the original pinned tool for the host, without changing
the package or replacing its generated source.
"""
import json
from pathlib import Path
import subprocess


def prepare(derived_data: Path):
    root = Path(__file__).resolve().parents[1]
    pin = json.loads((root / 'Native/Terminal/source-lock.json').read_text())['SwiftTerm']['revision']
    package = derived_data / 'SourcePackages/checkouts/SwiftTerm'
    revision = subprocess.check_output(['git', '-C', str(package), 'rev-parse', 'HEAD'], text=True).strip()
    if revision != pin or subprocess.check_output(['git', '-C', str(package), 'status', '--porcelain'], text=True).strip():
        raise RuntimeError('SwiftTerm host tool must come from its clean pinned checkout.')
    destination = derived_data / 'Build/Products/Debug/SwiftTermBuildInfoGenerator'
    destination.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['xcrun', '--sdk', 'macosx', 'swiftc', '-parse-as-library',
                    str(package / 'Sources/SwiftTermBuildInfoGenerator/BuildInfoGenerator.swift'),
                    '-o', str(destination)], check=True)
