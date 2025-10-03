#if canImport(UIKit)
import UIKit
import AVFoundation

/// Errors the can occur when rendering images.
internal enum HighPerformanceImageViewError: Error {
    case invalidFormat
    case invalidImageData
    case setupError
}

/// Class to render pixel buffers to the screen. If you're rendering CascableCore live view frames, it's reccommended
/// that you use `CameraLiveViewController` instead.
internal class HighPerformanceImageView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }

    private func setup() {
        isUserInteractionEnabled = false
        refreshSampleView()
    }

    // MARK: - API

    /// Clear the view.
    func clearDisplay() {
        lastSize = nil
        lastFormat = nil
        lastCrop = nil
        lastOrientation = nil
        sampleView?.clearImage()
    }

    /// Display the given JPEG image data.
    ///
    /// - Parameters:
    ///   - data: The JPEG image data.
    ///   - size: The size of the image, in pixels.
    ///   - crop: The crop to apply to the image, relative to the image size. Pass `{.zero, .size}` if no crop should be applied.
    ///   - orientation: The orientation of the image.
    /// - Throws: Throws an error of type `HighPerformanceImageViewError` if an error occurs.
    func display(imageData data: Data, ofSize size: CGSize, croppingTo crop: CGRect, orientation: UIImage.Orientation) throws(HighPerformanceImageViewError) {

        if size != lastSize {
            var newFormat: CMFormatDescription? = nil
            let success = CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: kCMVideoCodecType_JPEG, width: Int32(size.width), height: Int32(size.height), extensions: nil, formatDescriptionOut: &newFormat)
            guard newFormat != nil, success == noErr else {
                throw HighPerformanceImageViewError.invalidFormat
            }
            lastFormat = newFormat
        }

        let buffer: CMBlockBuffer
        do { buffer = try data.toCMBlockBuffer() }
        catch { throw HighPerformanceImageViewError.invalidImageData }

        var timingInfo = CMSampleTimingInfo(duration: CMTime.invalid, presentationTimeStamp: CMTime.zero, decodeTimeStamp: CMTime.invalid)
        var sampleSize = data.count

        var createdSample: CMSampleBuffer? = nil
        let success = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: buffer,
                                                formatDescription: lastFormat!, sampleCount: 1, sampleTimingEntryCount: 1,
                                                sampleTimingArray: &timingInfo, sampleSizeEntryCount: 1,
                                                sampleSizeArray: &sampleSize, sampleBufferOut: &createdSample)

        guard let sample = createdSample, success == noErr else {
            throw HighPerformanceImageViewError.invalidImageData
        }

        guard let bufferAttachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) else {
            throw HighPerformanceImageViewError.setupError
        }

        let firstSampleAttachment = unsafeBitCast(CFArrayGetValueAtIndex(bufferAttachments, 0), to: CFMutableDictionary.self)
        CFDictionarySetValue(firstSampleAttachment,
                             Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                             Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())

        display(buffer: sample, orientation: orientation, bufferCrop: crop, size: size)
    }

    /// Display the given sample buffer.
    ///
    /// - Parameters:
    ///   - buffer: The pixel buffer to render.
    ///   - orientation: The orientation of the image.
    ///   - size: The size of the image, in pixels.
    ///   - crop: The crop to apply to the image, relative to the image size. Pass `{.zero, .size}` if no crop should be applied.
    func display(buffer: CMSampleBuffer, orientation: UIImage.Orientation, bufferCrop crop: CGRect, size: CGSize) {
        guard let sampleView else { return }

        var needsRelayout: Bool = false

        if orientation != lastOrientation {
            lastOrientation = orientation
            needsRelayout = true
        }

        if crop != lastCrop {
            lastCrop = crop
            needsRelayout = true
        }

        if size != lastSize {
            lastSize = size
            needsRelayout = true
        }

        if !sampleView.isReadyForMoreMediaData {
            sampleView.typedLayer.flush()
        }

        if sampleView.hasFailed {
            refreshSampleView()
            needsRelayout = true
        }

        if needsRelayout {
            #if os(iOS) || os(visionOS)
            setNeedsLayout()
            layoutIfNeeded()
            #else
            needsLayout = true
            layoutSubtreeIfNeeded()
            #endif
        }

        sampleView.enqueue(buffer)
    }

    // MARK: - Layout

    private var sampleView: AVSampleBufferView?
    private var lastSize: CGSize? = nil
    private var lastCrop: CGRect? = nil
    private var lastFormat: CMFormatDescription? = nil
    private var lastOrientation: UIImage.Orientation? = nil

    override func layoutSubviews() {
        guard let imageSize = lastSize, let orientation = lastOrientation, let crop = lastCrop, let sampleView else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let (sampleRect, scaleFactor) = rectForDisplayingSize(imageSize, cropped: crop, in: bounds, rotated: orientation)
        sampleView.bounds = CGRect(origin: .zero, size: sampleRect.size)
        sampleView.center = CGPoint(x: sampleRect.midX, y: sampleRect.midY)

        // The crop rect isn't rotated, since it's transformed along with the rest of the view.
        let cropRect = crop.applying(CGAffineTransform(scaleX: scaleFactor, y: scaleFactor))
        sampleView.crop(to: cropRect)

        switch orientation {
        case .up: sampleView.transform = .identity
        case .right: sampleView.transform = CGAffineTransform(rotationAngle: CGFloat(90.0).toRadians())
        case .down: sampleView.transform = CGAffineTransform(rotationAngle: CGFloat(180.0).toRadians())
        case .left: sampleView.transform = CGAffineTransform(rotationAngle: CGFloat(270.0).toRadians())
        case .upMirrored: sampleView.transform = CGAffineTransform.identity.scaledBy(x: -1.0, y: 1.0)
        case .rightMirrored: sampleView.transform = CGAffineTransform.identity.scaledBy(x: 1.0, y: -1.0).rotated(by: CGFloat(90.0).toRadians())
        case .downMirrored: sampleView.transform = CGAffineTransform(rotationAngle: CGFloat(180.0).toRadians()).scaledBy(x: -1.0, y: 1.0)
        case .leftMirrored: sampleView.transform = CGAffineTransform.identity.scaledBy(x: 1.0, y: -1.0).rotated(by: CGFloat(270.0).toRadians())
        @unknown default: sampleView.transform = .identity
        }

        CATransaction.commit()
    }

    private func refreshSampleView() {
        if sampleView != nil { sampleView?.removeFromSuperview() }
        let sampleView = AVSampleBufferView()
        self.sampleView = sampleView
        addSubview(sampleView)
    }

    private func rectForDisplayingSize(_ size: CGSize, cropped crop: CGRect, in bounds: CGRect, rotated orientation: UIImage.Orientation) -> (CGRect, CGFloat) {
        let effectiveSize: CGSize = {
            if orientation == .left || orientation == .leftMirrored || orientation == .right || orientation == .rightMirrored {
                return CGSize(width: crop.height, height: crop.width)
            } else {
                return crop.size
            }
        }()

        let scale = min(bounds.width / effectiveSize.width, bounds.height / effectiveSize.height)
        let scaledSize = CGSize(width: size.width * scale, height: size.height * scale)
        var scaledRect = CGRect(origin: .zero, size: scaledSize)
        scaledRect.origin.x = bounds.midX - (scaledSize.width / 2.0)
        scaledRect.origin.y = bounds.midY - (scaledSize.height / 2.0)
        return (scaledRect, scale)
    }
}

// MARK: - Layout Support

fileprivate class AVSampleBufferView: UIView {

    override class var layerClass: AnyClass {
        return AVSampleBufferDisplayLayer.self
    }

    var typedLayer: AVSampleBufferDisplayLayer {
        return layer as! AVSampleBufferDisplayLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }

    private func setup() {
        maskLayer = CALayer()
        maskLayer.anchorPoint = .zero
        maskLayer.backgroundColor = UIColor.black.cgColor
        typedLayer.mask = maskLayer
        typedLayer.contentsGravity = CALayerContentsGravity.resizeAspectFill
    }

    func enqueue(_ sample: CMSampleBuffer) {
        typedLayer.enqueue(sample)
    }

    func clearImage() {
        typedLayer.flushAndRemoveImage()
    }

    var hasFailed: Bool {
        return typedLayer.status == .failed
    }

    var isReadyForMoreMediaData: Bool {
        return typedLayer.isReadyForMoreMediaData
    }

    // Crop

    private var maskLayer: CALayer!

    func crop(to cropRect: CGRect) {
        maskLayer.frame = cropRect
    }

}

// MARK: - CMBlockBuffer Support

fileprivate enum CMEncodingError: Error {
    case cmBlockCreationFailed
}

// This is here so we can create a function pointer to it. It's used to release manually-retained data buffers.
private func freeBlock(_ refCon: UnsafeMutableRawPointer?, doomedMemoryBlock: UnsafeMutableRawPointer, sizeInBytes: Int) -> Void {
    let unmanagedData = Unmanaged<NSData>.fromOpaque(refCon!)
    unmanagedData.release()
}

private extension Data {
    func toCMBlockBuffer() throws -> CMBlockBuffer {
        // This block source is a manually retained pointer to our data instance.
        // The passed FreeBlock function manually releases it when the block buffer gets deallocated.
        let data = NSMutableData(data: self)
        var source = CMBlockBufferCustomBlockSource()
        source.refCon = Unmanaged.passRetained(data).toOpaque()
        source.FreeBlock = freeBlock

        var blockBuffer: CMBlockBuffer?
        let result = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: data.mutableBytes,
            blockLength: data.length,
            blockAllocator: kCFAllocatorNull,
            customBlockSource: &source,
            offsetToData: 0,
            dataLength: data.length,
            flags: 0,
            blockBufferOut: &blockBuffer)
        if OSStatus(result) != kCMBlockBufferNoErr {
            throw CMEncodingError.cmBlockCreationFailed
        }

        guard let buffer = blockBuffer else {
            throw CMEncodingError.cmBlockCreationFailed
        }

        assert(CMBlockBufferGetDataLength(buffer) == data.length)
        return buffer
    }
}

fileprivate extension CGFloat {
    func toRadians() -> CGFloat {
        return self * .pi / 180.0
    }
}
#endif
