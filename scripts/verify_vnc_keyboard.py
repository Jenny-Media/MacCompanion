#!/usr/bin/env python3
"""Run the actual native keyboard against synthetic, manifest-indexed vectors."""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
fixtures = ROOT / "spec/fixtures"
manifest = json.loads((fixtures / "manifest.json").read_text())
entry = next(item for item in manifest["fixtures"]
             if item["path"] == "vnc-desktop-tunnel-v0.1.json")
assert entry["expect"] == "valid"
source = r'''
#import <Foundation/Foundation.h>
#import "CompanionVNCKeyboard.h"
#include <assert.h>
int main(int argc, const char **argv) {
    @autoreleasepool {
        assert(argc == 2);
        NSData *data = [NSData dataWithContentsOfFile:@(argv[1])];
        NSDictionary *profile = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        assert(profile != nil && [profile[@"keyboardCases"] count] > 0);
        for (NSDictionary *test in profile[@"keyboardCases"]) {
            NSMutableArray *actual = [NSMutableArray new];
            CompanionVNCKeyboard *keyboard = [[CompanionVNCKeyboard alloc] initWithEvents:^(NSArray<NSDictionary *> *events) {
                // Every admitted chord is independently balanced, including standalone keys.
                NSMutableSet *held = [NSMutableSet new];
                assert(events.count > 0 && events.count <= 10);
                for (NSDictionary *event in events) {
                    NSNumber *key = event[@"key"];
                    if ([event[@"down"] boolValue]) {
                        assert(![held containsObject:key]); [held addObject:key];
                    } else { assert([held containsObject:key]); [held removeObject:key]; }
                }
                assert(held.count == 0); [actual addObjectsFromArray:events];
            }];
            for (NSDictionary *action in test[@"actions"]) {
                NSString *kind = action[@"kind"]; uint32_t key = [action[@"key"] unsignedIntValue];
                if ([kind isEqual:@"modifier"]) [keyboard toggleModifier:key];
                else if ([kind isEqual:@"alone"]) [keyboard pressModifierAlone:key];
                else if ([kind isEqual:@"key"]) [keyboard pressKey:key];
                else if ([kind isEqual:@"reset"]) [keyboard reset];
                else if ([kind isEqual:@"text"]) {
                    NSMutableData *scalars = [NSMutableData new];
                    for (NSNumber *value in action[@"scalars"]) {
                        uint32_t scalar = CFSwapInt32HostToLittle(value.unsignedIntValue);
                        [scalars appendBytes:&scalar length:sizeof(scalar)];
                    }
                    NSString *text = [[NSString alloc] initWithData:scalars encoding:NSUTF32LittleEndianStringEncoding];
                    [keyboard text:text ?: @""];
                } else assert(0);
            }
            assert([actual isEqual:test[@"events"]]);
            assert([keyboard.armedModifiers isEqual:test[@"armed"]]);
        }
        for (NSDictionary *test in profile[@"keyboardQueueCases"]) {
            assert(CompanionVNCKeyGroupFits([test[@"queued"] unsignedIntegerValue],
                [test[@"incoming"] unsignedIntegerValue], [test[@"capacity"] unsignedIntegerValue])
                == [test[@"allowed"] boolValue]);
        }
    }
    return 0;
}
'''
with tempfile.TemporaryDirectory(prefix="maccompanion-vnc-keyboard-") as directory:
    path = Path(directory)
    (path / "test.m").write_text(source)
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror",
                    "-framework", "Foundation", "-I", str(ROOT / "Native/VNC"),
                    str(ROOT / "Native/VNC/CompanionVNCKeyboard.m"), str(path / "test.m"),
                    "-o", str(path / "test")], check=True)
    subprocess.run([str(path / "test"), str(fixtures / entry["path"])], check=True)
profile = json.loads((fixtures / entry["path"]).read_text())
print(f"VNC keyboard: {len(profile['keyboardCases'])} indexed chords and "
      f"{len(profile['keyboardQueueCases'])} atomic queue bounds passed; synthetic input only")
