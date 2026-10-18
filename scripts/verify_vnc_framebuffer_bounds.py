#!/usr/bin/env python3
"""Exercise the native allocation guard using the authoritative fixture index."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
fixtures = ROOT / "spec/fixtures"
manifest = json.loads((fixtures / "manifest.json").read_text())
entry = next(item for item in manifest["fixtures"]
             if item["path"] == "vnc-desktop-tunnel-v0.1.json")
assert entry["expect"] == "valid"
profile = json.loads((fixtures / entry["path"]).read_text())
limits = profile["framebufferLimits"]
checks = []
for case in profile["framebufferCases"]:
    width, height, allowed = case["width"], case["height"], case["allowed"]
    expected = (0 < width <= limits["maximumDimension"]
                and 0 < height <= limits["maximumDimension"]
                and width * height * 4 <= limits["maximumBytes"])
    assert expected == allowed
    checks.append(f"assert(CompanionVNCFramebufferByteCount({width}, {height}, &bytes) == {str(allowed).lower()});")
    if allowed:
        checks.append(f"assert(bytes == UINT64_C({width * height * 4}));")
    else:
        checks.append("assert(bytes == 17);")
    checks.append("bytes = 17;")
input_entry = next(item for item in manifest["fixtures"] if item["path"] == "direct-screen-sharing-v1.json")
assert input_entry["expect"] == "valid"
input_profile = json.loads((fixtures / input_entry["path"]).read_text())
policy = input_profile["inputOnlyInitializationPolicy"]
assert policy["geometryMaximum"] == 65535
assert not any(policy[key] for key in ["initialFramebufferRequest", "framebufferAllocation", "coverageAllocation"])
assert policy["unsolicitedPixelsWithoutStorage"] == "reject-before-decoding"
for case in input_profile["inputOnlyInitializationCases"]:
    width, height = case["width"], case["height"]
    assert case["inputGeometryValid"] == (0 < width <= 65535 and 0 < height <= 65535)
    checks.append(f"assert(CompanionVNCInputGeometryValid({width}, {height}) == {str(case['inputGeometryValid']).lower()});")
    checks.append(f"assert(CompanionVNCFramebufferByteCount({width}, {height}, &bytes) == {str(case['videoAdmitted']).lower()});")
source = '\n'.join([
    '#include <assert.h>', '#include "CompanionVNCFramebufferBounds.h"',
    'int main(void) { size_t bytes = 17;', *checks, 'return 0; }',
])
compiler = shutil.which("cc")
if not compiler:
    raise SystemExit("A C compiler is required for the VNC allocation regression.")
with tempfile.TemporaryDirectory(prefix="maccompanion-vnc-bounds-") as directory:
    path = Path(directory)
    (path / "test.c").write_text(source)
    subprocess.run([compiler, "-std=c11", "-Wall", "-Wextra", "-Werror",
                    "-I", str(ROOT / "Native/VNC"), str(path / "test.c"),
                    "-o", str(path / "test")], check=True)
    subprocess.run([str(path / "test")], check=True)
print(f"VNC bounds: {len(profile['framebufferCases'])} framebuffer and {len(input_profile['inputOnlyInitializationCases'])} independent input-only indexed cases passed")
