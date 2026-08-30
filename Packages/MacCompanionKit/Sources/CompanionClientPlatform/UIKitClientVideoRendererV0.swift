#if os(iOS)
import AVFoundation
import CompanionInteractiveClient
import CoreMedia
import CoreVideo
import Foundation
import UIKit

public enum UIKitClientVideoRendererErrorV0: Error, Equatable, Sendable {
    case invalidPixelBuffer
    case formatDescriptionCreationFailed
    case sampleBufferCreationFailed
    case displayLayerFailed
}

@MainActor
public protocol UIKitClientPixelBufferRenderingV0: AnyObject {
    func present(_ frame: VideoToolboxClientDecodedFrameV0) throws
    func blank()
}

/// A compile-checked aspect-fit display surface. Input mapping must use the
/// separately calculated content rectangle, never this view's whole bounds.
@MainActor
public final class UIKitClientVideoSurfaceViewV0:
    UIView,
    UIKitClientPixelBufferRenderingV0
{
    public override class var layerClass: AnyClass {
        AVSampleBufferDisplayLayer.self
    }

    private var displayLayer: AVSampleBufferDisplayLayer {
        layer as! AVSampleBufferDisplayLayer
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        backgroundColor = .black
        displayLayer.backgroundColor = UIColor.black.cgColor
        displayLayer.videoGravity = .resizeAspect
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    public func present(
        _ frame: VideoToolboxClientDecodedFrameV0
    ) throws {
        let receipt = frame.receipt
        guard CVPixelBufferGetWidth(frame.pixelBuffer)
                == Int(receipt.fence.encodedWidth),
              CVPixelBufferGetHeight(frame.pixelBuffer)
                == Int(receipt.fence.encodedHeight),
              CVPixelBufferGetPixelFormatType(frame.pixelBuffer)
                == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else {
            blank()
            throw UIKitClientVideoRendererErrorV0.invalidPixelBuffer
        }
        var description: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: frame.pixelBuffer,
            formatDescriptionOut: &description
        ) == noErr,
              let description else {
            blank()
            throw UIKitClientVideoRendererErrorV0
                .formatDescriptionCreationFailed
        }
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(
                value: Int64(receipt.presentationTimeNanoseconds),
                timescale: 1_000_000_000
            ),
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: frame.pixelBuffer,
            formatDescription: description,
            sampleTiming: &timing,
            sampleBufferOut: &sample
        ) == noErr,
              let sample else {
            blank()
            throw UIKitClientVideoRendererErrorV0
                .sampleBufferCreationFailed
        }
        // DisplayImmediately is a per-sample attachment, not a buffer-level
        // CMAttachmentBearer attachment. The latter is ignored by the display
        // layer and can leave decoded frames waiting on the remote Mac clock.
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sample, createIfNecessary: true
        ), CFArrayGetCount(attachments) == 1 else {
            blank()
            throw UIKitClientVideoRendererErrorV0.sampleBufferCreationFailed
        }
        let attachment = unsafeBitCast(
            CFArrayGetValueAtIndex(attachments, 0),
            to: CFMutableDictionary.self
        )
        CFDictionarySetValue(
            attachment,
            Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
            Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
        )
        guard displayLayer.status != .failed else {
            blank()
            throw UIKitClientVideoRendererErrorV0.displayLayerFailed
        }
        // Immediate samples replace pending images; flushing every frame can
        // repeatedly discard work before the display pipeline presents it.
        displayLayer.enqueue(sample)
        if displayLayer.status == .failed {
            blank()
            throw UIKitClientVideoRendererErrorV0.displayLayerFailed
        }
    }

    public func blank() {
        displayLayer.flushAndRemoveImage()
    }
}
#endif
