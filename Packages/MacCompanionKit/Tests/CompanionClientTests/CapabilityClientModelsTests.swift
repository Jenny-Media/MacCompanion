import CompanionClient
import CompanionDomain
import CompanionWire
import Foundation
import Testing

private func clientDescriptor(_ index: Int) throws -> CapabilityDiscoveryDescriptorV1 {
    let schema = try CapabilitySchemaV1.object(properties: [
        CapabilitySchemaPropertyV1(
            name: "value",
            required: true,
            schema: .boolean()
        ),
    ])
    return try CapabilityDiscoveryDescriptorV1(CapabilityDescriptorV1(
        capabilityID: String(format: "maccompanion.test.capability%02d", index),
        schemaVersion: 1,
        providerID: "maccompanion.test",
        providerVersion: "1.0.0",
        providerGeneration: UUID(
            uuidString: "018f8100-0000-7000-8000-000000000001"
        )!,
        executionRevision: UUID(
            uuidString: "018f8200-0000-7000-8000-000000000001"
        )!,
        englishTitle: "Capability \(index)",
        englishSummary: "A bounded capability.",
        parameterSchema: schema,
        resultSchema: schema,
        effects: try CapabilityEffectFacts(
            dataAccess: .none,
            changesLocalState: .reversible,
            mayDisruptUser: false,
            invokesExternalService: false,
            usesCredentials: false,
            destructive: false,
            requiresForegroundSession: false,
            allowedWhileLocked: false,
            cancellation: .notApplicable
        )
    ))
}

private func clientPage(
    generation: UUID,
    range: Range<Int>,
    next: String?
) throws -> CapabilityRegistryResponseBody {
    try CapabilityRegistryResponseBody(
        registryGeneration: WireUUID(generation),
        grantRevision: 2,
        policyRevision: 3,
        capabilities: try range.map(clientDescriptor),
        nextAfterCapabilityID: next
    )
}

@Test func catalogAssemblerPublishesOnlyAfterEveryFenceMatchedPage() throws {
    let generation = UUID()
    var assembler = CapabilityCatalogAssemblerV1()
    let firstRequest = try assembler.begin()
    #expect(firstRequest.expectedRegistryGeneration == nil)
    let continuation = try #require(try assembler.accept(clientPage(
        generation: generation,
        range: 0..<4,
        next: "maccompanion.test.capability03"
    )))
    #expect(assembler.state == .loading)
    #expect(assembler.catalog == nil)
    #expect(continuation.expectedRegistryGeneration == WireUUID(generation))
    #expect(continuation.expectedGrantRevision == 2)
    #expect(continuation.afterCapabilityID == "maccompanion.test.capability03")

    #expect(try assembler.accept(clientPage(
        generation: generation,
        range: 4..<5,
        next: nil
    )) == nil)
    #expect(assembler.state == .complete)
    #expect(assembler.catalog?.capabilities.count == 5)
    #expect(assembler.catalog?.capability(
        "maccompanion.test.capability04"
    ) != nil)
}

@Test func fenceOrOrderingFailureDiscardsEveryPartialCapability() throws {
    let generation = UUID()
    var fenceAssembler = CapabilityCatalogAssemblerV1()
    _ = try fenceAssembler.begin()
    _ = try fenceAssembler.accept(clientPage(
        generation: generation,
        range: 0..<4,
        next: "maccompanion.test.capability03"
    ))
    #expect(throws: CapabilityCatalogAssemblyErrorV1.fenceChanged) {
        _ = try fenceAssembler.accept(clientPage(
            generation: UUID(),
            range: 4..<5,
            next: nil
        ))
    }
    #expect(fenceAssembler.state == .invalidated)
    #expect(fenceAssembler.catalog == nil)

    var orderAssembler = CapabilityCatalogAssemblerV1()
    _ = try orderAssembler.begin()
    _ = try orderAssembler.accept(clientPage(
        generation: generation,
        range: 0..<4,
        next: "maccompanion.test.capability03"
    ))
    #expect(throws: CapabilityCatalogAssemblyErrorV1.unexpectedCursor) {
        _ = try orderAssembler.accept(clientPage(
            generation: generation,
            range: 2..<3,
            next: nil
        ))
    }
    #expect(orderAssembler.state == .invalidated)
}

@Test func resultPresenterAcceptsOnlyTheInvokedCapabilitySchema() throws {
    let descriptor = try clientDescriptor(0)
    let status = try OperationStatusResponseBody(
        operationID: WireUUID(UUID()),
        state: .succeeded,
        terminalCode: nil,
        result: .object([
            .init(key: "value", value: .boolean(true)),
        ])
    )
    #expect(try OperationResultPresenterV1.present(
        status,
        invokedCapabilityID: descriptor.capabilityID,
        descriptor: descriptor
    ) == .succeeded(verifiedResult: .object([
        .init(key: "value", value: .boolean(true)),
    ])))
    #expect(throws: OperationResultPresentationErrorV1.capabilityMismatch) {
        _ = try OperationResultPresenterV1.present(
            status,
            invokedCapabilityID: "maccompanion.test.different",
            descriptor: descriptor
        )
    }
}

@Test func resultPresenterRejectsSchemaMismatchAndHidesUnknownFailureText() throws {
    let descriptor = try clientDescriptor(0)
    let invalid = try OperationStatusResponseBody(
        operationID: WireUUID(UUID()),
        state: .succeeded,
        terminalCode: nil,
        result: .object([
            .init(key: "value", value: .string("not-a-boolean")),
        ])
    )
    #expect(throws: OperationResultPresentationErrorV1.resultSchemaRejected) {
        _ = try OperationResultPresenterV1.present(
            invalid,
            invokedCapabilityID: descriptor.capabilityID,
            descriptor: descriptor
        )
    }

    let failed = try OperationStatusResponseBody(
        operationID: WireUUID(UUID()),
        state: .failed,
        terminalCode: "provider.someFutureInternalCode",
        result: nil
    )
    #expect(try OperationResultPresenterV1.present(
        failed,
        invokedCapabilityID: descriptor.capabilityID,
        descriptor: descriptor
    ) == .failed(.genericFailure))
}

@Test func resultPresenterKeepsUnknownOutcomeDistinctFromFailureOrSuccess() throws {
    let descriptor = try clientDescriptor(0)
    let unknown = try OperationStatusResponseBody(
        operationID: WireUUID(UUID()),
        state: .outcomeUnknown,
        terminalCode: "operation.outcomeUnknown",
        result: nil
    )
    #expect(try OperationResultPresenterV1.present(
        unknown,
        invokedCapabilityID: descriptor.capabilityID,
        descriptor: descriptor
    ) == .outcomeUnknown)
}
