#!/usr/bin/env python3
"""Keep test approval/bootstrap code out of the production source graph."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
production = [root / "MacCompanion.xcodeproj/project.pbxproj"]
for directory in ("Apps", "Packages"):
    production.extend(path for path in (root / directory).rglob("*.swift")
                      if ".build" not in path.parts and "Tests" not in path.parts)
for path in production:
    text = path.read_text()
    for marker in ("LiveControlLab", "LabApprovalSigner", "--network-control-lab", "--integrated-control-lab", "IntegratedLab", "lab-fixture.json", "AuthenticatedJourney", "JourneySoftwareCustody", "--authenticated-journey"):
        assert marker not in text, f"Test-only dependency in {path.relative_to(root)}: {marker}"

host = (root / "Experiments/LiveControlLab/Sources/LiveControlTestHost/main.swift").read_text()
client = (root / "Experiments/ClientUIHarness/ClientUIHarness/NetworkControlLabView.swift").read_text()
assert '#if !DEBUG\n#error(' in host, "Host must reject Release builds"
assert '#if !DEBUG || !targetEnvironment(simulator)\n#error(' in client
assert 'requiredLocalEndpoint = .hostPort(host: "127.0.0.1"' in host
assert "guard hello.token == fixture.token" in host
assert "isValidSignature" in host
assert 'try await runtime.invalidateAgentAuthority()' in host, 'Lab teardown must close production runtime authority before purging'
for name in ("NetworkClientPrimaryRouterBridgeV0", "NetworkClientPrimaryProductCandidateV0"):
    source = (root / "Packages/MacCompanionKit/Sources/CompanionClientNetworkPlatform" / (name + ".swift")).read_text()
    seam = source.index("package func bindAuthenticatedTransport(")
    debug_start = source.rfind("#if DEBUG", 0, seam)
    assert debug_start >= 0 and "#endif" not in source[debug_start:seam], 'Seeded authenticated transport must not exist in Release'
assert "CGEvent" not in host and "SCStream" not in host, "Generated lane must not affect the desktop"
real = (root / "Experiments/LiveControlLab/Sources/LiveControlTestHost/RealMacTarget.swift").read_text()
assert '#if !DEBUG\n#error(' in real
assert 'event.postToPid(getpid())' in real
assert '.post(tap:' not in real and 'CGEventPost(' not in real
assert 'SCContentFilter(desktopIndependentWindow: owned)' in real
assert '$0.owningApplication?.processID == getpid()' in real
assert 'CGPreflightScreenCaptureAccess()' in real and 'CGPreflightPostEventAccess()' in real
assert 'CGRequest' not in real, 'Permission prompts require a separate human action'
assert 'args[2] == "--real-mac"' in host
journey_host = (root / "Experiments/LiveControlLab/Sources/LiveControlTestHost/AuthenticatedJourneyHost.swift").read_text()
journey_client = (root / "Experiments/ClientUIHarness/ClientUIHarness/AuthenticatedJourneyView.swift").read_text()
assert '#if !DEBUG\n#error(' in journey_host
assert '#if !DEBUG || !targetEnvironment(simulator)\n#error(' in journey_client
assert 'bindAuthenticatedTransport' not in journey_client, 'Journey must use the production TLS/authentication connector'
assert 'NetworkClientPairingApplicationCompositionV0.makeOwner' in journey_client
assert 'NetworkClientConfiguredRouteApplicationProductFactoryV1.make' in journey_client
assert 'SecItemAdd' not in journey_host and 'prepareKey(' not in journey_host, 'Journey must not mutate host Keychain'
renewal_source = (root / 'Packages/MacCompanionKit/Sources/CompanionAgent/AgentInteractiveLeaseRenewalOwnerV1.swift').read_text()
renewal_seam = renewal_source.index('func startForInstalledTestRuntime(')
renewal_debug = renewal_source.rfind('#if DEBUG', 0, renewal_seam)
assert renewal_debug >= 0 and '#endif' not in renewal_source[renewal_debug:renewal_seam]
assert 'AgentInteractiveLeaseRenewalOwnerV1(runtime: LabAgentLeaseRuntime(session: self))' in host
journey_transport = (root / 'Experiments/LiveControlLab/Sources/LiveControlTestHost/JourneyInteractiveTransport.swift').read_text()
assert 'usesAgentRenewal: true' in journey_transport
tls_source = (root / 'Packages/MacCompanionKit/Sources/CompanionNetworkPlatform/NetworkHostTLSListenerConfigurationV0.swift').read_text()
loopback = tls_source.index('func makeUnstartedLoopbackListener(')
debug_start = tls_source.rfind('#if DEBUG', 0, loopback)
assert debug_start >= 0 and '#endif' not in tls_source[debug_start:loopback]
assert 'requiredLocalEndpoint = .hostPort(host: "127.0.0.1"' in tls_source[loopback:]
assert 'listener.service =' not in tls_source[loopback:], 'Loopback test listener must never advertise on LAN'
runner = (root / "scripts/verify_simulator_features.sh").read_text()
assert 'platform=iOS Simulator,id=' in runner
assert 'devicectl' not in runner and 'generic/platform=iOS' not in runner, 'This runner must never target a physical iPhone'
assert 'run_lab_host() {' in runner and 'run_lab_host() (' not in runner
assert 'stop_lab_process "$lab_child_pid" 20' in runner
assert 'wait "$lab_child_pid"' in runner and 'MACCOMPANION_LAB_RESUME=1' in runner
signed_runner = (root / "scripts/verify_signed_simulator.py").read_text()
signed_menu = (root / "Experiments/LiveControlLab/Sources/AgentXPCTest/ProbeSimulatorMenu.swift").read_text()
assert "MACCOMPANION_SIMULATOR_ID" in signed_runner and '"xcrun", "simctl"' in signed_runner
assert "devicectl" not in signed_runner and "generic/platform=iOS" not in signed_runner
assert '"-only-testing:ClientUIHarnessUITests/SignedAgentJourneyUITests/' in signed_runner
assert 'BUNDLE = "dev.maccompanion.clientuiharness"' in signed_runner
assert "production Keychain" in signed_runner and "probe.cleanup()" in signed_runner
assert signed_menu.startswith("#if !DEBUG || !os(macOS)\n#error(")
assert 'requiredLocalEndpoint = .hostPort(host: "127.0.0.1"' in signed_menu
assert "MacLocalXPCClientV1" in signed_menu and "makeCapabilityGrantReview" in signed_menu
assert "CoreAudio" not in signed_menu and "CGEvent" not in signed_menu and "SecItem" not in signed_menu
assert 'execv(' not in host, 'AppKit restart must use a fresh supervised process'
print("Live Control Lab isolation checks passed")
