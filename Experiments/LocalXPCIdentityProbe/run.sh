#!/bin/bash

set -euo pipefail

repository_root="$(cd "$(dirname "$0")/../.." && pwd)"
source_root="$repository_root/Experiments/LocalXPCIdentityProbe"
probe_root="$(mktemp -d /private/tmp/maccompanion-xpc-identity.XXXXXX)"
launch_domain="gui/$(id -u)"
launch_label="media.jenny.maccompanion.identity-probe"
service_name="media.jenny.maccompanion.identity-probe"
plist_path="$probe_root/$launch_label.plist"
agent_log="$probe_root/agent.log"
signing_identity="${MACCOMPANION_XPC_PROBE_SIGNING_IDENTITY:-Developer ID Application}"
job_loaded=0

cleanup() {
    if [[ "$job_loaded" == "1" ]]; then
        launchctl bootout "$launch_domain/$launch_label" >/dev/null 2>&1 || true
    fi
    rm -rf "$probe_root"
}
trap cleanup EXIT

clang_path="$(DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun --find clang)"
sdk_path="$(DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun --sdk macosx --show-sdk-path)"
common_flags=(
    -std=c11
    -fblocks
    -mmacosx-version-min=26.0
    -isysroot "$sdk_path"
)

"$clang_path" "${common_flags[@]}" "$source_root/agent.c" -o "$probe_root/agent"
"$clang_path" "${common_flags[@]}" "$source_root/client.c" -o "$probe_root/client-template"

cp "$probe_root/client-template" "$probe_root/good-client"
cp "$probe_root/client-template" "$probe_root/wrong-id-client"
cp "$probe_root/client-template" "$probe_root/adhoc-client"
cp "$probe_root/agent" "$probe_root/wrong-agent"

codesign --force --sign "$signing_identity" --timestamp=none --options runtime \
    --identifier media.jenny.maccompanion.agent "$probe_root/agent"
codesign --force --sign "$signing_identity" --timestamp=none --options runtime \
    --identifier media.jenny.maccompanion "$probe_root/good-client"
codesign --force --sign "$signing_identity" --timestamp=none --options runtime \
    --identifier media.jenny.maccompanion.identity-probe.wrong \
    "$probe_root/wrong-id-client"
codesign --force --sign - --options runtime \
    --identifier media.jenny.maccompanion "$probe_root/adhoc-client"
codesign --force --sign "$signing_identity" --timestamp=none --options runtime \
    --identifier media.jenny.maccompanion.agent.wrong "$probe_root/wrong-agent"

make_plist() {
    local program="$1"
    : > "$agent_log"
    plutil -create xml1 "$plist_path"
    plutil -insert Label -string "$launch_label" "$plist_path"
    plutil -insert ProgramArguments -json "[\"$program\"]" "$plist_path"
    plutil -insert MachServices -json "{\"$service_name\":true}" "$plist_path"
    plutil -insert RunAtLoad -bool true "$plist_path"
    plutil -insert ProcessType -string Background "$plist_path"
    plutil -insert StandardOutPath -string "$agent_log" "$plist_path"
    plutil -insert StandardErrorPath -string "$agent_log" "$plist_path"
}

bootstrap_agent() {
    local program="$1"
    make_plist "$program"
    launchctl bootstrap "$launch_domain" "$plist_path"
    job_loaded=1
    for _ in {1..50}; do
        if rg -q '^listener-ready$' "$agent_log"; then
            return 0
        fi
        sleep 0.1
    done
    echo "probe listener did not become ready" >&2
    return 1
}

bootout_agent() {
    launchctl bootout "$launch_domain/$launch_label"
    job_loaded=0
}

expect_success() {
    local name="$1"
    shift
    if ! "$@"; then
        echo "$name unexpectedly failed" >&2
        return 1
    fi
    echo "$name=accepted"
}

expect_failure() {
    local name="$1"
    shift
    if "$@"; then
        echo "$name unexpectedly succeeded" >&2
        return 1
    fi
    echo "$name=rejected"
}

bootstrap_agent "$probe_root/agent"
expect_success good-peer "$probe_root/good-client"
expect_failure unsupported-version \
    "$probe_root/good-client" --unsupported-version
expect_failure malformed-hello "$probe_root/good-client" --malformed
expect_failure wrong-identifier "$probe_root/wrong-id-client"
expect_failure wrong-signer "$probe_root/adhoc-client" --no-peer-requirement
bootout_agent

bootstrap_agent "$probe_root/wrong-agent"
expect_failure wrong-agent "$probe_root/good-client"
for _ in {1..30}; do
    if rg -q '^handled-constant-hello$' "$agent_log"; then
        echo "wrong-agent-received=constant-hello-only"
        break
    fi
    sleep 0.1
done
rg -q '^handled-constant-hello$' "$agent_log"

echo "local XPC identity probe passed"
