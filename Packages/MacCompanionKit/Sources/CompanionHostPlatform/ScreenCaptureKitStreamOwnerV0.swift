import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

public enum ScreenCaptureKitVideoSampleErrorV0:
  Error,
  Equatable,
  Sendable
{
  case sampleNotReady
  case invalidSampleCount
  case missingImageBuffer
  case invalidPixelBuffer
  case invalidPresentationTime
}

public enum ScreenCaptureKitVideoSampleAdmissionV0: @unchecked Sendable {
  case ignored
  case frame(ScreenCaptureKitVideoFrameV0)
}

/// A complete ScreenCaptureKit frame after all callback-local validation. The
/// pixel buffer is immutable by contract after admission and its ownership is
/// transferred to the encoder when the stream owner submits it.
public struct ScreenCaptureKitVideoFrameV0: @unchecked Sendable {
  public let pixelBuffer: CVPixelBuffer
  public let presentationTime: CMTime
  public let duration: CMTime

  init(
    pixelBuffer: CVPixelBuffer,
    presentationTime: CMTime,
    duration: CMTime
  ) {
    self.pixelBuffer = pixelBuffer
    self.presentationTime = presentationTime
    self.duration = duration
  }
}

@available(macOS 13.0, *)
public enum ScreenCaptureKitVideoSampleNormalizerV0 {
  public static func admit(
    _ sampleBuffer: CMSampleBuffer,
    profile: ScreenCaptureKitCaptureProfileV0
  ) throws -> ScreenCaptureKitVideoSampleAdmissionV0 {
    guard CMSampleBufferDataIsReady(sampleBuffer) else {
      throw ScreenCaptureKitVideoSampleErrorV0.sampleNotReady
    }
    guard CMSampleBufferGetNumSamples(sampleBuffer) == 1 else {
      throw ScreenCaptureKitVideoSampleErrorV0.invalidSampleCount
    }
    guard
      let attachments =
        (CMSampleBufferGetSampleAttachmentsArray(
          sampleBuffer,
          createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]])?.first,
      let rawStatus = attachments[.status] as? Int,
      let status = SCFrameStatus(rawValue: rawStatus),
      status == .complete
    else {
      return .ignored
    }
    guard
      let pixelBuffer = CMSampleBufferGetImageBuffer(
        sampleBuffer
      )
    else {
      throw ScreenCaptureKitVideoSampleErrorV0.missingImageBuffer
    }
    guard CVPixelBufferGetWidth(pixelBuffer) == profile.width,
      CVPixelBufferGetHeight(pixelBuffer) == profile.height,
      CVPixelBufferGetPixelFormatType(pixelBuffer)
        == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    else {
      throw ScreenCaptureKitVideoSampleErrorV0.invalidPixelBuffer
    }
    let presentationTime = CMSampleBufferGetPresentationTimeStamp(
      sampleBuffer
    )
    guard presentationTime.isNumeric,
      presentationTime.timescale > 0,
      presentationTime.value >= 0
    else {
      throw ScreenCaptureKitVideoSampleErrorV0
        .invalidPresentationTime
    }
    return .frame(
      ScreenCaptureKitVideoFrameV0(
        pixelBuffer: pixelBuffer,
        presentationTime: presentationTime,
        duration: CMTime(
          value: 1,
          timescale: CMTimeScale(profile.framesPerSecond)
        )
      ))
  }
}

public enum ScreenCaptureKitStreamEventV0: @unchecked Sendable {
  case frame(ScreenCaptureKitVideoFrameV0)
  case stoppedBySystem
  case invalidSample
}

public protocol ScreenCaptureKitStreamingSessionV0: Sendable {
  func start() async throws -> AsyncStream<ScreenCaptureKitStreamEventV0>
  func stop() async throws
}

public protocol ScreenCaptureKitVideoEncodingV0: Sendable {
  func submit(
    _ frame: VideoToolboxH264InputFrameV0,
    forceCleanKeyframe: Bool
  ) async throws -> VideoToolboxH264FrameSubmissionV0
  func stop() async
}

extension VideoToolboxH264EncoderOwnerV0:
  ScreenCaptureKitVideoEncodingV0
{}

public enum ScreenCaptureKitStreamOwnerPhaseV0:
  String,
  Equatable,
  Sendable
{
  case idle
  case starting
  case active
  case stopping
  case stopped
  case failed
}

public enum ScreenCaptureKitStreamOwnerErrorV0:
  Error,
  Equatable,
  Sendable
{
  case invalidState(ScreenCaptureKitStreamOwnerPhaseV0)
  case sourceSequenceExhausted
}

public enum ScreenCaptureKitStreamTerminationReasonV0:
  String,
  Equatable,
  Sendable
{
  case localStop
  case captureStartFailed
  case captureStopFailed
  case captureStoppedBySystem
  case invalidCaptureSample
  case encoderRejectedFrame
  case encoderTerminated
  case sourceSequenceExhausted
}

/// The single serialized owner from ScreenCaptureKit events to the encoder.
/// Its event stream retains at most one newest unconsumed callback, so capture
/// cannot grow tasks or buffers while VideoToolbox/runtime publication awaits.
public actor ScreenCaptureKitStreamOwnerV0 {
  private let session: any ScreenCaptureKitStreamingSessionV0
  private let encoder: any ScreenCaptureKitVideoEncodingV0
  private let terminal:
    @Sendable (
      ScreenCaptureKitStreamTerminationReasonV0
    ) -> Void
  private var phaseStorage: ScreenCaptureKitStreamOwnerPhaseV0 = .idle
  private var sourceSequence: UInt64 = 0
  private var consumer: Task<Void, Never>?
  private var terminalDelivered = false
  private var sequencingTail = Task<Void, Never> {}

  public init(
    session: any ScreenCaptureKitStreamingSessionV0,
    encoder: any ScreenCaptureKitVideoEncodingV0,
    terminal:
      @escaping @Sendable (
        ScreenCaptureKitStreamTerminationReasonV0
      ) -> Void = { _ in }
  ) {
    self.session = session
    self.encoder = encoder
    self.terminal = terminal
  }

  public func phase() -> ScreenCaptureKitStreamOwnerPhaseV0 {
    phaseStorage
  }

  public func start() async throws {
    let predecessor = sequencingTail
    let operation = Task { [self] in
      await predecessor.value
      try await performStart()
    }
    sequencingTail = Task { _ = try? await operation.value }
    return try await operation.value
  }

  public func stop() async throws {
    let predecessor = sequencingTail
    let operation = Task { [self] in
      await predecessor.value
      try await performStop()
    }
    sequencingTail = Task { _ = try? await operation.value }
    return try await operation.value
  }

  /// Wired to the VideoToolbox owner's terminal callback by production
  /// composition so capture stops even when no later frame arrives to observe
  /// the encoder's terminal state.
  public func encoderTerminated() async {
    await fail(.encoderTerminated)
  }

  private func performStart() async throws {
    guard phaseStorage == .idle else {
      throw
        ScreenCaptureKitStreamOwnerErrorV0
        .invalidState(phaseStorage)
    }
    phaseStorage = .starting
    let events: AsyncStream<ScreenCaptureKitStreamEventV0>
    do {
      events = try await session.start()
    } catch {
      phaseStorage = .failed
      try? await session.stop()
      await encoder.stop()
      deliverTerminal(.captureStartFailed)
      throw error
    }
    guard phaseStorage == .starting else {
      try? await session.stop()
      await encoder.stop()
      return
    }
    phaseStorage = .active
    consumer = Task { [weak self] in
      await self?.consume(events)
    }
  }

  private func performStop() async throws {
    switch phaseStorage {
    case .active, .starting:
      phaseStorage = .stopping
    case .stopped:
      return
    default:
      throw
        ScreenCaptureKitStreamOwnerErrorV0
        .invalidState(phaseStorage)
    }

    do {
      try await session.stop()
    } catch {
      consumer?.cancel()
      consumer = nil
      await encoder.stop()
      phaseStorage = .failed
      deliverTerminal(.captureStopFailed)
      throw error
    }
    consumer?.cancel()
    consumer = nil
    await encoder.stop()
    phaseStorage = .stopped
    deliverTerminal(.localStop)
  }

  private func consume(
    _ events: AsyncStream<ScreenCaptureKitStreamEventV0>
  ) async {
    for await event in events {
      guard phaseStorage == .active else { return }
      switch event {
      case .frame(let frame):
        guard sourceSequence < UInt64.max else {
          await fail(.sourceSequenceExhausted)
          return
        }
        sourceSequence += 1
        let input = VideoToolboxH264InputFrameV0(
          sourceSequence: sourceSequence,
          pixelBuffer: frame.pixelBuffer,
          presentationTime: frame.presentationTime,
          duration: frame.duration
        )
        do {
          _ = try await encoder.submit(
            input,
            forceCleanKeyframe: false
          )
        } catch {
          await fail(.encoderRejectedFrame)
          return
        }
      case .stoppedBySystem:
        await fail(.captureStoppedBySystem)
        return
      case .invalidSample:
        await fail(.invalidCaptureSample)
        return
      }
    }
    if phaseStorage == .active {
      await fail(.captureStoppedBySystem)
    }
  }

  private func fail(
    _ reason: ScreenCaptureKitStreamTerminationReasonV0
  ) async {
    guard phaseStorage == .active || phaseStorage == .starting else {
      return
    }
    phaseStorage = .failed
    try? await session.stop()
    await encoder.stop()
    consumer?.cancel()
    consumer = nil
    deliverTerminal(reason)
  }

  private func deliverTerminal(
    _ reason: ScreenCaptureKitStreamTerminationReasonV0
  ) {
    guard !terminalDelivered else { return }
    terminalDelivered = true
    terminal(reason)
  }
}

public enum ScreenCaptureKitStreamingSessionErrorV0:
  Error,
  Equatable,
  Sendable
{
  case invalidState
}

@available(macOS 13.0, *)
private final class ScreenCaptureKitStreamBridgeV0:
  NSObject,
  SCStreamOutput,
  SCStreamDelegate,
  @unchecked Sendable
{
  let events: AsyncStream<ScreenCaptureKitStreamEventV0>
  private let continuation: AsyncStream<ScreenCaptureKitStreamEventV0>.Continuation
  private let profile: ScreenCaptureKitCaptureProfileV0
  private let lock = NSLock()
  private var finished = false

  init(profile: ScreenCaptureKitCaptureProfileV0) {
    self.profile = profile
    let pair = AsyncStream.makeStream(
      of: ScreenCaptureKitStreamEventV0.self,
      bufferingPolicy: .bufferingNewest(1)
    )
    events = pair.stream
    continuation = pair.continuation
    super.init()
  }

  func stream(
    _ stream: SCStream,
    didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of outputType: SCStreamOutputType
  ) {
    guard outputType == .screen, !isFinished else { return }
    do {
      switch try ScreenCaptureKitVideoSampleNormalizerV0.admit(
        sampleBuffer,
        profile: profile
      ) {
      case .ignored:
        return
      case .frame(let frame):
        continuation.yield(.frame(frame))
      }
    } catch {
      finish(with: .invalidSample)
    }
  }

  func stream(_ stream: SCStream, didStopWithError error: any Error) {
    finish(with: .stoppedBySystem)
  }

  func finish(with event: ScreenCaptureKitStreamEventV0? = nil) {
    let shouldFinish = lock.withLock {
      guard !finished else { return false }
      finished = true
      return true
    }
    guard shouldFinish else { return }
    if let event { continuation.yield(event) }
    continuation.finish()
  }

  private var isFinished: Bool {
    lock.withLock { finished }
  }
}

/// Concrete ScreenCaptureKit adapter. Construction is inert; only `start()`
/// installs the output and asks macOS to begin capture. Physical TCC behavior
/// remains a signed-app evidence gate.
@available(macOS 13.0, *)
public actor ScreenCaptureKitStreamingSessionAdapterV0:
  ScreenCaptureKitStreamingSessionV0
{
  private enum State {
    case idle
    case active
    case stopped
  }

  private let stream: SCStream
  private let bridge: ScreenCaptureKitStreamBridgeV0
  private let callbackQueue: DispatchQueue
  private var state = State.idle

  public init(
    filter: SCContentFilter,
    profile: ScreenCaptureKitCaptureProfileV0,
    sourceRect: CGRect? = nil,
    callbackQueue: DispatchQueue = DispatchQueue(
      label: "com.jennymedia.maccompanion.capture.video",
      qos: .userInteractive
    )
  ) {
    let bridge = ScreenCaptureKitStreamBridgeV0(profile: profile)
    self.bridge = bridge
    self.callbackQueue = callbackQueue
    stream = SCStream(
      filter: filter,
      configuration:
        ScreenCaptureKitCaptureConfigurationV0
        .makeStreamConfiguration(
          profile: profile,
          sourceRect: sourceRect
        ),
      delegate: bridge
    )
  }

  public func start() async throws
    -> AsyncStream<ScreenCaptureKitStreamEventV0>
  {
    guard case .idle = state else {
      throw ScreenCaptureKitStreamingSessionErrorV0.invalidState
    }
    do {
      try stream.addStreamOutput(
        bridge,
        type: .screen,
        sampleHandlerQueue: callbackQueue
      )
      try await stream.startCapture()
      state = .active
      return bridge.events
    } catch {
      try? stream.removeStreamOutput(bridge, type: .screen)
      bridge.finish()
      state = .stopped
      throw error
    }
  }

  public func stop() async throws {
    switch state {
    case .idle:
      state = .stopped
      bridge.finish()
      return
    case .stopped:
      return
    case .active:
      state = .stopped
    }

    var stopError: (any Error)?
    do {
      try await stream.stopCapture()
    } catch {
      stopError = error
    }
    do {
      try stream.removeStreamOutput(bridge, type: .screen)
    } catch {
      if stopError == nil { stopError = error }
    }
    bridge.finish()
    if let stopError { throw stopError }
  }
}
