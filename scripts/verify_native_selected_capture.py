#!/usr/bin/env python3
"""Compile and exercise selected capture lifecycle with synthetic native samples."""
from pathlib import Path
import argparse
import json
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--native-root", type=Path, help="Also check the bridge against the exact pinned Sunshine checkout")
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix="maccompanion-selected-capture-", dir="/private/tmp") as temporary:
    epoch = Path(temporary) / "native-surface-epoch-tests"
    fixture = json.loads((ROOT / "spec/fixtures/native-stream-continuity-v0.1.json").read_text())
    manifest = json.loads((ROOT / "spec/fixtures/manifest.json").read_text())
    assert sum(entry["path"] == "native-stream-continuity-v0.1.json" for entry in manifest["fixtures"]) == 1
    assert len(fixture["epochCases"]) == 11
    subprocess.run(["xcrun", "clang", "-std=c11", "-Wall", "-Wextra", "-Werror",
                    "-I" + str(ROOT / "Native/Client"),
                    str(ROOT / "Experiments/SunshineMoonlightIntegration/NativeSurfaceEpochTests.c"),
                    "-o", str(epoch)], check=True)
    subprocess.run([str(epoch), fixture["epoch"]["bytesHex"]], check=True, timeout=10)
    association = Path(temporary) / "native-epoch-association-tests"
    assert len(fixture["encoderEpochCases"]) == 6
    subprocess.run(["xcrun", "clang", "-std=c11", "-Wall", "-Wextra", "-Werror",
                    "-I" + str(ROOT / "Native/Host"),
                    str(ROOT / "Experiments/SunshineMoonlightIntegration/NativeEpochAssociationTests.c"),
                    "-o", str(association)], check=True)
    subprocess.run([str(association), fixture["epoch"]["bytesHex"]], check=True, timeout=10)
    executable = Path(temporary) / "selected-capture-tests"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-mmacosx-version-min=26.0",
                    "-Wall", "-Wextra", "-Werror", "-I" + str(ROOT / "Native/Host"),
                    str(ROOT / "Native/Host/CompanionSelectedCapture.m"),
                    str(ROOT / "Experiments/SunshineMoonlightIntegration/SelectedCaptureTests.m"),
                    "-framework", "Foundation", "-framework", "ScreenCaptureKit", "-framework", "CoreMedia",
                    "-framework", "CoreVideo", "-framework", "CoreGraphics", "-o", str(executable)], check=True)
    subprocess.run([str(executable), str(ROOT / "spec/fixtures/native-selected-capture-context-v0.1.json"),
                    str(ROOT / "spec/fixtures/native-stream-continuity-v0.1.json")], check=True, timeout=30)
    context = Path(temporary) / "selected-context-tests"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-mmacosx-version-min=26.0",
                    "-Wall", "-Wextra", "-Werror", "-I" + str(ROOT / "Native/Host"),
                    str(ROOT / "Native/Host/CompanionSelectedCaptureContext.m"),
                    str(ROOT / "Experiments/SunshineMoonlightIntegration/SelectedCaptureContextTests.m"),
                    "-framework", "Foundation", "-framework", "AppKit", "-framework", "ScreenCaptureKit",
                    "-framework", "CoreGraphics", "-framework", "ApplicationServices", "-o", str(context)], check=True)
    subprocess.run([str(context), str(ROOT / "spec/fixtures/native-selected-capture-context-v0.1.json")],
                   check=True, timeout=30)
    handoff = Path(temporary) / "selected-handoff-tests"
    handoff_object = Path(temporary) / "selected-handoff.o"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-mmacosx-version-min=26.0",
                    "-Wall", "-Wextra", "-Werror", "-Dread=CompanionHandoffReadForTest",
                    "-I" + str(ROOT / "Native/Host"), "-c",
                    str(ROOT / "Native/Host/CompanionSelectedCaptureHandoff.m"), "-o", str(handoff_object)], check=True)
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-mmacosx-version-min=26.0",
                    "-Wall", "-Wextra", "-Werror", "-I" + str(ROOT / "Native/Host"),
                    str(ROOT / "Native/Host/CompanionSelectedCaptureContext.m"),
                    str(handoff_object),
                    str(ROOT / "Experiments/SunshineMoonlightIntegration/SelectedCaptureHandoffTests.m"),
                    "-framework", "Foundation", "-framework", "AppKit", "-framework", "ScreenCaptureKit",
                    "-framework", "CoreGraphics", "-framework", "ApplicationServices", "-o", str(handoff)], check=True)
    subprocess.run([str(handoff), str(ROOT / "spec/fixtures/native-stream-continuity-v0.1.json")], check=True, timeout=15)
    if args.native_root:
        sys.path.insert(0, str(ROOT / "Experiments/SunshineMoonlightIntegration"))
        from reference_build import copy_native_depacketizer, verify_source
        upstream = verify_source(args.native_root.resolve(), "moonlight-ios")
        derived = Path(temporary) / "depacketizer"
        copy_native_depacketizer(upstream, derived)
        common = upstream / "moonlight-common/moonlight-common-c"
        assert len(fixture["depacketizerEpochCases"]) == 5
        native_parser = Path(temporary) / "depacketizer-tests"
        subprocess.run(["xcrun", "clang", "-std=c11", "-DNDEBUG", "-DHAS_SOCKLEN_T",
                        "-DMACCOMPANION_NATIVE_SURFACE_EPOCH=1", "-ffunction-sections", "-fdata-sections", "-Wl,-dead_strip",
                        "-I" + str(derived), "-I" + str(common / "src"),
                        "-I" + str(common / "enet/include"), "-I" + str(common / "reedsolomon"),
                        "-I" + str(ROOT / "Native/Client"),
                        str(ROOT / "Experiments/SunshineMoonlightIntegration/NativeDepacketizerEpochTests.c"),
                        "-o", str(native_parser)], check=True)
        subprocess.run([str(native_parser), fixture["epoch"]["bytesHex"]], check=True, timeout=10)
        sys.path.insert(0, str(ROOT / "Experiments/SunshineMoonlightIntegration"))
        from reference_build import verify_source
        source = verify_source(args.native_root.resolve(), "Sunshine") / "src/platform/macos"
        bridge = Path(temporary) / "av-video.o"
        subprocess.run(["xcrun", "clang", "-fblocks", "-mmacosx-version-min=26.0",
                        "-DMACCOMPANION_SELECTED_CAPTURE_ADAPTER=1", "-I" + str(ROOT / "Native/Host"),
                        "-c", str(source / "av_video.m"), "-o", str(bridge)], check=True)
        executable = Path(temporary) / "selected-bridge-tests"
        subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-mmacosx-version-min=26.0",
                        "-Wall", "-Wextra", "-Werror", "-DMACCOMPANION_SELECTED_CAPTURE_ADAPTER=1",
                        "-I" + str(ROOT / "Native/Host"), "-I" + str(source), str(bridge),
                        str(ROOT / "Native/Host/CompanionSelectedCapture.m"),
                        str(ROOT / "Native/Host/CompanionSelectedCaptureContext.m"),
                        str(ROOT / "Native/Host/CompanionSelectedCaptureHandoff.m"),
                        str(ROOT / "Experiments/SunshineMoonlightIntegration/SelectedCaptureBridgeTests.m"),
                        "-framework", "Foundation", "-framework", "ScreenCaptureKit", "-framework", "AVFoundation",
                        "-framework", "AppKit", "-framework", "ApplicationServices", "-framework", "CoreMedia", "-framework", "CoreVideo", "-framework", "CoreGraphics", "-o", str(executable)], check=True)
        subprocess.run([str(executable), str(ROOT / "spec/fixtures/native-stream-continuity-v0.1.json")], check=True, timeout=10)
        verify_source(args.native_root.resolve(), "Sunshine")
