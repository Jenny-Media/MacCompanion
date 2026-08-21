import CompanionNativeProviders
import CompanionOperations
import CompanionWire
import Foundation
import Testing

private final class FakeMuteController: DefaultOutputMuteControllingV1,
    @unchecked Sendable {
    private let lock = NSLock()
    private var requested: [Bool] = []
    let result: Result<Bool, DefaultOutputMuteErrorV1>

    init(result: Result<Bool, DefaultOutputMuteErrorV1>) {
        self.result = result
    }

    func setDefaultOutputMuted(_ desired: Bool) throws -> Bool {
        lock.withLock { requested.append(desired) }
        return try result.get()
    }

    func requests() -> [Bool] { lock.withLock { requested } }
}

private func muteRequest(
    parameters: CanonicalJSONValue
) -> CapabilityProviderRequestV1 {
    CapabilityProviderRequestV1(
        operationID: UUID(),
        capabilityID: NativeAudioMuteCapabilityV1.capabilityID,
        parameters: parameters,
        expiresAtUnixMilliseconds: 30_000
    )
}

@Test func nativeAudioMuteDescriptorIsClosedDesiredStateAndConservativeAtLock() throws {
    let descriptor = try NativeAudioMuteCapabilityV1.descriptor()
    #expect(descriptor.capabilityID == "maccompanion.system.setAudioMuted")
    #expect(descriptor.providerID == "maccompanion.native.audio")
    #expect(descriptor.effects.changesLocalState == .reversible)
    #expect(descriptor.effects.dataAccess == .none)
    #expect(!descriptor.effects.allowedWhileLocked)
    #expect(descriptor.effects.cancellation == .notApplicable)
    try descriptor.parameterSchema.validate(.object([
        .init(key: "muted", value: .boolean(true)),
    ]))
    #expect(throws: (any Error).self) {
        try descriptor.parameterSchema.validate(.object([
            .init(key: "toggle", value: .boolean(true)),
        ]))
    }
}

@Test func nativeAudioMuteProviderReturnsOnlyVerifiedCanonicalState() async {
    let controller = FakeMuteController(result: .success(true))
    let provider = NativeAudioMuteProviderV1(controller: controller)
    let outcome = await provider.execute(muteRequest(parameters: .object([
        .init(key: "muted", value: .boolean(true)),
    ])))
    #expect(outcome == .succeeded(resultJSON: Data("{\"muted\":true}".utf8)))
    #expect(controller.requests() == [true])
}

@Test func nativeAudioMuteProviderDefensivelyRejectsUnregisteredShape() async {
    let controller = FakeMuteController(result: .success(true))
    let provider = NativeAudioMuteProviderV1(controller: controller)
    let outcome = await provider.execute(muteRequest(parameters: .object([
        .init(key: "muted", value: .boolean(true)),
        .init(key: "extra", value: .boolean(false)),
    ])))
    #expect(outcome == .failed(.rejected))
    #expect(controller.requests().isEmpty)
}

@Test func nativeAudioMuteProviderMapsOnlyClosedHostOwnedFailures() async {
    for (error, expected) in [
        (DefaultOutputMuteErrorV1.unavailable, CapabilityProviderFailureCodeV1.unavailable),
        (.rejected, .rejected),
        (.executionFailed, .executionFailed),
    ] {
        let provider = NativeAudioMuteProviderV1(
            controller: FakeMuteController(result: .failure(error))
        )
        #expect(await provider.execute(muteRequest(parameters: .object([
            .init(key: "muted", value: .boolean(false)),
        ]))) == .failed(expected))
    }
}
