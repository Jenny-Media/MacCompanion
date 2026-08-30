#!/bin/bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repository_root"
export DEVELOPER_DIR="${MACCOMPANION_DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
lab_simulator="${MACCOMPANION_SIMULATOR_ID:-}"
if [[ -z "$lab_simulator" ]]; then
    lab_simulator="$(xcrun simctl list devices booted --json | python3 -c 'import json,sys; devices=[d for runtime,items in json.load(sys.stdin)["devices"].items() if ".iOS-" in runtime for d in items if d["state"] == "Booted"]; devices.sort(key=lambda d: "iPhone" not in d["name"]); print(devices[0]["udid"] if devices else "")')"
fi
lab_derived="${MACCOMPANION_LAB_DERIVED_DATA:-/private/tmp/maccompanion-live-lab-build}"
lab_run="$(mktemp -d /private/tmp/maccompanion-feature-tests.XXXXXX)"
lab_host_pid=""
lab_container=""
lab_lock=""
lab_source="${MACCOMPANION_LAB_SOURCE:-generated}"
[[ "$lab_source" == generated || "$lab_source" == real-mac-window ]] || { echo "Invalid lab source" >&2; exit 2; }
lab_suite="${MACCOMPANION_LAB_SUITE:-full}"
lab_iterations="${MACCOMPANION_LAB_ITERATIONS:-1}"
if [[ ${MACCOMPANION_LAB_ONLY_LIVE:-0} == 1 ]]; then lab_suite=live; fi
case "$lab_suite" in full|live|soak|reconnect|lifecycle|semantic|integration|journey|journey-observe|journey-renewal) ;; *) echo "Invalid lab suite" >&2; exit 2 ;; esac
if [[ "$lab_suite" == journey* || "$lab_suite" == full ]]; then export MACCOMPANION_LAB_JOURNEY=1; fi
stop_lab_process() {
    local lab_stop_pid=$1
    local lab_stop_attempts=$2
    kill "$lab_stop_pid" 2>/dev/null || true
    for ((lab_stop_attempt=0; lab_stop_attempt<lab_stop_attempts; lab_stop_attempt++)); do
        if ! kill -0 "$lab_stop_pid" 2>/dev/null; then break; fi
        sleep 0.1
    done
    if kill -0 "$lab_stop_pid" 2>/dev/null; then kill -KILL "$lab_stop_pid" 2>/dev/null || true; fi
    wait "$lab_stop_pid" 2>/dev/null || true
}
cleanup() {
    local lab_exit_code=$?
    local lab_current_container=""
    if [[ -n "$lab_host_pid" ]]; then stop_lab_process "$lab_host_pid" 60; fi
    if [[ -n "$lab_container" ]]; then
        xcrun simctl terminate "$lab_simulator" dev.maccompanion.clientuiharness >/dev/null 2>&1 || true
        # XCTest can relocate the installed app's data container. Retire both
        # the original installation path and the current authoritative path.
        lab_current_container="$(xcrun simctl get_app_container "$lab_simulator" dev.maccompanion.clientuiharness data 2>/dev/null || true)"
        if [[ -f "$lab_container/Documents/lab-fixture.json" ]]; then
            rm "$lab_container/Documents/lab-fixture.json" || lab_exit_code=1
        fi
        if [[ -n "$lab_current_container" ]]; then
            rm -f "$lab_current_container/Documents/lab-fixture.json" || lab_exit_code=1
        else
            echo "Could not confirm current Simulator bootstrap cleanup" >&2
            lab_exit_code=1
        fi
        # Exact disposable harness directories only; never touch a production
        # app container or a user-selected root. These hold software test keys.
        for lab_owned_container in "$lab_container" "$lab_current_container"; do
            if [[ -n "$lab_owned_container" && -d "$lab_owned_container/Documents/journey-tests" ]]; then
                rm -r -- "$lab_owned_container/Documents/journey-tests" || lab_exit_code=1
            fi
        done
    fi
    rm -f "$lab_run/fixture.json" || lab_exit_code=1
    if [[ -d "$lab_run/journey" ]]; then rm -r -- "$lab_run/journey" || lab_exit_code=1; fi
    if [[ -n "$lab_lock" ]]; then rmdir "$lab_lock" || lab_exit_code=1; fi
    if ! python3 scripts/report_simulator_run.py "$lab_run" "$lab_suite" "$lab_source" "$lab_exit_code" "$lab_iterations"; then
        if [[ "$lab_exit_code" == 0 ]]; then lab_exit_code=1; fi
    fi
    echo "Evidence: $lab_run"
    exit "$lab_exit_code"
}
trap cleanup EXIT
echo "Evidence: $lab_run"
echo "Simulator-only suite: $lab_suite; source: $lab_source"
python3 scripts/validate_live_control_lab.py

# Never erase, reset, or change the user's Simulator; require a booted device.
[[ -n "$lab_simulator" ]] && xcrun simctl list devices booted | rg -q -F "$lab_simulator" || {
    echo "Boot the selected Simulator or set MACCOMPANION_SIMULATOR_ID." >&2; exit 2;
}
[[ "$lab_simulator" =~ ^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$ ]] || {
    echo "Invalid Simulator UUID" >&2; exit 2;
}
# Keep the lease through pairing regressions and fixture cleanup. Starting a
# second runner early must not let the first runner erase its new bootstrap.
lab_requested_lock="/private/tmp/maccompanion-simulator-$lab_simulator.lock"
mkdir "$lab_requested_lock" 2>/dev/null || {
    echo "Another runner owns this Simulator (or a stale lock needs inspection): $lab_requested_lock" >&2; exit 2;
}
lab_lock="$lab_requested_lock"
swift build --package-path Experiments/LiveControlLab > "$lab_run/host-build.log" 2>&1
lab_bin="$(swift build --package-path Experiments/LiveControlLab --show-bin-path)"
lab_host_args=("$lab_run/fixture.json")
lab_host_executable="$lab_bin/maccompanion-test-host"
if [[ "$lab_source" == real-mac-window ]]; then
    lab_mac_app="$lab_derived/Mac Companion Real Mac Lab.app"
    mkdir -p "$lab_mac_app/Contents/MacOS"
    cp Experiments/LiveControlLab/Info.plist "$lab_mac_app/Contents/Info.plist"
    cp "$lab_bin/maccompanion-test-host" "$lab_mac_app/Contents/MacOS/maccompanion-test-host"
    codesign --force --sign "${MACCOMPANION_LAB_SIGNING_IDENTITY:-Apple Development}" "$lab_mac_app" > "$lab_run/host-signing.log" 2>&1
    codesign --verify --deep --strict "$lab_mac_app" >> "$lab_run/host-signing.log" 2>&1
    lab_host_executable="$lab_mac_app/Contents/MacOS/maccompanion-test-host"
    lab_host_args+=(--real-mac)
fi
# Supervise only our disposable child. A requested restart must create a new
# process/main thread, including in the AppKit lane. Killing this supervisor
# also terminates and reaps its current child; no orphan survives cleanup.
# The background function is already a subshell. An additional `( ... )`
# would make $! point at an outer wrapper, orphaning the real supervisor.
run_lab_host() {
    lab_child_pid=""
    trap 'if [[ -n "$lab_child_pid" ]]; then stop_lab_process "$lab_child_pid" 20; fi' EXIT
    trap 'exit 143' TERM INT
    for ((lab_restart=0; lab_restart<32; lab_restart++)); do
        "$lab_host_executable" "${lab_host_args[@]}" &
        lab_child_pid=$!
        lab_child_result=0
        wait "$lab_child_pid" || lab_child_result=$?
        lab_child_pid=""
        if [[ "$lab_child_result" != 75 ]]; then exit "$lab_child_result"; fi
        export MACCOMPANION_LAB_RESUME=1
    done
    echo "Test host restart limit exceeded" >&2
    exit 1
}
run_lab_host > "$lab_run/host.log" 2>&1 &
lab_host_pid=$!
for ((attempt=0; attempt<100; attempt++)); do
    [[ -s "$lab_run/fixture.json" ]] && break
    if ! kill -0 "$lab_host_pid" 2>/dev/null; then
        lab_host_result=0
        wait "$lab_host_pid" || lab_host_result=$?
        lab_host_pid=""
        if [[ "$lab_host_result" == 77 ]]; then
            echo "REAL_MAC_BLOCKED: allow Screen Recording and Accessibility for $lab_mac_app, then rerun. No permissions were changed." >&2
            exit 77
        fi
        echo "Test host stopped; see $lab_run/host.log" >&2; exit 1
    fi
    sleep 0.1
done
[[ -s "$lab_run/fixture.json" ]] || { echo "Test host readiness timed out" >&2; exit 1; }
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["source"] == sys.argv[2], "Wrong test source"' "$lab_run/fixture.json" "$lab_source"
xcodebuild build-for-testing -project Experiments/ClientUIHarness/ClientUIHarness.xcodeproj \
    -scheme ClientUIHarness -configuration Debug -destination "platform=iOS Simulator,id=$lab_simulator" \
    -derivedDataPath "$lab_derived" CODE_SIGNING_ALLOWED=NO > "$lab_run/simulator-build.log" 2>&1
xcrun simctl install "$lab_simulator" "$lab_derived/Build/Products/Debug-iphonesimulator/ClientUIHarness.app"
lab_container="$(xcrun simctl get_app_container "$lab_simulator" dev.maccompanion.clientuiharness data)"
mkdir -p "$lab_container/Documents"
cp "$lab_run/fixture.json" "$lab_container/Documents/lab-fixture.json"
chmod 600 "$lab_container/Documents/lab-fixture.json"

lab_test_selection=(-parallel-testing-enabled NO)
if [[ ! "$lab_iterations" =~ ^[1-9][0-9]*$ ]]; then
    echo "MACCOMPANION_LAB_ITERATIONS must be a positive integer" >&2; exit 2
fi
if ((lab_iterations > 1)); then
    lab_test_selection+=(-test-iterations "$lab_iterations")
fi
case "$lab_suite" in
    full) lab_test_selection+=(-only-testing:ClientUIHarnessUITests/ClientUIHarnessUITests) ;;
    journey-renewal) lab_test_selection+=(-only-testing:ClientUIHarnessUITests/ClientUIHarnessUITests/testAuthenticatedAgentRenewalFailureRecovery) ;;
    journey-observe) lab_test_selection+=(-only-testing:ClientUIHarnessUITests/ClientUIHarnessUITests/testAuthenticatedObserveAcrossReopens) ;;
    journey) lab_test_selection+=(-only-testing:ClientUIHarnessUITests/ClientUIHarnessUITests/testAuthenticatedPairingRestartRecoveryAndRevocation) ;;
    integration) lab_test_selection+=(-only-testing:ClientUIHarnessUITests/ClientUIHarnessUITests/testIntegratedControlBackgroundRecovery -only-testing:ClientUIHarnessUITests/ClientUIHarnessUITests/testIntegratedControlNetworkLossAndCancelledDial -only-testing:ClientUIHarnessUITests/ClientUIHarnessUITests/testRetiredControlCallbacksCannotCorruptReplacement) ;;
    live) lab_test_selection+=(-only-testing:ClientUIHarnessUITests/ClientUIHarnessUITests/testNetworkControlLabStreamingZoomKeyboardReconnect) ;;
    soak) lab_test_selection+=(-only-testing:ClientUIHarnessUITests/ClientUIHarnessUITests/testNetworkControlLabIdleSoak) ;;
    reconnect) lab_test_selection+=(-only-testing:ClientUIHarnessUITests/ClientUIHarnessUITests/testNetworkControlLabRepeatedStopDropReconnect) ;;
    lifecycle) lab_test_selection+=(-only-testing:ClientUIHarnessUITests/ClientUIHarnessUITests/testLifecycleUsesInjectedReachabilityAndRearmsAfterBackground) ;;
    semantic) lab_test_selection+=(-only-testing:ClientUIHarnessUITests/ClientUIHarnessUITests/testLiveControlKeyboardAndStopAreSemanticallyReachable) ;;
esac
xcodebuild test-without-building -project Experiments/ClientUIHarness/ClientUIHarness.xcodeproj \
    -scheme ClientUIHarness -configuration Debug -destination "platform=iOS Simulator,id=$lab_simulator" \
    -derivedDataPath "$lab_derived" -resultBundlePath "$lab_run/features.xcresult" \
    -test-timeouts-enabled YES -maximum-test-execution-time-allowance 360 \
    "${lab_test_selection[@]}" CODE_SIGNING_ALLOWED=NO > "$lab_run/features.log" 2>&1
echo "SIMULATOR_FEATURES_PASSED"
zsh scripts/verify_pairing_reliability.sh > "$lab_run/pairing.log" 2>&1
if rg -q 'Some test targets (reported failures|did not run successfully)|✘ Test|Test run with .* failed after' "$lab_run/pairing.log"; then
    echo "Pairing tests reported a failure despite the process exit status." >&2
    exit 1
fi
echo "PAIRING_REGRESSIONS_PASSED"
