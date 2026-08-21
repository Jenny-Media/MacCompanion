import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit
import Testing

@testable import CompanionHostPlatform

private enum ScreenCaptureKitStreamOwnerTestError: Error {
  case startRejected
  case stopRejected
  case encodeRejected
  case pixelBufferCreationFailed
  case sampleBufferCreationFailed
}

private actor ScreenCaptureKitStreamSessionProbeV0:
  ScreenCaptureKitStreamingSessionV0
{
  private let stream: AsyncStream<ScreenCaptureKitStreamEventV0>
  private let continuation: AsyncStream<ScreenCaptureKitStreamEventV0>.Continuation
  private let rejectsStart: Bool
  private let rejectsStop: Bool
  private var startsStorage = 0
  private var stopsStorage = 0

  init(rejectsStart: Bool = false, rejectsStop: Bool = false) {
    self.rejectsStart = rejectsStart
    self.rejectsStop = rejectsStop
    let pair = AsyncStream.makeStream(
      of: ScreenCaptureKitStreamEventV0.self,
      bufferingPolicy: .bufferingNewest(1)
    )
    stream = pair.stream
    continuation = pair.continuation
  }

  func start() async throws
    -> AsyncStream<ScreenCaptureKitStreamEventV0>
  {
    startsStorage += 1
    if rejectsStart {
      throw ScreenCaptureKitStreamOwnerTestError.startRejected
    }
    return stream
  }

  func stop() async throws {
    stopsStorage += 1
    continuation.finish()
    if rejectsStop {
      throw ScreenCaptureKitStreamOwnerTestError.stopRejected
    }
  }

  func yield(_ event: ScreenCaptureKitStreamEventV0) {
    continuation.yield(event)
  }

  func calls() -> (starts: Int, stops: Int) {
    (startsStorage, stopsStorage)
  }
}

private actor ScreenCaptureKitEncoderProbeV0:
  ScreenCaptureKitVideoEncodingV0
{
  struct Submission: Equatable, Sendable {
    let sourceSequence: UInt64
    let presentationTime: CMTime
    let duration: CMTime
    let forceCleanKeyframe: Bool
  }

  private let rejectsSubmission: Bool
  private let blocksFirstSubmission: Bool
  private var submissionsStorage: [Submission] = []
  private var stopsStorage = 0
  private var firstSubmissionContinuation: CheckedContinuation<Void, Never>?

  init(
    rejectsSubmission: Bool = false,
    blocksFirstSubmission: Bool = false
  ) {
    self.rejectsSubmission = rejectsSubmission
    self.blocksFirstSubmission = blocksFirstSubmission
  }

  func submit(
    _ frame: VideoToolboxH264InputFrameV0,
    forceCleanKeyframe: Bool
  ) async throws -> VideoToolboxH264FrameSubmissionV0 {
    if rejectsSubmission {
      throw ScreenCaptureKitStreamOwnerTestError.encodeRejected
    }
    submissionsStorage.append(
      Submission(
        sourceSequence: frame.sourceSequence,
        presentationTime: frame.presentationTime,
        duration: frame.duration,
        forceCleanKeyframe: forceCleanKeyframe
      ))
    if blocksFirstSubmission, submissionsStorage.count == 1 {
      await withCheckedContinuation {
        firstSubmissionContinuation = $0
      }
    }
    return .started
  }

  func stop() async { stopsStorage += 1 }

  func snapshot() -> (submissions: [Submission], stops: Int) {
    (submissionsStorage, stopsStorage)
  }

  func firstSubmissionIsBlocked() -> Bool {
    firstSubmissionContinuation != nil
  }

  func releaseFirstSubmission() {
    firstSubmissionContinuation?.resume()
    firstSubmissionContinuation = nil
  }
}

private final class ScreenCaptureKitTerminalProbeV0: @unchecked Sendable {
  private let lock = NSLock()
  private var reasonsStorage: [ScreenCaptureKitStreamTerminationReasonV0] = []

  var reasons: [ScreenCaptureKitStreamTerminationReasonV0] {
    lock.withLock { reasonsStorage }
  }

  func record(_ reason: ScreenCaptureKitStreamTerminationReasonV0) {
    lock.withLock { reasonsStorage.append(reason) }
  }
}

private func screenCaptureKitOwnerProfile() throws
  -> ScreenCaptureKitCaptureProfileV0
{
  try ScreenCaptureKitCaptureProfileV0(
    width: 4,
    height: 4,
    framesPerSecond: 30,
    queueDepth: 2
  )
}

private func screenCaptureKitPixelBuffer(
  width: Int = 4,
  height: Int = 4
) throws -> CVPixelBuffer {
  var output: CVPixelBuffer?
  guard
    CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
      nil,
      &output
    ) == kCVReturnSuccess,
    let output
  else {
    throw ScreenCaptureKitStreamOwnerTestError
      .pixelBufferCreationFailed
  }
  return output
}

private func screenCaptureKitFrame(
  presentationValue: Int64
) throws -> ScreenCaptureKitVideoFrameV0 {
  ScreenCaptureKitVideoFrameV0(
    pixelBuffer: try screenCaptureKitPixelBuffer(),
    presentationTime: CMTime(
      value: presentationValue,
      timescale: 30
    ),
    duration: CMTime(value: 1, timescale: 30)
  )
}

@available(macOS 13.0, *)
private func screenCaptureKitSampleBuffer(
  width: Int = 4,
  complete: Bool
) throws -> CMSampleBuffer {
  let pixelBuffer = try screenCaptureKitPixelBuffer(width: width)
  var description: CMVideoFormatDescription?
  guard
    CMVideoFormatDescriptionCreateForImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescriptionOut: &description
    ) == noErr,
    let description
  else {
    throw ScreenCaptureKitStreamOwnerTestError
      .sampleBufferCreationFailed
  }
  var timing = CMSampleTimingInfo(
    duration: CMTime(value: 1, timescale: 30),
    presentationTimeStamp: CMTime(value: 2, timescale: 30),
    decodeTimeStamp: .invalid
  )
  var output: CMSampleBuffer?
  guard
    CMSampleBufferCreateReadyWithImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescription: description,
      sampleTiming: &timing,
      sampleBufferOut: &output
    ) == noErr,
    let output
  else {
    throw ScreenCaptureKitStreamOwnerTestError
      .sampleBufferCreationFailed
  }
  if complete,
    let attachments = CMSampleBufferGetSampleAttachmentsArray(
      output,
      createIfNecessary: true
    ) as? [NSMutableDictionary],
    let first = attachments.first
  {
    first[SCStreamFrameInfo.status] = SCFrameStatus.complete.rawValue
  }
  return output
}

private func waitForScreenCaptureKitOwner(
  _ condition: @escaping @Sendable () async -> Bool
) async -> Bool {
  for _ in 0..<1_000 {
    if await condition() { return true }
    await Task.yield()
  }
  return await condition()
}

@available(macOS 13.0, *)
@Test func screenCaptureKitNormalizerAdmitsOnlyCompleteBoundedFrames()
  throws
{
  let profile = try screenCaptureKitOwnerProfile()
  let ignored = try ScreenCaptureKitVideoSampleNormalizerV0.admit(
    screenCaptureKitSampleBuffer(complete: false),
    profile: profile
  )
  guard case .ignored = ignored else {
    Issue.record("frame without complete status was admitted")
    return
  }

  let admitted = try ScreenCaptureKitVideoSampleNormalizerV0.admit(
    screenCaptureKitSampleBuffer(complete: true),
    profile: profile
  )
  guard case .frame(let frame) = admitted else {
    Issue.record("complete frame was not admitted")
    return
  }
  #expect(CVPixelBufferGetWidth(frame.pixelBuffer) == 4)
  #expect(frame.presentationTime == CMTime(value: 2, timescale: 30))
  #expect(frame.duration == CMTime(value: 1, timescale: 30))

  #expect(throws: ScreenCaptureKitVideoSampleErrorV0.invalidPixelBuffer) {
    _ = try ScreenCaptureKitVideoSampleNormalizerV0.admit(
      screenCaptureKitSampleBuffer(width: 3, complete: true),
      profile: profile
    )
  }
}

@Test func screenCaptureKitOwnerSerializesFramesAndStopsExactlyOnce()
  async throws
{
  let session = ScreenCaptureKitStreamSessionProbeV0()
  let encoder = ScreenCaptureKitEncoderProbeV0()
  let terminal = ScreenCaptureKitTerminalProbeV0()
  let owner = ScreenCaptureKitStreamOwnerV0(
    session: session,
    encoder: encoder,
    terminal: terminal.record
  )

  try await owner.start()
  await session.yield(
    .frame(
      try screenCaptureKitFrame(
        presentationValue: 1
      )))
  #expect(
    await waitForScreenCaptureKitOwner {
      await encoder.snapshot().submissions.count == 1
    })
  await session.yield(
    .frame(
      try screenCaptureKitFrame(
        presentationValue: 2
      )))
  #expect(
    await waitForScreenCaptureKitOwner {
      await encoder.snapshot().submissions.count == 2
    })
  try await owner.stop()
  try await owner.stop()

  let encoderSnapshot = await encoder.snapshot()
  #expect(encoderSnapshot.submissions.map(\.sourceSequence) == [1, 2])
  #expect(
    encoderSnapshot.submissions.map(\.forceCleanKeyframe)
      == [false, false])
  #expect(encoderSnapshot.stops == 1)
  #expect(await session.calls().starts == 1)
  #expect(await session.calls().stops == 1)
  #expect(await owner.phase() == .stopped)
  #expect(terminal.reasons == [.localStop])
}

@Test func screenCaptureKitOwnerRetainsOnlyNewestUnconsumedCallback()
  async throws
{
  let session = ScreenCaptureKitStreamSessionProbeV0()
  let encoder = ScreenCaptureKitEncoderProbeV0(
    blocksFirstSubmission: true
  )
  let owner = ScreenCaptureKitStreamOwnerV0(
    session: session,
    encoder: encoder
  )
  try await owner.start()
  await session.yield(.frame(try screenCaptureKitFrame(
    presentationValue: 1
  )))
  #expect(await waitForScreenCaptureKitOwner {
    await encoder.firstSubmissionIsBlocked()
  })

  await session.yield(.frame(try screenCaptureKitFrame(
    presentationValue: 2
  )))
  await session.yield(.frame(try screenCaptureKitFrame(
    presentationValue: 3
  )))
  await encoder.releaseFirstSubmission()
  #expect(await waitForScreenCaptureKitOwner {
    await encoder.snapshot().submissions.count == 2
  })

  let submissions = await encoder.snapshot().submissions
  #expect(submissions.map(\.sourceSequence) == [1, 2])
  #expect(submissions.map(\.presentationTime) == [
    CMTime(value: 1, timescale: 30),
    CMTime(value: 3, timescale: 30),
  ])
  try await owner.stop()
}

@Test func screenCaptureKitOwnerFailsClosedOnInvalidSampleOrEncoderError()
  async throws
{
  let invalidSession = ScreenCaptureKitStreamSessionProbeV0()
  let invalidEncoder = ScreenCaptureKitEncoderProbeV0()
  let invalidTerminal = ScreenCaptureKitTerminalProbeV0()
  let invalidOwner = ScreenCaptureKitStreamOwnerV0(
    session: invalidSession,
    encoder: invalidEncoder,
    terminal: invalidTerminal.record
  )
  try await invalidOwner.start()
  await invalidSession.yield(.invalidSample)
  #expect(
    await waitForScreenCaptureKitOwner {
      let phase = await invalidOwner.phase()
      let sessionStops = await invalidSession.calls().stops
      let encoderStops = await invalidEncoder.snapshot().stops
      return phase == .failed
        && invalidTerminal.reasons == [.invalidCaptureSample]
        && sessionStops == 1
        && encoderStops == 1
    })
  #expect(invalidTerminal.reasons == [.invalidCaptureSample])
  #expect(await invalidSession.calls().stops == 1)
  #expect(await invalidEncoder.snapshot().stops == 1)

  let rejectedSession = ScreenCaptureKitStreamSessionProbeV0()
  let rejectedEncoder = ScreenCaptureKitEncoderProbeV0(
    rejectsSubmission: true
  )
  let rejectedTerminal = ScreenCaptureKitTerminalProbeV0()
  let rejectedOwner = ScreenCaptureKitStreamOwnerV0(
    session: rejectedSession,
    encoder: rejectedEncoder,
    terminal: rejectedTerminal.record
  )
  try await rejectedOwner.start()
  await rejectedSession.yield(
    .frame(
      try screenCaptureKitFrame(
        presentationValue: 1
      )))
  #expect(
    await waitForScreenCaptureKitOwner {
      let phase = await rejectedOwner.phase()
      let sessionStops = await rejectedSession.calls().stops
      let encoderStops = await rejectedEncoder.snapshot().stops
      return phase == .failed
        && rejectedTerminal.reasons == [.encoderRejectedFrame]
        && sessionStops == 1
        && encoderStops == 1
    })
  #expect(rejectedTerminal.reasons == [.encoderRejectedFrame])
  #expect(await rejectedSession.calls().stops == 1)
  #expect(await rejectedEncoder.snapshot().stops == 1)
}

@Test func screenCaptureKitOwnerFailsClosedOnSystemStop() async throws {
  let session = ScreenCaptureKitStreamSessionProbeV0()
  let encoder = ScreenCaptureKitEncoderProbeV0()
  let terminal = ScreenCaptureKitTerminalProbeV0()
  let owner = ScreenCaptureKitStreamOwnerV0(
    session: session,
    encoder: encoder,
    terminal: terminal.record
  )
  try await owner.start()
  await session.yield(.stoppedBySystem)
  #expect(
    await waitForScreenCaptureKitOwner {
      await owner.phase() == .failed
    })
  #expect(terminal.reasons == [.captureStoppedBySystem])
  #expect(await session.calls().stops == 1)
  #expect(await encoder.snapshot().stops == 1)
}

@Test func screenCaptureKitOwnerStopsImmediatelyWhenEncoderTerminates()
  async throws
{
  let session = ScreenCaptureKitStreamSessionProbeV0()
  let encoder = ScreenCaptureKitEncoderProbeV0()
  let terminal = ScreenCaptureKitTerminalProbeV0()
  let owner = ScreenCaptureKitStreamOwnerV0(
    session: session,
    encoder: encoder,
    terminal: terminal.record
  )
  try await owner.start()

  await owner.encoderTerminated()

  #expect(await owner.phase() == .failed)
  #expect(terminal.reasons == [.encoderTerminated])
  #expect(await session.calls().stops == 1)
  #expect(await encoder.snapshot().stops == 1)
}

@Test func screenCaptureKitOwnerReportsStartAndStopFailuresExactlyOnce()
  async throws
{
  let failedStartSession = ScreenCaptureKitStreamSessionProbeV0(
    rejectsStart: true
  )
  let failedStartEncoder = ScreenCaptureKitEncoderProbeV0()
  let failedStartTerminal = ScreenCaptureKitTerminalProbeV0()
  let failedStartOwner = ScreenCaptureKitStreamOwnerV0(
    session: failedStartSession,
    encoder: failedStartEncoder,
    terminal: failedStartTerminal.record
  )
  await #expect(
    throws: ScreenCaptureKitStreamOwnerTestError.startRejected
  ) {
    try await failedStartOwner.start()
  }
  #expect(await failedStartOwner.phase() == .failed)
  #expect(failedStartTerminal.reasons == [.captureStartFailed])
  #expect(await failedStartSession.calls().stops == 1)
  #expect(await failedStartEncoder.snapshot().stops == 1)

  let failedStopSession = ScreenCaptureKitStreamSessionProbeV0(
    rejectsStop: true
  )
  let failedStopEncoder = ScreenCaptureKitEncoderProbeV0()
  let failedStopTerminal = ScreenCaptureKitTerminalProbeV0()
  let failedStopOwner = ScreenCaptureKitStreamOwnerV0(
    session: failedStopSession,
    encoder: failedStopEncoder,
    terminal: failedStopTerminal.record
  )
  try await failedStopOwner.start()
  await #expect(
    throws: ScreenCaptureKitStreamOwnerTestError.stopRejected
  ) {
    try await failedStopOwner.stop()
  }
  #expect(await failedStopOwner.phase() == .failed)
  #expect(failedStopTerminal.reasons == [.captureStopFailed])
  #expect(await failedStopSession.calls().stops == 1)
  #expect(await failedStopEncoder.snapshot().stops == 1)
}
