import CompanionIPC
import CompanionInteractiveRuntime
import CompanionInteractiveShared
import CompanionInteractiveWire
import Foundation
import OSLog

private let interactiveMediaPublisherLoggerV0 = Logger(
  subsystem: "media.jenny.maccompanion", category: "interactive-media-publisher")

public enum VideoToolboxInteractiveMediaPublisherPhaseV0:
  String,
  Equatable,
  Sendable
{
  case active
  case ended
  case failed
}

public enum VideoToolboxInteractiveMediaPublisherErrorV0:
  Error,
  Equatable,
  Sendable
{
  case bindingMismatch
}

/// One exact surface and execution-lease fence. A replacement binding can be
/// installed only through the publisher's sequence-preserving transition.
public struct InteractiveMediaPublicationBindingV0: Equatable, Sendable {
  public let fence: InteractiveCommandFence
  public let encodedWidth: UInt16
  public let encodedHeight: UInt16

  public init(
    fence: InteractiveCommandFence,
    descriptor: AdaptiveSurfaceDescriptor
  ) throws {
    do {
      try descriptor.validate()
    } catch {
      throw VideoToolboxInteractiveMediaPublisherErrorV0
        .bindingMismatch
    }
    guard
      fence.interactiveSessionID
        == descriptor.interactiveSessionID,
      fence.authorizationEpoch == descriptor.authorizationEpoch,
      fence.surfaceID == descriptor.surfaceID,
      fence.surfaceRevision.rawValue
        == descriptor.surfaceRevision.rawValue,
      fence.coordinateRevision.rawValue
        == descriptor.coordinateSpaceRevision.rawValue,
      descriptor.interactionClasses.contains(.view)
    else {
      throw VideoToolboxInteractiveMediaPublisherErrorV0
        .bindingMismatch
    }
    self.fence = fence
    encodedWidth = descriptor.encodedWidth
    encodedHeight = descriptor.encodedHeight
  }
}

public protocol InteractiveMediaRuntimePublishingV0: Sendable {
  func publishMedia(
    _ action: InteractiveRuntimeMediaActionV0,
    nowMonotonicNanoseconds: UInt64
  ) async throws
}

extension InteractiveMenuRuntimeOwnerV0:
  InteractiveMediaRuntimePublishingV0
{}

/// Converts validated VideoToolbox output into the normative media record
/// sequence and submits every record through the lease-validating menu runtime.
/// No detached work or secondary byte queue is created here: the encoder does
/// not admit its next frame until this publisher receives a definitive result.
public actor VideoToolboxInteractiveMediaPublisherV0 {
  private var binding: InteractiveMediaPublicationBindingV0
  private let runtime: any InteractiveMediaRuntimePublishingV0
  private let clock: @Sendable () -> UInt64
  private let commandID: @Sendable () -> UUID
  private var phaseStorage: VideoToolboxInteractiveMediaPublisherPhaseV0 = .active
  private var mediaSequence: UInt64 = 0
  private var lastPresentationTimeNanoseconds: UInt64?
  private var decoderConfiguration: Data?
  private var cleanKeyframeRequired = true
  private var initialDiscontinuityRequired: Bool

  public init(
    binding: InteractiveMediaPublicationBindingV0,
    runtime: any InteractiveMediaRuntimePublishingV0,
    resumingAfterMediaSequence: UInt64? = nil,
    clock: @escaping @Sendable () -> UInt64 = {
      DispatchTime.now().uptimeNanoseconds
    },
    commandID: @escaping @Sendable () -> UUID = { UUID() }
  ) {
    self.binding = binding
    self.runtime = runtime
    mediaSequence = resumingAfterMediaSequence ?? 0
    initialDiscontinuityRequired = resumingAfterMediaSequence != nil
    self.clock = clock
    self.commandID = commandID
  }

  public func phase() -> VideoToolboxInteractiveMediaPublisherPhaseV0 {
    phaseStorage
  }

  /// Replaces only the lease identity for the current surface. Media sequence,
  /// decoder state, and presentation time remain continuous, so a routine
  /// lease renewal never invents a surface discontinuity or keyframe demand.
  public func adoptLeaseRenewal(
    to replacement: InteractiveMediaPublicationBindingV0
  ) -> Bool {
    guard phaseStorage == .active,
      replacement.fence.leaseID != binding.fence.leaseID,
      replacement.fence.hostID == binding.fence.hostID,
      replacement.fence.deviceID == binding.fence.deviceID,
      replacement.fence.interactiveSessionID
        == binding.fence.interactiveSessionID,
      replacement.fence.authorizationEpoch
        == binding.fence.authorizationEpoch,
      replacement.fence.selectedDisplayID
        == binding.fence.selectedDisplayID,
      replacement.fence.surfaceID == binding.fence.surfaceID,
      replacement.fence.surfaceRevision
        == binding.fence.surfaceRevision,
      replacement.fence.coordinateRevision
        == binding.fence.coordinateRevision,
      replacement.encodedWidth == binding.encodedWidth,
      replacement.encodedHeight == binding.encodedHeight
    else { return false }
    binding = replacement
    return true
  }

  /// Returns only after both the configuration (when needed) and access unit
  /// have been accepted by the runtime. Any malformed sample or rejection is
  /// terminal so a partially published decoder transition cannot be reused.
  public func publish(_ sample: VideoToolboxEncodedSampleV0) async -> Bool {
    guard phaseStorage == .active else { return false }
    guard sample.width == binding.encodedWidth,
      sample.height == binding.encodedHeight,
      lastPresentationTimeNanoseconds.map({
        sample.presentationTimeNanoseconds >= $0
      }) ?? true
    else {
      interactiveMediaPublisherLoggerV0.error(
        "encoded sample rejected expected=\(self.binding.encodedWidth)x\(self.binding.encodedHeight) actual=\(sample.width)x\(sample.height) timelineValid=\(self.lastPresentationTimeNanoseconds.map { sample.presentationTimeNanoseconds >= $0 } ?? true)")
      fail()
      return false
    }

    // Construction/activation cannot publish into a runtime that is still
    // serializing the surface transition. The first clean output starts the
    // replacement sequence, independently of any retired publisher callbacks.
    if initialDiscontinuityRequired {
      guard sample.cleanKeyframe,
        await publishRecord(
          type: .discontinuity,
          payload: Data(),
          presentationTimeNanoseconds: sample.presentationTimeNanoseconds,
          cleanKeyframe: false,
          includesDimensions: false
        )
      else {
        fail()
        return false
      }
      initialDiscontinuityRequired = false
    }

    let configurationChanged =
      decoderConfiguration
      != sample.decoderConfiguration
    if configurationChanged {
      guard sample.cleanKeyframe,
        await publishRecord(
          type: .decoderConfiguration,
          payload: sample.decoderConfiguration,
          presentationTimeNanoseconds:
            sample.presentationTimeNanoseconds,
          cleanKeyframe: false,
          includesDimensions: true
        )
      else {
        fail()
        return false
      }
      decoderConfiguration = sample.decoderConfiguration
      cleanKeyframeRequired = true
    }

    guard !cleanKeyframeRequired || sample.cleanKeyframe,
      await publishRecord(
        type: .videoAccessUnit,
        payload: sample.accessUnit,
        presentationTimeNanoseconds:
          sample.presentationTimeNanoseconds,
        cleanKeyframe: sample.cleanKeyframe,
        includesDimensions: true
      )
    else {
      fail()
      return false
    }
    cleanKeyframeRequired = false
    return true
  }

  /// Activates a descriptor/lease replacement only after the runtime accepts
  /// a discontinuity carrying the new complete fence. Sequence and timeline
  /// remain continuous across the transition; configuration and a clean frame
  /// are required before the new surface can become acknowledgement-ready.
  public func transition(
    to replacement: InteractiveMediaPublicationBindingV0,
    presentationTimeNanoseconds: UInt64
  ) async -> Bool {
    guard phaseStorage == .active else { return false }
    guard
      replacement.fence.interactiveSessionID
        == binding.fence.interactiveSessionID,
      replacement.fence.authorizationEpoch
        == binding.fence.authorizationEpoch,
      replacement.fence.surfaceRevision.rawValue
        > binding.fence.surfaceRevision.rawValue,
      replacement.fence.coordinateRevision.rawValue
        > binding.fence.coordinateRevision.rawValue,
      await publishRecord(
        type: .discontinuity,
        payload: Data(),
        presentationTimeNanoseconds:
          presentationTimeNanoseconds,
        cleanKeyframe: false,
        includesDimensions: false,
        using: replacement
      )
    else {
      fail()
      return false
    }
    binding = replacement
    decoderConfiguration = nil
    cleanKeyframeRequired = true
    return true
  }

  /// Marks a capture/encoder interruption under the same exact surface. The
  /// next accepted sample must republish configuration and be a clean frame.
  public func publishDiscontinuity(
    presentationTimeNanoseconds: UInt64
  ) async -> Bool {
    guard phaseStorage == .active else { return false }
    guard
      await publishRecord(
        type: .discontinuity,
        payload: Data(),
        presentationTimeNanoseconds:
          presentationTimeNanoseconds,
        cleanKeyframe: false,
        includesDimensions: false
      )
    else {
      fail()
      return false
    }
    decoderConfiguration = nil
    cleanKeyframeRequired = true
    return true
  }

  public func publishEnd(
    presentationTimeNanoseconds: UInt64
  ) async -> Bool {
    guard phaseStorage == .active else { return false }
    guard
      await publishRecord(
        type: .end,
        payload: Data(),
        presentationTimeNanoseconds:
          presentationTimeNanoseconds,
        cleanKeyframe: false,
        includesDimensions: false
      )
    else {
      fail()
      return false
    }
    decoderConfiguration = nil
    cleanKeyframeRequired = true
    phaseStorage = .ended
    return true
  }

  private func publishRecord(
    type: MediaRecordType,
    payload: Data,
    presentationTimeNanoseconds: UInt64,
    cleanKeyframe: Bool,
    includesDimensions: Bool,
    using publicationBinding:
      InteractiveMediaPublicationBindingV0? = nil,
    mayRetryRenewal: Bool = true
  ) async -> Bool {
    let publicationBinding = publicationBinding ?? binding
    guard mediaSequence < UInt64.max,
      let payloadLength = UInt32(exactly: payload.count),
      lastPresentationTimeNanoseconds.map({
        presentationTimeNanoseconds >= $0
      }) ?? true
    else {
      return false
    }
    let nextSequence = mediaSequence + 1
    do {
      let header = try MediaRecordHeader(
        type: type,
        flags: cleanKeyframe ? [.cleanKeyframe] : [],
        payloadLength: payloadLength,
        interactiveSessionID:
          publicationBinding.fence.interactiveSessionID,
        authorizationEpoch:
          publicationBinding.fence.authorizationEpoch,
        surfaceID: publicationBinding.fence.surfaceID,
        surfaceRevision: .init(
          rawValue:
            publicationBinding.fence.surfaceRevision.rawValue
        ),
        coordinateSpaceRevision: .init(
          rawValue:
            publicationBinding.fence.coordinateRevision.rawValue
        ),
        mediaSequence: nextSequence,
        presentationTimeNanoseconds:
          presentationTimeNanoseconds,
        encodedWidth:
          includesDimensions
          ? publicationBinding.encodedWidth : 0,
        encodedHeight:
          includesDimensions
          ? publicationBinding.encodedHeight : 0
      )
      let action = try InteractiveRuntimeMediaActionV0(
        commandID: commandID(),
        fence: publicationBinding.fence,
        header: header,
        payload: payload
      )
      try await runtime.publishMedia(
        action,
        nowMonotonicNanoseconds: clock()
      )
      mediaSequence = nextSequence
      lastPresentationTimeNanoseconds = presentationTimeNanoseconds
      return true
    } catch {
      // Only typed runtime/lease errors and numeric record metadata; never
      // media bytes, focus contents, or arbitrary platform error strings.
      if let failure = error as? InteractiveMenuRuntimeErrorV0 {
        interactiveMediaPublisherLoggerV0.error("media record rejected type=\(type.rawValue) sequence=\(nextSequence) runtime=\(String(describing: failure), privacy: .public)")
      } else if let failure = error as? InteractiveLeaseError {
        interactiveMediaPublisherLoggerV0.error("media record rejected type=\(type.rawValue) sequence=\(nextSequence) lease=\(String(describing: failure), privacy: .public)")
      } else {
        interactiveMediaPublisherLoggerV0.error("media record rejected type=\(type.rawValue) sequence=\(nextSequence) otherError")
      }
      // A stale-lease rejection occurs before runtime sequence/effect commit.
      // A concurrent authoritative renewal may already have updated our local
      // binding. Retry once with that exact new lease; the runtime still
      // rejects all stale leases and validates the complete current fence.
      guard mayRetryRenewal, error as? InteractiveLeaseError == .staleLease,
        phaseStorage == .active,
        binding.fence.leaseID != publicationBinding.fence.leaseID,
        binding.fence.hostID == publicationBinding.fence.hostID,
        binding.fence.deviceID == publicationBinding.fence.deviceID,
        binding.fence.interactiveSessionID == publicationBinding.fence.interactiveSessionID,
        binding.fence.authorizationEpoch == publicationBinding.fence.authorizationEpoch,
        binding.fence.selectedDisplayID == publicationBinding.fence.selectedDisplayID,
        binding.fence.surfaceID == publicationBinding.fence.surfaceID,
        binding.fence.surfaceRevision == publicationBinding.fence.surfaceRevision,
        binding.fence.coordinateRevision == publicationBinding.fence.coordinateRevision,
        binding.encodedWidth == publicationBinding.encodedWidth,
        binding.encodedHeight == publicationBinding.encodedHeight else { return false }
      return await publishRecord(type: type, payload: payload,
        presentationTimeNanoseconds: presentationTimeNanoseconds,
        cleanKeyframe: cleanKeyframe, includesDimensions: includesDimensions,
        using: binding, mayRetryRenewal: false)
    }
  }

  private func fail() {
    phaseStorage = .failed
    decoderConfiguration = nil
    cleanKeyframeRequired = true
  }
}
