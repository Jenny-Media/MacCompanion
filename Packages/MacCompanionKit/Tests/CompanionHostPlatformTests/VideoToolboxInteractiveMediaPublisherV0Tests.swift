import CompanionDomain
import CompanionIPC
import CompanionInteractiveRuntime
import CompanionInteractiveShared
import CompanionInteractiveWire
import Foundation
import Testing

@testable import CompanionHostPlatform

private enum InteractiveMediaPublisherTestError: Error {
  case rejected
}

private actor InteractiveMediaPublisherRuntimeProbeV0:
  InteractiveMediaRuntimePublishingV0
{
  struct Entry: Equatable, Sendable {
    let action: InteractiveRuntimeMediaActionV0
    let nowMonotonicNanoseconds: UInt64
  }

  private var entriesStorage: [Entry] = []
  private let rejectedIndex: Int?

  init(rejectedIndex: Int? = nil) {
    self.rejectedIndex = rejectedIndex
  }

  func publishMedia(
    _ action: InteractiveRuntimeMediaActionV0,
    nowMonotonicNanoseconds: UInt64
  ) async throws {
    if entriesStorage.count == rejectedIndex {
      throw InteractiveMediaPublisherTestError.rejected
    }
    entriesStorage.append(
      Entry(
        action: action,
        nowMonotonicNanoseconds: nowMonotonicNanoseconds
      ))
  }

  func entries() -> [Entry] { entriesStorage }
}

private let mediaPublisherSessionID = UUID(
  uuidString: "018f7000-0000-7000-8000-000000000001"
)!
private let mediaPublisherSurfaceID = UUID(
  uuidString: "018f7000-0000-7000-8000-000000000002"
)!

private func mediaPublisherDescriptor(
  surfaceID: UUID = mediaPublisherSurfaceID,
  surfaceRevision: UInt64 = 5,
  coordinateRevision: UInt64 = 8,
  interactionClasses: Set<SurfaceInteractionClass> = [.view]
) throws -> AdaptiveSurfaceDescriptor {
  try AdaptiveSurfaceDescriptor(
    interactiveSessionID: mediaPublisherSessionID,
    authorizationEpoch: .init(rawValue: 3),
    surfaceID: surfaceID,
    kind: .desktop,
    surfaceRevision: .init(rawValue: surfaceRevision),
    coordinateSpaceRevision: .init(rawValue: coordinateRevision),
    encodedWidth: 4,
    encodedHeight: 4,
    logicalWidthPoints: 4,
    logicalHeightPoints: 4,
    interactionClasses: interactionClasses,
    privacyProfile: .visualOnly,
    metadataFields: [],
    createdAtMonotonicMilliseconds: 1,
    expiresAtMonotonicMilliseconds: 10_000
  )
}

private func mediaPublisherFence(
  surfaceID: UUID = mediaPublisherSurfaceID,
  surfaceRevision: UInt64 = 5,
  coordinateRevision: UInt64 = 8
) -> InteractiveCommandFence {
  InteractiveCommandFence(
    leaseID: UUID(
      uuidString: "018f7000-0000-7000-8000-000000000003"
    )!,
    hostID: UUID(
      uuidString: "018f7000-0000-7000-8000-000000000004"
    )!,
    deviceID: UUID(
      uuidString: "018f7000-0000-7000-8000-000000000005"
    )!,
    interactiveSessionID: mediaPublisherSessionID,
    authorizationEpoch: .init(rawValue: 3),
    selectedDisplayID: UUID(
      uuidString: "018f7000-0000-7000-8000-000000000006"
    )!,
    surfaceID: surfaceID,
    surfaceRevision: .init(rawValue: surfaceRevision),
    coordinateRevision: .init(rawValue: coordinateRevision)
  )
}

private func mediaPublisherBinding() throws
  -> InteractiveMediaPublicationBindingV0
{
  try InteractiveMediaPublicationBindingV0(
    fence: mediaPublisherFence(),
    descriptor: mediaPublisherDescriptor()
  )
}

private func mediaPublisherConfiguration(
  level: UInt8 = 30
) throws -> Data {
  try VideoToolboxAVCCOutputV0.makeDecoderConfiguration(
    sequenceParameterSets: [Data([0x67, 66, 0, level])],
    pictureParameterSets: [Data([0x68, 0])]
  )
}

private func mediaPublisherSample(
  cleanKeyframe: Bool,
  presentationTimeNanoseconds: UInt64,
  configurationLevel: UInt8 = 30
) throws -> VideoToolboxEncodedSampleV0 {
  VideoToolboxEncodedSampleV0(
    decoderConfiguration: try mediaPublisherConfiguration(
      level: configurationLevel
    ),
    accessUnit: Data([
      0, 0, 0, 2,
      cleanKeyframe ? 0x65 : 0x41,
      UInt8(presentationTimeNanoseconds & 0xff),
    ]),
    cleanKeyframe: cleanKeyframe,
    width: 4,
    height: 4,
    presentationTimeNanoseconds: presentationTimeNanoseconds
  )
}

private func makeMediaPublisher(
  runtime: InteractiveMediaPublisherRuntimeProbeV0
) throws -> VideoToolboxInteractiveMediaPublisherV0 {
  VideoToolboxInteractiveMediaPublisherV0(
    binding: try mediaPublisherBinding(),
    runtime: runtime,
    clock: { 2_000 }
  )
}

@Test func mediaPublisherBindingRejectsFenceAndDescriptorMismatch() throws {
  #expect(
    throws:
      VideoToolboxInteractiveMediaPublisherErrorV0
      .bindingMismatch
  ) {
    _ = try InteractiveMediaPublicationBindingV0(
      fence: mediaPublisherFence(surfaceID: UUID()),
      descriptor: mediaPublisherDescriptor()
    )
  }
  #expect(
    throws:
      VideoToolboxInteractiveMediaPublisherErrorV0
      .bindingMismatch
  ) {
    _ = try InteractiveMediaPublicationBindingV0(
      fence: mediaPublisherFence(),
      descriptor: mediaPublisherDescriptor(surfaceID: UUID())
    )
  }
}

@Test func mediaPublisherStartsWithConfigurationThenCleanAccessUnit()
  async throws
{
  let runtime = InteractiveMediaPublisherRuntimeProbeV0()
  let publisher = try makeMediaPublisher(runtime: runtime)

  #expect(
    await publisher.publish(
      try mediaPublisherSample(
        cleanKeyframe: true,
        presentationTimeNanoseconds: 100
      )))

  let entries = await runtime.entries()
  #expect(entries.count == 2)
  #expect(
    entries.map(\.action.header.type)
      == [.decoderConfiguration, .videoAccessUnit])
  #expect(entries.map(\.action.header.mediaSequence) == [1, 2])
  #expect(
    entries.map(\.action.header.presentationTimeNanoseconds)
      == [100, 100])
  #expect(entries[0].action.header.flags.isEmpty)
  #expect(entries[1].action.header.flags == [.cleanKeyframe])
  #expect(
    entries.allSatisfy {
      $0.action.header.encodedWidth == 4
        && $0.action.header.encodedHeight == 4
        && $0.nowMonotonicNanoseconds == 2_000
    })
}

@Test func mediaPublisherOmitsUnchangedConfigurationForDeltaFrames()
  async throws
{
  let runtime = InteractiveMediaPublisherRuntimeProbeV0()
  let publisher = try makeMediaPublisher(runtime: runtime)
  #expect(
    await publisher.publish(
      try mediaPublisherSample(
        cleanKeyframe: true,
        presentationTimeNanoseconds: 100
      )))
  #expect(
    await publisher.publish(
      try mediaPublisherSample(
        cleanKeyframe: false,
        presentationTimeNanoseconds: 200
      )))

  let entries = await runtime.entries()
  #expect(
    entries.map(\.action.header.type)
      == [.decoderConfiguration, .videoAccessUnit, .videoAccessUnit])
  #expect(entries.map(\.action.header.mediaSequence) == [1, 2, 3])
  #expect(entries[2].action.header.flags.isEmpty)
}

@Test func mediaPublisherRepublishesChangedConfigurationOnlyWithCleanFrame()
  async throws
{
  let runtime = InteractiveMediaPublisherRuntimeProbeV0()
  let publisher = try makeMediaPublisher(runtime: runtime)
  #expect(
    await publisher.publish(
      try mediaPublisherSample(
        cleanKeyframe: true,
        presentationTimeNanoseconds: 100
      )))
  #expect(
    await publisher.publish(
      try mediaPublisherSample(
        cleanKeyframe: true,
        presentationTimeNanoseconds: 200,
        configurationLevel: 31
      )))

  let entries = await runtime.entries()
  #expect(
    entries.map(\.action.header.type) == [
      .decoderConfiguration, .videoAccessUnit,
      .decoderConfiguration, .videoAccessUnit,
    ])
  #expect(entries.map(\.action.header.mediaSequence) == [1, 2, 3, 4])
}

@Test func mediaPublisherDiscontinuityRequiresFreshConfigurationAndCleanFrame()
  async throws
{
  let runtime = InteractiveMediaPublisherRuntimeProbeV0()
  let publisher = try makeMediaPublisher(runtime: runtime)
  #expect(
    await publisher.publish(
      try mediaPublisherSample(
        cleanKeyframe: true,
        presentationTimeNanoseconds: 100
      )))
  #expect(
    await publisher.publishDiscontinuity(
      presentationTimeNanoseconds: 150
    ))
  #expect(
    await publisher.publish(
      try mediaPublisherSample(
        cleanKeyframe: true,
        presentationTimeNanoseconds: 200
      )))

  let entries = await runtime.entries()
  #expect(
    entries.map(\.action.header.type) == [
      .decoderConfiguration, .videoAccessUnit, .discontinuity,
      .decoderConfiguration, .videoAccessUnit,
    ])
  #expect(entries.map(\.action.header.mediaSequence) == [1, 2, 3, 4, 5])
  #expect(entries[2].action.payload.isEmpty)
  #expect(entries[2].action.header.encodedWidth == 0)
  #expect(entries[2].action.header.encodedHeight == 0)
}

@Test func mediaPublisherSurfaceTransitionPreservesSequenceUnderNewFence()
  async throws
{
  let runtime = InteractiveMediaPublisherRuntimeProbeV0()
  let publisher = try makeMediaPublisher(runtime: runtime)
  #expect(
    await publisher.publish(
      try mediaPublisherSample(
        cleanKeyframe: true,
        presentationTimeNanoseconds: 100
      )))

  let replacementSurfaceID = UUID(
    uuidString: "018f7000-0000-7000-8000-000000000007"
  )!
  let replacement = try InteractiveMediaPublicationBindingV0(
    fence: mediaPublisherFence(
      surfaceID: replacementSurfaceID,
      surfaceRevision: 6,
      coordinateRevision: 9
    ),
    descriptor: mediaPublisherDescriptor(
      surfaceID: replacementSurfaceID,
      surfaceRevision: 6,
      coordinateRevision: 9
    )
  )
  #expect(
    await publisher.transition(
      to: replacement,
      presentationTimeNanoseconds: 150
    ))
  #expect(
    await publisher.publish(
      try mediaPublisherSample(
        cleanKeyframe: true,
        presentationTimeNanoseconds: 200
      )))

  let entries = await runtime.entries()
  #expect(entries.map(\.action.header.mediaSequence) == [1, 2, 3, 4, 5])
  #expect(
    entries.map(\.action.header.type) == [
      .decoderConfiguration, .videoAccessUnit, .discontinuity,
      .decoderConfiguration, .videoAccessUnit,
    ])
  #expect(entries[2].action.header.surfaceID == replacementSurfaceID)
  #expect(entries[2].action.header.surfaceRevision.rawValue == 6)
  #expect(entries[2].action.header.coordinateSpaceRevision.rawValue == 9)
  #expect(entries[3].action.header.surfaceID == replacementSurfaceID)
  #expect(entries[4].action.header.surfaceID == replacementSurfaceID)
}

@Test func mediaPublisherRejectsDeltaConfigurationChangeAndTimelineRollback()
  async throws
{
  let deltaRuntime = InteractiveMediaPublisherRuntimeProbeV0()
  let deltaPublisher = try makeMediaPublisher(runtime: deltaRuntime)
  #expect(
    !(await deltaPublisher.publish(
      try mediaPublisherSample(
        cleanKeyframe: false,
        presentationTimeNanoseconds: 100
      ))))
  #expect(await deltaPublisher.phase() == .failed)
  #expect(await deltaRuntime.entries().isEmpty)

  let rollbackRuntime = InteractiveMediaPublisherRuntimeProbeV0()
  let rollbackPublisher = try makeMediaPublisher(runtime: rollbackRuntime)
  #expect(
    await rollbackPublisher.publish(
      try mediaPublisherSample(
        cleanKeyframe: true,
        presentationTimeNanoseconds: 200
      )))
  #expect(
    !(await rollbackPublisher.publish(
      try mediaPublisherSample(
        cleanKeyframe: false,
        presentationTimeNanoseconds: 199
      ))))
  #expect(await rollbackPublisher.phase() == .failed)
  #expect(await rollbackRuntime.entries().count == 2)
}

@Test func mediaPublisherRuntimeRejectionAndEndAreTerminal()
  async throws
{
  let rejectedRuntime = InteractiveMediaPublisherRuntimeProbeV0(
    rejectedIndex: 1
  )
  let rejectedPublisher = try makeMediaPublisher(
    runtime: rejectedRuntime
  )
  #expect(
    !(await rejectedPublisher.publish(
      try mediaPublisherSample(
        cleanKeyframe: true,
        presentationTimeNanoseconds: 100
      ))))
  #expect(await rejectedPublisher.phase() == .failed)
  #expect(await rejectedRuntime.entries().count == 1)

  let endedRuntime = InteractiveMediaPublisherRuntimeProbeV0()
  let endedPublisher = try makeMediaPublisher(runtime: endedRuntime)
  #expect(
    await endedPublisher.publishEnd(
      presentationTimeNanoseconds: 0
    ))
  #expect(await endedPublisher.phase() == .ended)
  #expect(
    !(await endedPublisher.publish(
      try mediaPublisherSample(
        cleanKeyframe: true,
        presentationTimeNanoseconds: 1
      ))))
  #expect(await endedPublisher.phase() == .ended)
  let entries = await endedRuntime.entries()
  #expect(entries.count == 1)
  #expect(entries[0].action.header.type == .end)
  #expect(entries[0].action.header.mediaSequence == 1)
}
