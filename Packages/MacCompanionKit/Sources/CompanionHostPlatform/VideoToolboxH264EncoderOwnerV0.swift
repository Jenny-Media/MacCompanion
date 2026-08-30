import CoreMedia
import CoreVideo
import Foundation

public enum VideoToolboxH264EncoderOwnerErrorV0:
  Error,
  Equatable,
  Sendable
{
  case stopped
  case invalidFrame
  case staleSourceSequence
  case stalePresentationTime
}

public enum VideoToolboxH264EncoderTerminationReasonV0:
  String,
  Equatable,
  Sendable
{
  case localStop
  case encodeSubmissionFailed
  case encodeCallbackFailed
  case requiredCleanKeyframeMissing
  case outputRejected
}

public enum VideoToolboxH264FrameSubmissionV0:
  Equatable,
  Sendable
{
  case started
  case queued
  case replacedStaleWaitingFrame
}

/// Ownership of the pixel buffer transfers for the duration of encode. The
/// capture adapter must not mutate or recycle it after submission. CoreVideo
/// buffers are reference types, so this narrow wrapper documents the external
/// lifetime rule behind the required unchecked conformance.
public struct VideoToolboxH264InputFrameV0: @unchecked Sendable {
  public let sourceSequence: UInt64
  public let pixelBuffer: CVPixelBuffer
  public let presentationTime: CMTime
  public let duration: CMTime

  public init(
    sourceSequence: UInt64,
    pixelBuffer: CVPixelBuffer,
    presentationTime: CMTime,
    duration: CMTime
  ) {
    self.sourceSequence = sourceSequence
    self.pixelBuffer = pixelBuffer
    self.presentationTime = presentationTime
    self.duration = duration
  }
}

public enum VideoToolboxH264SessionCompletionV0: Sendable {
  case success(VideoToolboxEncodedSampleV0)
  case failure
}

public protocol VideoToolboxH264EncodingSessionV0: Sendable {
  func encode(
    frame: VideoToolboxH264InputFrameV0,
    forceCleanKeyframe: Bool,
    completion:
      @escaping @Sendable (
        VideoToolboxH264SessionCompletionV0
      ) -> Void
  ) throws
  func invalidate()
}

/// Serial owner for the latency-first encoder boundary. It admits one frame
/// in VideoToolbox and retains at most one unencoded latest frame. Replacing a
/// stale waiter forces the replacement to be a clean keyframe.
public actor VideoToolboxH264EncoderOwnerV0 {
  private struct PendingFrame: Sendable {
    let frame: VideoToolboxH264InputFrameV0
    var forceCleanKeyframe: Bool
  }

  private let profile: VideoToolboxH264EncoderProfileV0
  private let session: any VideoToolboxH264EncodingSessionV0
  private let output:
    @Sendable (
      VideoToolboxEncodedSampleV0
    ) async -> Bool
  private let terminal:
    @Sendable (
      VideoToolboxH264EncoderTerminationReasonV0
    ) -> Void
  private var inFlight = false
  private var inFlightRequiresCleanKeyframe = false
  private var pending: PendingFrame?
  private var nextRequiresCleanKeyframe = true
  private var lastSourceSequence: UInt64 = 0
  private var lastPresentationTime: CMTime?
  private var stopped = false

  public init(
    profile: VideoToolboxH264EncoderProfileV0,
    session: any VideoToolboxH264EncodingSessionV0,
    output:
      @escaping @Sendable (
        VideoToolboxEncodedSampleV0
      ) async -> Bool,
    terminal:
      @escaping @Sendable (
        VideoToolboxH264EncoderTerminationReasonV0
      ) -> Void = { _ in }
  ) {
    self.profile = profile
    self.session = session
    self.output = output
    self.terminal = terminal
  }

  public func submit(
    _ frame: VideoToolboxH264InputFrameV0,
    forceCleanKeyframe: Bool = false
  ) throws -> VideoToolboxH264FrameSubmissionV0 {
    guard !stopped else {
      throw VideoToolboxH264EncoderOwnerErrorV0.stopped
    }
    try validate(frame)
    guard frame.sourceSequence > lastSourceSequence else {
      throw VideoToolboxH264EncoderOwnerErrorV0
        .staleSourceSequence
    }
    if let lastPresentationTime,
      CMTimeCompare(
        frame.presentationTime,
        lastPresentationTime
      ) <= 0
    {
      throw VideoToolboxH264EncoderOwnerErrorV0
        .stalePresentationTime
    }
    lastSourceSequence = frame.sourceSequence
    lastPresentationTime = frame.presentationTime

    let mustBeClean =
      forceCleanKeyframe
      || nextRequiresCleanKeyframe
    if inFlight {
      let didReplace = pending != nil
      pending = PendingFrame(
        frame: frame,
        forceCleanKeyframe: mustBeClean || didReplace
      )
      if didReplace { nextRequiresCleanKeyframe = true }
      return didReplace ? .replacedStaleWaitingFrame : .queued
    }
    try start(
      PendingFrame(
        frame: frame,
        forceCleanKeyframe: mustBeClean
      )
    )
    return .started
  }

  public func requestCleanKeyframe() {
    guard !stopped else { return }
    nextRequiresCleanKeyframe = true
    if pending != nil {
      pending?.forceCleanKeyframe = true
    }
  }

  public func stop() {
    terminate(.localStop)
  }

  private func validate(_ frame: VideoToolboxH264InputFrameV0) throws {
    guard frame.sourceSequence > 0,
      CVPixelBufferGetWidth(frame.pixelBuffer)
        == profile.capture.width,
      CVPixelBufferGetHeight(frame.pixelBuffer)
        == profile.capture.height,
      CVPixelBufferGetPixelFormatType(frame.pixelBuffer)
        == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
      frame.presentationTime.isNumeric,
      frame.presentationTime.value >= 0,
      frame.duration.isNumeric,
      frame.duration.value > 0
    else {
      throw VideoToolboxH264EncoderOwnerErrorV0.invalidFrame
    }
  }

  private func start(_ pending: PendingFrame) throws {
    inFlight = true
    inFlightRequiresCleanKeyframe = pending.forceCleanKeyframe
    if pending.forceCleanKeyframe {
      nextRequiresCleanKeyframe = false
    }
    do {
      try session.encode(
        frame: pending.frame,
        forceCleanKeyframe: pending.forceCleanKeyframe
      ) { [weak self] result in
        Task { await self?.completed(result) }
      }
    } catch {
      terminate(.encodeSubmissionFailed)
      throw error
    }
  }

  private func completed(
    _ result: VideoToolboxH264SessionCompletionV0
  ) async {
    guard !stopped, inFlight else { return }
    switch result {
    case .failure:
      terminate(.encodeCallbackFailed)
      return
    case .success(let sample):
      if inFlightRequiresCleanKeyframe,
        !sample.cleanKeyframe
      {
        terminate(.requiredCleanKeyframeMissing)
        return
      }
      guard await output(sample) else {
        terminate(.outputRejected)
        return
      }
    }
    // Publication is part of the one-frame in-flight boundary. Keep
    // `inFlight` set while awaiting the downstream media rendezvous so capture
    // callbacks can retain only the newest waiter instead of starting another
    // encode and overflowing the bounded publication path.
    inFlight = false
    inFlightRequiresCleanKeyframe = false
    guard let next = pending else { return }
    pending = nil
    do {
      try start(next)
    } catch {
      // `start` already performed the exactly-once terminal transition.
    }
  }

  private func terminate(
    _ reason: VideoToolboxH264EncoderTerminationReasonV0
  ) {
    guard !stopped else { return }
    stopped = true
    pending = nil
    session.invalidate()
    terminal(reason)
  }
}
