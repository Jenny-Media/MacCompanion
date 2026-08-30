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

private actor RacingRenewalRuntimeProbe: InteractiveMediaRuntimePublishingV0 {
  private var actions: [InteractiveRuntimeMediaActionV0] = []
  private var blocked: CheckedContinuation<Void, Never>?
  let rejectRetry: Bool
  let firstError: InteractiveLeaseError
  init(rejectRetry: Bool, firstError: InteractiveLeaseError = .staleLease) {
    self.rejectRetry = rejectRetry; self.firstError = firstError
  }
  func publishMedia(_ action: InteractiveRuntimeMediaActionV0, nowMonotonicNanoseconds: UInt64) async throws {
    actions.append(action)
    if actions.count == 1 {
      await withCheckedContinuation { blocked = $0 }
      throw firstError
    }
    if rejectRetry { throw InteractiveLeaseError.staleLease }
  }
  func isBlocked() -> Bool { blocked != nil }
  func resume() { blocked?.resume(); blocked = nil }
  func entries() -> [InteractiveRuntimeMediaActionV0] { actions }
}

@Test(arguments: [false, true], [false, true])
func mediaPublisherRetriesOnlyAnAdoptedRenewalOnce(adoptRenewal: Bool, rejectRetry: Bool) async throws {
  let runtime = RacingRenewalRuntimeProbe(rejectRetry: rejectRetry)
  let publisher = VideoToolboxInteractiveMediaPublisherV0(binding: try mediaPublisherBinding(), runtime: runtime, clock: { 1_000 })
  let attempt = Task { await publisher.publishDiscontinuity(presentationTimeNanoseconds: 100) }
  for _ in 0..<1_000 {
    if await runtime.isBlocked() { break }
    try await Task.sleep(for: .milliseconds(1))
  }
  try #require(await runtime.isBlocked())
  let replacement = try InteractiveMediaPublicationBindingV0(fence: mediaPublisherFence(leaseID: UUID()), descriptor: mediaPublisherDescriptor())
  if adoptRenewal { #expect(await publisher.adoptLeaseRenewal(to: replacement)) }
  await runtime.resume()
  #expect(await attempt.value == (adoptRenewal && !rejectRetry))
  let entries = await runtime.entries()
  #expect(entries.count == (adoptRenewal ? 2 : 1))
  if adoptRenewal {
    #expect(entries[1].fence == replacement.fence)
    #expect(entries[0].header == entries[1].header)
    #expect(entries[0].payload == entries[1].payload)
  }
}

@Test func mediaPublisherDoesNotRetryOtherRejectionsAfterRenewal() async throws {
  let runtime = RacingRenewalRuntimeProbe(rejectRetry: false, firstError: .expired)
  let publisher = VideoToolboxInteractiveMediaPublisherV0(binding: try mediaPublisherBinding(), runtime: runtime, clock: { 1_000 })
  let attempt = Task { await publisher.publishDiscontinuity(presentationTimeNanoseconds: 100) }
  for _ in 0..<1_000 {
    if await runtime.isBlocked() { break }
    try await Task.sleep(for: .milliseconds(1))
  }
  try #require(await runtime.isBlocked())
  let replacement = try InteractiveMediaPublicationBindingV0(fence: mediaPublisherFence(leaseID: UUID()), descriptor: mediaPublisherDescriptor())
  #expect(await publisher.adoptLeaseRenewal(to: replacement))
  await runtime.resume()
  #expect(await attempt.value == false)
  #expect(await runtime.entries().count == 1)
}

/// Exercises the real serialized runtime and publisher together. The simulated
/// encoder callback starts during activation but is never awaited by it.
private actor PublisherTransitionEffectsV0:
  InteractiveRuntimeIndicatorControllingV0,
  InteractiveRuntimeCaptureControllingV0,
  InteractiveRuntimeInputControllingV0,
  InteractiveRuntimeFrameControllingV0
{
  var runtime: InteractiveMenuRuntimeOwnerV0?
  var firstFrame: Task<Bool, Never>?
  var replacementPublisher: VideoToolboxInteractiveMediaPublisherV0?

  func bind(_ runtime: InteractiveMenuRuntimeOwnerV0) { self.runtime = runtime }
  func showInteractiveIndicator(
    deviceDisplayName: DeviceDisplayName, interactiveSessionID: UUID
  ) async throws -> InteractiveRuntimeIndicatorSnapshotV0 {
    try .init(menuAppGeneration: UUID(), menuAppRevision: 1)
  }
  func clearInteractiveIndicator() async throws {}
  func releaseAllInteractiveInput() async throws {}
  func blankLastInteractiveFrame() async throws {}
  func stopInteractiveCapture() async throws {}
  func startInteractiveCapture(
    _ command: InteractiveRuntimeInstallCommandV0
  ) async throws -> Set<SurfaceInteractionClass> { [.view] }
  func adoptInteractiveLeaseRenewal(
    _ renewal: InteractiveRuntimeLeaseRenewalV0
  ) async throws {}
  func prepareInteractiveCaptureTransition(
    _ command: InteractiveRuntimeSurfaceTransitionCommandV0
  ) async throws -> Set<SurfaceInteractionClass> { [.view] }
  func activatePreparedInteractiveCaptureTransition(
    _ command: InteractiveRuntimeSurfaceTransitionCommandV0,
    mediaSequenceBeforeTransition: UInt64
  ) async throws {
    let runtime = try #require(runtime)
    let lease = command.replacement
    let publisher = VideoToolboxInteractiveMediaPublisherV0(
      binding: try .init(
        fence: mediaPublisherFence(
          leaseID: lease.leaseID, surfaceID: lease.surfaceID,
          surfaceRevision: lease.surfaceRevision.rawValue,
          coordinateRevision: lease.coordinateRevision.rawValue
        ),
        descriptor: command.descriptor
      ),
      runtime: runtime,
      resumingAfterMediaSequence: mediaSequenceBeforeTransition,
      clock: { 3_000_000 }
    )
    replacementPublisher = publisher
    let sample = try mediaPublisherSample(
      cleanKeyframe: true, presentationTimeNanoseconds: 200
    )
    firstFrame = Task { await publisher.publish(sample) }
    await Task.yield()
  }
}

private struct PublisherTransitionOutputsV0:
  InteractiveRuntimeInputPostingV0, InteractiveRuntimeMediaEnqueuingV0
{
  func postInteractiveInput(_ envelope: InteractiveInputEnvelope) async throws {}
  func enqueueInteractiveMedia(header: MediaRecordHeader, payload: Data) -> Bool {
    true
  }
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
  leaseID: UUID = UUID(
    uuidString: "018f7000-0000-7000-8000-000000000003"
  )!,
  surfaceID: UUID = mediaPublisherSurfaceID,
  surfaceRevision: UInt64 = 5,
  coordinateRevision: UInt64 = 8
) -> InteractiveCommandFence {
  InteractiveCommandFence(
    leaseID: leaseID,
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

@Test func mediaPublisherLeaseRenewalAdvancesFenceWithoutDiscontinuity()
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

  let renewedLeaseID = UUID(
    uuidString: "018f7000-0000-7000-8000-000000000009"
  )!
  let renewed = try InteractiveMediaPublicationBindingV0(
    fence: mediaPublisherFence(leaseID: renewedLeaseID),
    descriptor: mediaPublisherDescriptor()
  )
  #expect(await publisher.adoptLeaseRenewal(to: renewed))
  #expect(
    await publisher.publish(
      try mediaPublisherSample(
        cleanKeyframe: false,
        presentationTimeNanoseconds: 200
      )))

  let entries = await runtime.entries()
  #expect(entries.map(\.action.header.mediaSequence) == [1, 2, 3])
  #expect(entries.map(\.action.header.type) == [
    .decoderConfiguration, .videoAccessUnit, .videoAccessUnit,
  ])
  #expect(entries[0].action.fence.leaseID != renewedLeaseID)
  #expect(entries[1].action.fence.leaseID != renewedLeaseID)
  #expect(entries[2].action.fence.leaseID == renewedLeaseID)
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

@Test(arguments: [UInt64(0), 2, 100])
func mediaPublisherReplacementDefersDiscontinuityUntilFirstCleanSample(
  boundary: UInt64
) async throws {
  let runtime = InteractiveMediaPublisherRuntimeProbeV0()
  let publisher = VideoToolboxInteractiveMediaPublisherV0(
    binding: try mediaPublisherBinding(),
    runtime: runtime,
    resumingAfterMediaSequence: boundary,
    clock: { 2_000 }
  )
  #expect(await runtime.entries().isEmpty)
  #expect(await publisher.publish(try mediaPublisherSample(
    cleanKeyframe: true, presentationTimeNanoseconds: 100
  )))
  #expect(await publisher.publish(try mediaPublisherSample(
    cleanKeyframe: false, presentationTimeNanoseconds: 200
  )))
  let entries = await runtime.entries()
  #expect(entries.map(\.action.header.mediaSequence)
    == [boundary + 1, boundary + 2, boundary + 3, boundary + 4])
  #expect(entries.map(\.action.header.type) == [
    .discontinuity, .decoderConfiguration, .videoAccessUnit, .videoAccessUnit,
  ])
  #expect(entries.allSatisfy { $0.action.fence == mediaPublisherFence() })
}

@Test(.timeLimit(.minutes(1)))
func mediaPublisherReplacementCompletesSerializedRuntimeAndRejectsLateOldFrame()
  async throws
{
  let effects = PublisherTransitionEffectsV0()
  let outputs = PublisherTransitionOutputsV0()
  let runtime = InteractiveMenuRuntimeOwnerV0(
    indicator: effects, capture: effects, input: effects, frame: effects,
    inputPoster: outputs, mediaQueue: outputs
  )
  await effects.bind(runtime)
  func lease(
    fence: InteractiveCommandFence, renewalCounter: UInt64
  ) throws -> InteractiveExecutionLease {
    try .init(
      leaseID: fence.leaseID, hostID: fence.hostID, deviceID: fence.deviceID,
      interactiveSessionID: fence.interactiveSessionID,
      authorizationEpoch: fence.authorizationEpoch,
      selectedDisplayID: fence.selectedDisplayID, surfaceID: fence.surfaceID,
      surfaceRevision: fence.surfaceRevision,
      coordinateRevision: fence.coordinateRevision,
      allowedInteractionClasses: [.view], renewalCounter: renewalCounter,
      issuedAtMonotonicNanoseconds: 1_000_000 + renewalCounter * 1_000_000,
      expiresAtMonotonicNanoseconds: 8_000_000 + renewalCounter * 1_000_000
    )
  }
  func acknowledge(
    commandID: UUID, fence: InteractiveCommandFence, sequence: UInt64
  ) async throws {
    _ = try await runtime.acknowledgeSurface(
      .init(
        commandID: UUID(), transitionCommandID: commandID,
        leaseID: fence.leaseID, interactiveSessionID: fence.interactiveSessionID,
        surfaceID: fence.surfaceID, surfaceRevision: fence.surfaceRevision,
        coordinateRevision: fence.coordinateRevision, readyMediaSequence: sequence
      ),
      nowMonotonicNanoseconds: 3_000_000
    )
  }
  let initialFence = mediaPublisherFence()
  let install = try InteractiveRuntimeInstallCommandV0(
    commandID: UUID(), lease: lease(fence: initialFence, renewalCounter: 0),
    deviceDisplayName: DeviceDisplayName("Test phone"),
    surfaceDescriptor: mediaPublisherDescriptor(),
    sessionDeadlineMonotonicNanoseconds: 10_000_000
  )
  _ = try await runtime.install(install, nowMonotonicNanoseconds: 3_000_000)
  let oldPublisher = VideoToolboxInteractiveMediaPublisherV0(
    binding: try mediaPublisherBinding(), runtime: runtime, clock: { 3_000_000 }
  )
  #expect(await oldPublisher.publish(try mediaPublisherSample(
    cleanKeyframe: true, presentationTimeNanoseconds: 100
  )))
  try await acknowledge(commandID: install.commandID, fence: initialFence, sequence: 2)
  let replacementFence = mediaPublisherFence(
    leaseID: UUID(), surfaceID: UUID(), surfaceRevision: 6, coordinateRevision: 9
  )
  let transition = try InteractiveRuntimeSurfaceTransitionCommandV0(
    commandID: UUID(), previousLeaseID: initialFence.leaseID,
    replacement: lease(fence: replacementFence, renewalCounter: 1),
    descriptor: mediaPublisherDescriptor(
      surfaceID: replacementFence.surfaceID, surfaceRevision: 6, coordinateRevision: 9
    )
  )
  let receipt = try await runtime.prepareSurfaceTransition(
    transition, nowMonotonicNanoseconds: 3_000_000
  )
  #expect(receipt.mediaSequenceBeforeTransition == 2)
  let firstFrame = try #require(await effects.firstFrame)
  #expect(await firstFrame.value)
  // A completion from the stopped encoder cannot corrupt the new publisher or
  // force teardown of a valid replacement session.
  #expect(!(await oldPublisher.publish(try mediaPublisherSample(
    cleanKeyframe: false, presentationTimeNanoseconds: 250
  ))))
  try await acknowledge(
    commandID: transition.commandID, fence: replacementFence, sequence: 5
  )
  #expect(await runtime.surfaceAdmissionState() == .ready)
  let replacementPublisher = try #require(await effects.replacementPublisher)
  #expect(await replacementPublisher.publish(try mediaPublisherSample(
    cleanKeyframe: false, presentationTimeNanoseconds: 300
  )))
}

@Test func mediaPublisherReplacementRejectsDeltaBeforeAnyPublication()
  async throws
{
  let runtime = InteractiveMediaPublisherRuntimeProbeV0()
  let publisher = VideoToolboxInteractiveMediaPublisherV0(
    binding: try mediaPublisherBinding(), runtime: runtime,
    resumingAfterMediaSequence: 2, clock: { 2_000 }
  )
  #expect(!(await publisher.publish(try mediaPublisherSample(
    cleanKeyframe: false, presentationTimeNanoseconds: 100
  ))))
  #expect(await runtime.entries().isEmpty)
  #expect(await publisher.phase() == .failed)
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
