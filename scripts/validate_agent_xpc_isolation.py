#!/usr/bin/env python3
"""Source-graph guards; real signed-process tests are a separate opt-in lane."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
sources = root / "Packages/MacCompanionKit/Sources"
startup = sources / "CompanionAgentApplicationPlatform/MacCompanionAgentIsolatedStartupTestV1.swift"
text = startup.read_text()
assert text.startswith("#if os(macOS) && DEBUG\n") and text.rstrip().endswith("#endif")
assert "public enum MacCompanionAgentIsolatedStartupTestV1" not in text
assert '"/private/tmp/maccompanion-agent-xpc-' in text
assert "realpath(base.path, nil)" in text and "0o700" in text and "getuid()" in text
assert "MacCompanionAgentLocalServiceStartupV1.start(" in text
for forbidden in ("systemDefault()", "SecurityHostIdentityKeyCustodyV0(", "SMAppService", "CGRequest", "SecItem"):
    assert forbidden not in text, f"Forbidden production side effect: {forbidden}"
assert "MacAgentProductBootstrapV1.prepareInert(" in text
assert "MacAgentLifecycleObservationRootV1" in text
assert "MacLocalXPCStatusReaderV1(" in text
assert "product.startLocalAuthorization()" in text
assert "MacAgentEnabledProductRuntimeV1(product:" in text
assert "IsolatedLoopbackProduct(product:" in text and "binding: .isolatedLoopback" in text
assert "activeTestSession: Bool = false" in text
assert "consoleSession: activeTestSession ? .active : .otherConsoleUserActive" in text

for name in ("MacLocalXPCTransportV1.swift", "MacLocalXPCRemoteAccessBootstrapClientV1.swift"):
    source = (sources / "CompanionLocalXPCPlatform" / name).read_text()
    for match in re.finditer(r"private var isolatedTestID:|public convenience init\(\s*isolatedTestID:", source):
        before = source[:match.start()]
        assert before.rfind("#if DEBUG") > before.rfind("#endif"), f"Non-Debug seam: {name}"
    assert "MCLocalXPCPeerRequirementCreateSameTeamIdentifier(" in source
    assert "MacLocalXPCIdentityV1.agentSigningIdentifier" in source

for relative, marker in (
    ("CompanionAgentProductPlatform/MacAgentProductBootstrapV1.swift", "package static func prepareIsolatedPresentation("),
    ("CompanionAgentProductPlatform/MacAgentProductBootstrapV1.swift", "package func confirmIsolatedLoopbackEndpoint("),
    ("CompanionAgentNetworkPlatform/AgentNetworkListenerPairingCompositionV0.swift", "case isolatedLoopback"),
    ("CompanionAgentNetworkPlatform/AgentNetworkListenerPairingCompositionV0.swift", "package func confirmIsolatedLoopbackEndpoint("),
):
    source = (sources / relative).read_text()
    before = source[:source.index(marker)]
    assert before.rfind("#if DEBUG") > before.rfind("#endif"), f"Non-Debug seam: {relative}"
binding = (sources / "CompanionAgentNetworkPlatform/AgentNetworkListenerPairingCompositionV0.swift").read_text()
assert "makeUnstartedLoopbackListener(port:" in binding
assert 'endpoints: [.init(kind: .ipv4, value: "127.0.0.1"' in binding
assert "listenerService.snapshot().state == .listening" in binding and "context.listenerReady" in binding

probe = (root / "Experiments/LiveControlLab/Sources/AgentXPCTest/main.swift").read_text()
assert probe.startswith("#if !DEBUG || !os(macOS)\n#error(")
assert "@testable import CompanionAgentApplicationPlatform" in probe
primary = (root / "Experiments/LiveControlLab/Sources/AgentXPCTest/ProbePrimaryInputs.swift").read_text()
assert primary.startswith("#if !DEBUG || !os(macOS)\n#error(")
assert "assembleLoadedIdentity(" in primary and "assembleIssuedIdentity(" in primary
assert "guard existing == nil else" in primary and "0o600" in primary
assert "SecurityInteractiveSessionMaterialGeneratorV0()" in primary
assert "NativeAudioMuteProviderV1(controller: ProbeAudioMuteController())" in primary
assert "CoreAudioDefaultOutputMuteControllerV1(" not in primary
act = (root / "Experiments/LiveControlLab/Sources/AgentXPCTest/ProbeActClient.swift").read_text()
assert act.startswith("#if !DEBUG || !os(macOS)\n#error(")
for forbidden in ("SecItemAdd", "SecItemUpdate", "SecItemDelete", "CGRequest", "CoreAudioDefaultOutputMuteControllerV1("):
    assert forbidden not in act, f"Forbidden Act test effect: {forbidden}"
raw_act = (root / "Experiments/LiveControlLab/Sources/AgentXPCTest/ProbeActWireClient.swift").read_text()
assert raw_act.startswith("#if !DEBUG || !os(macOS)\n#error(")
assert "SecurityClientPinnedLeafEvaluatorV0.make(" in raw_act
assert "consumeVerifiedHandoff(for: connection)" in raw_act
assert "ClientCustodiedSessionSignerV0(" in raw_act
assert 'record.endpoints[0].value == "127.0.0.1"' in raw_act
for forbidden in ("SecItemAdd", "SecItemUpdate", "SecItemDelete", "CGRequest", "CoreAudioDefaultOutputMuteControllerV1("):
    assert forbidden not in raw_act, f"Forbidden raw Act test effect: {forbidden}"
assert "ProbePausedAudioProvider" in primary and "await native.execute(request)" in primary
assert "ContinuousClock.now + .seconds(12)" in primary
simulator_menu = (root / "Experiments/LiveControlLab/Sources/AgentXPCTest/ProbeSimulatorMenu.swift").read_text()
assert simulator_menu.startswith("#if !DEBUG || !os(macOS)\n#error(")
assert '"/private/tmp/maccompanion-agent-xpc-' in simulator_menu and "realpath(directory.path, nil)" in simulator_menu
assert 'requiredLocalEndpoint = .hostPort(host: "127.0.0.1"' in simulator_menu
for forbidden in ("SecItemAdd", "SecItemUpdate", "SecItemDelete", "CGRequest", "CoreAudioDefaultOutputMuteControllerV1("):
    assert forbidden not in simulator_menu, f"Forbidden signed Simulator bridge effect: {forbidden}"
for forbidden in ("SecItemAdd", "SecItemUpdate", "SecItemDelete", "prepareKey(", "systemDefault()", "CGRequest"):
    assert forbidden not in primary, f"Forbidden test custody side effect: {forbidden}"
pairing = (root / "Experiments/LiveControlLab/Sources/AgentXPCTest/ProbePairingClient.swift").read_text()
assert pairing.startswith("#if !DEBUG || !os(macOS)\n#error(")
assert "NetworkClientPairingApplicationCompositionV0.makeOwner(" in pairing
assert "NetworkClientConfiguredRouteApplicationProductFactoryV1.make(" in pairing
assert "realpath(directory.path, nil)" in pairing and "0o700" in pairing and "0o600" in pairing
for forbidden in ("SecItemAdd", "SecItemUpdate", "SecItemDelete", "systemDefault()", "CGRequest"):
    assert forbidden not in pairing, f"Forbidden client test custody side effect: {forbidden}"
interactive = (root / "Experiments/LiveControlLab/Sources/AgentXPCTest/ProbeInteractiveMenu.swift").read_text()
assert interactive.startswith("#if !DEBUG || !os(macOS)\n#error(")
assert "InteractiveMenuRuntimeOwnerV0(indicator:" in interactive
assert "MacInteractiveLeaseRuntimeAdapterV1(runtime:" in interactive
assert "try renewal.validate(current: lease)" in interactive
for forbidden in ("SecItemAdd", "SecItemUpdate", "SecItemDelete", "CGRequest", "CGEvent(", "SCStream(", "systemDefault()"):
    assert forbidden not in interactive, f"Forbidden Interactive test effect: {forbidden}"
project = (root / "MacCompanion.xcodeproj/project.pbxproj").read_text()
assert "AgentXPCTest" not in project and "AgentXPCRawProbe" not in project
assert "AgentXPCTest" not in (root / "Packages/MacCompanionKit/Package.swift").read_text()
runner = (root / "scripts/verify_agent_xpc.py").read_text()
assert 'f"media.jenny.maccompanion.xpc-test.{self.test_id}"' in runner
assert '"launchctl", "bootout", self.job' in runner
assert '"launchctl", "kill", "SIGKILL" if abrupt else "SIGTERM", self.job' in runner
assert "devicectl" not in runner and "tccutil" not in runner and "pkill" not in runner
assert "cleanupVerified" in runner and "subprocess.TimeoutExpired" in runner
print("Isolated Agent/XPC source guards passed")
