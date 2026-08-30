import CoreMedia
import CoreVideo
import Foundation
import Testing

@testable import CompanionHostPlatform

private enum VideoToolboxEncoderOwnerTestError: Error {
  case submissionFailed
  case pixelBufferCreationFailed
}

// Explicit opt-in: exercises this host's real encoder, using only synthetic
// pixel buffers. No screen capture, permissions, network, or input posting.
@Test(.enabled(if: ProcessInfo.processInfo.environment["MACCOMPANION_TEST_REAL_ENCODER"] == "1"), .timeLimit(.minutes(1)),
      arguments: [640, 641, 854, 855], [360, 361])
func realEncoderPreservesRequestedDimensions(width: Int, height: Int) async throws {
  let capture = try ScreenCaptureKitOpaqueTargetCatalogV0.captureProfile(logicalWidth: width, logicalHeight: height)
  let profile = try VideoToolboxH264EncoderProfileV0(
    capture: capture,
    targetBitrateBitsPerSecond: 1_000_000, keyframeIntervalMilliseconds: 2_000)
  let session = try VideoToolboxH264CompressionSessionV0(profile: profile)
  defer { session.invalidate() }
  var buffer: CVPixelBuffer?
  try #require(CVPixelBufferCreate(kCFAllocatorDefault, capture.width, capture.height,
    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
    [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer) == kCVReturnSuccess)
  let pixels = try #require(buffer)
  CVPixelBufferLockBaseAddress(pixels, [])
  for plane in 0..<CVPixelBufferGetPlaneCount(pixels) {
    if let base = CVPixelBufferGetBaseAddressOfPlane(pixels, plane) {
      memset(base, plane == 0 ? 16 : 128,
        CVPixelBufferGetBytesPerRowOfPlane(pixels, plane) * CVPixelBufferGetHeightOfPlane(pixels, plane))
    }
  }
  CVPixelBufferUnlockBaseAddress(pixels, [])
  let result = try await withCheckedThrowingContinuation { continuation in
    do {
      try session.encode(frame: .init(sourceSequence: 1, pixelBuffer: pixels,
        presentationTime: CMTime(value: 1, timescale: 30), duration: CMTime(value: 1, timescale: 30)),
        forceCleanKeyframe: true, completion: { continuation.resume(returning: $0) })
    } catch { continuation.resume(throwing: error) }
  }
  guard case .success(let sample) = result else {
    Issue.record("Real encoder failed to produce a sample")
    return
  }
  #expect(Int(sample.width) == capture.width)
  #expect(Int(sample.height) == capture.height)
}

private final class VideoToolboxEncoderOwnerFakeSessionV0:
  VideoToolboxH264EncodingSessionV0,
  @unchecked Sendable
{
  struct Request: @unchecked Sendable {
    let sequence: UInt64
    let forceCleanKeyframe: Bool
    let completion:
      @Sendable (
        VideoToolboxH264SessionCompletionV0
      ) -> Void
  }

  private let lock = NSLock()
  private var requestsStorage: [Request] = []
  private var invalidations = 0
  private var rejectSubmission = false

  var requests: [Request] { lock.withLock { requestsStorage } }
  var invalidateCount: Int { lock.withLock { invalidations } }

  func rejectNextSubmission() {
    lock.withLock { rejectSubmission = true }
  }

  func encode(
    frame: VideoToolboxH264InputFrameV0,
    forceCleanKeyframe: Bool,
    completion:
      @escaping @Sendable (
        VideoToolboxH264SessionCompletionV0
      ) -> Void
  ) throws {
    try lock.withLock {
      if rejectSubmission {
        rejectSubmission = false
        throw VideoToolboxEncoderOwnerTestError.submissionFailed
      }
      requestsStorage.append(
        Request(
          sequence: frame.sourceSequence,
          forceCleanKeyframe: forceCleanKeyframe,
          completion: completion
        ))
    }
  }

  func invalidate() {
    lock.withLock { invalidations += 1 }
  }

  func complete(
    request index: Int,
    with result: VideoToolboxH264SessionCompletionV0
  ) {
    requests[index].completion(result)
  }
}

private final class VideoToolboxEncoderOwnerRecorderV0:
  @unchecked Sendable
{
  private let lock = NSLock()
  private var outputsStorage: [VideoToolboxEncodedSampleV0] = []
  private var terminalsStorage: [VideoToolboxH264EncoderTerminationReasonV0] = []
  private var acceptsOutput = true

  var outputs: [VideoToolboxEncodedSampleV0] {
    lock.withLock { outputsStorage }
  }
  var terminals: [VideoToolboxH264EncoderTerminationReasonV0] {
    lock.withLock { terminalsStorage }
  }

  func rejectOutputs() {
    lock.withLock { acceptsOutput = false }
  }

  func output(_ sample: VideoToolboxEncodedSampleV0) -> Bool {
    lock.withLock {
      guard acceptsOutput else { return false }
      outputsStorage.append(sample)
      return true
    }
  }

  func terminal(_ reason: VideoToolboxH264EncoderTerminationReasonV0) {
    lock.withLock { terminalsStorage.append(reason) }
  }
}

private actor VideoToolboxEncoderOutputGateV0 {
  private var enteredStorage = false
  private var continuation: CheckedContinuation<Bool, Never>?

  func accept(_ sample: VideoToolboxEncodedSampleV0) async -> Bool {
    enteredStorage = true
    return await withCheckedContinuation { continuation = $0 }
  }

  func entered() -> Bool { enteredStorage }

  func release() {
    continuation?.resume(returning: true)
    continuation = nil
  }
}

private func videoToolboxEncoderOwnerProfile() throws
  -> VideoToolboxH264EncoderProfileV0
{
  try VideoToolboxH264EncoderProfileV0(
    capture: ScreenCaptureKitCaptureProfileV0(
      width: 4,
      height: 4,
      framesPerSecond: 30,
      queueDepth: 2
    ),
    targetBitrateBitsPerSecond: 1_000_000,
    keyframeIntervalMilliseconds: 2_000
  )
}

private func videoToolboxEncoderOwnerFrame(
  sequence: UInt64,
  presentationTime: CMTime? = nil
) throws -> VideoToolboxH264InputFrameV0 {
  var pixelBuffer: CVPixelBuffer?
  guard
    CVPixelBufferCreate(
      kCFAllocatorDefault,
      4,
      4,
      kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
      nil,
      &pixelBuffer
    ) == kCVReturnSuccess,
    let pixelBuffer
  else {
    throw VideoToolboxEncoderOwnerTestError
      .pixelBufferCreationFailed
  }
  return VideoToolboxH264InputFrameV0(
    sourceSequence: sequence,
    pixelBuffer: pixelBuffer,
    presentationTime: presentationTime
      ?? CMTime(value: Int64(sequence), timescale: 30),
    duration: CMTime(value: 1, timescale: 30)
  )
}

@Test func encoderOwnerRejectsSequenceAndTimelineRollback() async throws {
  let session = VideoToolboxEncoderOwnerFakeSessionV0()
  let recorder = VideoToolboxEncoderOwnerRecorderV0()
  let owner = VideoToolboxH264EncoderOwnerV0(
    profile: try videoToolboxEncoderOwnerProfile(),
    session: session,
    output: recorder.output,
    terminal: recorder.terminal
  )
  _ = try await owner.submit(videoToolboxEncoderOwnerFrame(sequence: 2))
  await #expect(
    throws:
      VideoToolboxH264EncoderOwnerErrorV0.staleSourceSequence
  ) {
    _ = try await owner.submit(
      videoToolboxEncoderOwnerFrame(sequence: 2)
    )
  }
  await #expect(
    throws:
      VideoToolboxH264EncoderOwnerErrorV0.stalePresentationTime
  ) {
    _ = try await owner.submit(
      videoToolboxEncoderOwnerFrame(
        sequence: 3,
        presentationTime: CMTime(value: 1, timescale: 30)
      )
    )
  }
  #expect(session.requests.count == 1)
}

private func videoToolboxEncoderOwnerSample(
  cleanKeyframe: Bool,
  marker: UInt64
) -> VideoToolboxEncodedSampleV0 {
  VideoToolboxEncodedSampleV0(
    decoderConfiguration: Data([UInt8(marker & 0xff)]),
    accessUnit: Data([UInt8(marker & 0xff)]),
    cleanKeyframe: cleanKeyframe,
    width: 4,
    height: 4,
    presentationTimeNanoseconds: marker
  )
}

private func waitForEncoderOwner(
  _ condition: @escaping @Sendable () async -> Bool
) async -> Bool {
  for _ in 0..<1_000 {
    if await condition() { return true }
    await Task.yield()
  }
  return await condition()
}

@Test func encoderOwnerRequiresInitialCleanKeyframeAndPublishesOnce()
  async throws
{
  let session = VideoToolboxEncoderOwnerFakeSessionV0()
  let recorder = VideoToolboxEncoderOwnerRecorderV0()
  let owner = VideoToolboxH264EncoderOwnerV0(
    profile: try videoToolboxEncoderOwnerProfile(),
    session: session,
    output: recorder.output,
    terminal: recorder.terminal
  )

  #expect(
    try await owner.submit(
      videoToolboxEncoderOwnerFrame(sequence: 1)
    ) == .started
  )
  #expect(session.requests.count == 1)
  #expect(session.requests[0].forceCleanKeyframe)
  session.complete(
    request: 0,
    with: .success(
      videoToolboxEncoderOwnerSample(
        cleanKeyframe: true,
        marker: 1
      )
    )
  )

  #expect(await waitForEncoderOwner { recorder.outputs.count == 1 })
  #expect(recorder.terminals.isEmpty)
  #expect(session.invalidateCount == 0)
}

@Test func encoderOwnerKeepsOnlyLatestWaiterAndForcesItClean()
  async throws
{
  let session = VideoToolboxEncoderOwnerFakeSessionV0()
  let recorder = VideoToolboxEncoderOwnerRecorderV0()
  let owner = VideoToolboxH264EncoderOwnerV0(
    profile: try videoToolboxEncoderOwnerProfile(),
    session: session,
    output: recorder.output,
    terminal: recorder.terminal
  )
  _ = try await owner.submit(videoToolboxEncoderOwnerFrame(sequence: 1))
  #expect(
    try await owner.submit(
      videoToolboxEncoderOwnerFrame(sequence: 2)
    ) == .queued
  )
  #expect(
    try await owner.submit(
      videoToolboxEncoderOwnerFrame(sequence: 3)
    ) == .replacedStaleWaitingFrame
  )
  #expect(session.requests.count == 1)

  session.complete(
    request: 0,
    with: .success(
      videoToolboxEncoderOwnerSample(
        cleanKeyframe: true,
        marker: 1
      )
    )
  )
  #expect(await waitForEncoderOwner { session.requests.count == 2 })
  #expect(session.requests[1].sequence == 3)
  #expect(session.requests[1].forceCleanKeyframe)
  session.complete(
    request: 1,
    with: .success(
      videoToolboxEncoderOwnerSample(
        cleanKeyframe: true,
        marker: 3
      )
    )
  )
  #expect(await waitForEncoderOwner { recorder.outputs.count == 2 })
  #expect(recorder.outputs.map(\.presentationTimeNanoseconds) == [1, 3])
}

@Test func encoderOwnerAwaitsPublicationBeforeStartingWaitingFrame()
  async throws
{
  let session = VideoToolboxEncoderOwnerFakeSessionV0()
  let gate = VideoToolboxEncoderOutputGateV0()
  let owner = VideoToolboxH264EncoderOwnerV0(
    profile: try videoToolboxEncoderOwnerProfile(),
    session: session,
    output: gate.accept
  )
  _ = try await owner.submit(videoToolboxEncoderOwnerFrame(sequence: 1))
  _ = try await owner.submit(videoToolboxEncoderOwnerFrame(sequence: 2))

  session.complete(
    request: 0,
    with: .success(
      videoToolboxEncoderOwnerSample(
        cleanKeyframe: true,
        marker: 1
      ))
  )
  #expect(await waitForEncoderOwner { await gate.entered() })
  #expect(session.requests.count == 1)

  await gate.release()
  #expect(await waitForEncoderOwner { session.requests.count == 2 })
  #expect(session.requests[1].sequence == 2)
}

@Test func encoderOwnerRetainsBackpressureAcrossSuspendedPublication()
  async throws
{
  let session = VideoToolboxEncoderOwnerFakeSessionV0()
  let gate = VideoToolboxEncoderOutputGateV0()
  let owner = VideoToolboxH264EncoderOwnerV0(
    profile: try videoToolboxEncoderOwnerProfile(),
    session: session,
    output: gate.accept
  )
  _ = try await owner.submit(videoToolboxEncoderOwnerFrame(sequence: 1))
  session.complete(
    request: 0,
    with: .success(
      videoToolboxEncoderOwnerSample(
        cleanKeyframe: true,
        marker: 1
      ))
  )
  #expect(await waitForEncoderOwner { await gate.entered() })

  #expect(
    try await owner.submit(
      videoToolboxEncoderOwnerFrame(sequence: 2)
    ) == .queued
  )
  #expect(
    try await owner.submit(
      videoToolboxEncoderOwnerFrame(sequence: 3)
    ) == .replacedStaleWaitingFrame
  )
  #expect(session.requests.count == 1)

  await gate.release()
  #expect(await waitForEncoderOwner { session.requests.count == 2 })
  #expect(session.requests[1].sequence == 3)
  #expect(session.requests[1].forceCleanKeyframe)
}

@Test func encoderOwnerFailsClosedWhenForcedFrameIsNotClean()
  async throws
{
  let session = VideoToolboxEncoderOwnerFakeSessionV0()
  let recorder = VideoToolboxEncoderOwnerRecorderV0()
  let owner = VideoToolboxH264EncoderOwnerV0(
    profile: try videoToolboxEncoderOwnerProfile(),
    session: session,
    output: recorder.output,
    terminal: recorder.terminal
  )
  _ = try await owner.submit(videoToolboxEncoderOwnerFrame(sequence: 1))

  session.complete(
    request: 0,
    with: .success(
      videoToolboxEncoderOwnerSample(
        cleanKeyframe: false,
        marker: 1
      )
    )
  )

  #expect(await waitForEncoderOwner { !recorder.terminals.isEmpty })
  #expect(recorder.terminals == [.requiredCleanKeyframeMissing])
  #expect(recorder.outputs.isEmpty)
  #expect(session.invalidateCount == 1)
}

@Test func encoderOwnerOutputRejectionTerminatesAndIgnoresLateCallback()
  async throws
{
  let session = VideoToolboxEncoderOwnerFakeSessionV0()
  let recorder = VideoToolboxEncoderOwnerRecorderV0()
  recorder.rejectOutputs()
  let owner = VideoToolboxH264EncoderOwnerV0(
    profile: try videoToolboxEncoderOwnerProfile(),
    session: session,
    output: recorder.output,
    terminal: recorder.terminal
  )
  _ = try await owner.submit(videoToolboxEncoderOwnerFrame(sequence: 1))
  session.complete(
    request: 0,
    with: .success(
      videoToolboxEncoderOwnerSample(
        cleanKeyframe: true,
        marker: 1
      )
    )
  )
  #expect(await waitForEncoderOwner { !recorder.terminals.isEmpty })
  session.complete(request: 0, with: .failure)
  await Task.yield()

  #expect(recorder.terminals == [.outputRejected])
  #expect(session.invalidateCount == 1)
}

@Test func encoderOwnerStopAndSubmissionFailureAreExactlyOnce()
  async throws
{
  let stoppedSession = VideoToolboxEncoderOwnerFakeSessionV0()
  let stoppedRecorder = VideoToolboxEncoderOwnerRecorderV0()
  let stoppedOwner = VideoToolboxH264EncoderOwnerV0(
    profile: try videoToolboxEncoderOwnerProfile(),
    session: stoppedSession,
    output: stoppedRecorder.output,
    terminal: stoppedRecorder.terminal
  )
  _ = try await stoppedOwner.submit(
    videoToolboxEncoderOwnerFrame(sequence: 1)
  )
  await stoppedOwner.stop()
  stoppedSession.complete(request: 0, with: .failure)
  await Task.yield()
  #expect(stoppedRecorder.terminals == [.localStop])
  #expect(stoppedSession.invalidateCount == 1)

  let failedSession = VideoToolboxEncoderOwnerFakeSessionV0()
  failedSession.rejectNextSubmission()
  let failedRecorder = VideoToolboxEncoderOwnerRecorderV0()
  let failedOwner = VideoToolboxH264EncoderOwnerV0(
    profile: try videoToolboxEncoderOwnerProfile(),
    session: failedSession,
    output: failedRecorder.output,
    terminal: failedRecorder.terminal
  )
  await #expect(throws: VideoToolboxEncoderOwnerTestError.submissionFailed) {
    _ = try await failedOwner.submit(
      videoToolboxEncoderOwnerFrame(sequence: 1)
    )
  }
  #expect(failedRecorder.terminals == [.encodeSubmissionFailed])
  #expect(failedSession.invalidateCount == 1)
}
