import Foundation
import MetalKit
import CoreGraphics
import CascableCore
import Accelerate
import VideoToolbox

/// This class provides both GPU- and CPU-backed functionality for loading pixel buffers.
public class LiveViewPixelBufferLoader {

    /// Create a new pixel buffer loader.
    ///
    /// - Parameter metalDevice: The device to load Metal textures with, or `nil` to only support CPU loading.
    public init(device metalDevice: MTLDevice?) {
        if let metalDevice {
            texturePool = LiveViewTexturePool(device: metalDevice)
            metalRenderingAvailable = true
        } else {
            texturePool = nil
            metalRenderingAvailable = false
        }
    }

    // MARK: - API

    /// Returns `true` if Metal rendering (i.e., loading pixel buffers into an `MTLTexture`) is available.
    public let metalRenderingAvailable: Bool

    /// The texture pool used by the renderer, if Metal rendering is available.
    public let texturePool: LiveViewTexturePool?

    /// Loads the given live view frame into an `MTLTexture` on the GPU.
    ///
    /// - Parameter liveViewFrame: The frame to load.
    /// - Returns: A texture containing the frame's raw pixel data. No cropping or scaling will be applied.
    /// - Throws: Throws an error if Metal rendering isn't available, or an error occurs.
    public func loadFrameToGPUTexture(_ liveViewFrame: LiveViewFrame) async throws(LiveViewMetalError) -> LeasedLiveViewTexture {
        // TODO: Do we need some kind of queue/locking of the loader etc here?
        switch liveViewFrame.rawPixelFormat {
        case .JPEG: return try await loadJPEGFrameToGPUTexture(liveViewFrame)
        case .rawPixelBuffer: return try await loadRawPixelBufferFrameToGPUTexture(liveViewFrame)
        @unknown default: throw LiveViewMetalError.pixelFormatNotSupported
        }
    }

    /// An object containing a sample buffer and any additional metadata needed for rendering.
    public struct SampleBufferContext: @unchecked Sendable {
        // @unchecked Sendable is a workaround for the fact CMSampleBuffer isn't marked Sendable.
        // This isn't a good fix - more of a misdirection - and we should fix it in a better way.

        /// The loaded sample buffer, in BGRA32 format.
        public let buffer: CMSampleBuffer

        /// Any further crop that should be applied to the loaded pixel buffer to get to the final image.
        /// If no crop is needed, this rectangle will have a zero origin and the same pixel size as the sample buffer.
        public let crop: CGRect

        /// The "natural" size of the buffer's image.
        public let naturalImageSize: CGSize
    }

    /// Loads the given live view frame into a `CMSampleBuffer` on the CPU.
    ///
    /// - Parameter liveViewFrame: The frame to load.
    /// - Returns: An object containing the loaded pixel buffer and additional metadata. Cropping or scaling
    ///            *may* be applied if we have the opportunity to do it efficiently as part of loading.
    public func loadFrameToCPUSampleBuffer(_ liveViewFrame: LiveViewFrame) async throws -> SampleBufferContext {
        // TODO: Do we need some kind of queue/locking of the loader etc here?
        switch liveViewFrame.rawPixelFormat {
        case .JPEG: return try await loadJPEGFrameToCPUSampleBuffer(liveViewFrame)
        case .rawPixelBuffer: return try await loadRawPixelBufferFrameToCPUSampleBuffer(liveViewFrame)
        @unknown default: throw LiveViewMetalError.pixelFormatNotSupported
        }
    }

    // MARK: - Texture Loading (GPU)

    private var gpuJpegFrameDecoder: VideoToolboxJPEGDecoder?

    private func loadJPEGFrameToGPUTexture(_ liveViewFrame: LiveViewFrame) async throws(LiveViewMetalError) -> LeasedLiveViewTexture {
        guard let texturePool else { throw LiveViewMetalError.metalNotSupported }

        let device = texturePool.device
        let format: CMFormatDescription = liveViewFrame.rawPixelFormatDescription
        let pixelData: Data = liveViewFrame.rawPixelData
        let pixelSize: CGSize = liveViewFrame.rawPixelSize

        // Here we use a nice wrapper around `VTDecompressionSession`. The session itself can be a bit fragile
        // and become invalidated in certain circumstances, and may be unable to handle changes in image size.
        // Therefore, we use an existing session if we have one and it claims to support the image size we're being
        // asked to decode. If that then fails, we create a new session and try again. If *that* fails, we throw.
        let decoder: VideoToolboxJPEGDecoder
        if let existingDecoder = gpuJpegFrameDecoder, existingDecoder.canDecodeSampleOfFormat(format) {
            decoder = existingDecoder
        } else {
            let newDecoder = try VideoToolboxJPEGDecoder(decoding: format, using: device)
            gpuJpegFrameDecoder = newDecoder
            decoder = newDecoder
        }

        let sample: CMSampleBuffer = try CMSampleBuffer.sampleFromJPEGData(pixelData, ofSize: pixelSize)
        let texture: MTLTexture

        do {
            texture = try decoder.decodeSample(sample, format: format)
        } catch {
            print("VT decoding of JPEG frame failed with error \(error)")
            // The decoder can fail for various reasons. A lot of them can be "fixed" by making a new session.
            let newDecoder: VideoToolboxJPEGDecoder = try VideoToolboxJPEGDecoder(decoding: format, using: device)
            texture = try newDecoder.decodeSample(sample, format: format)
            gpuJpegFrameDecoder = newDecoder
        }

        return texturePool.orphanedLeasedTexture(containing: texture)
    }

    private func loadRawPixelBufferFrameToGPUTexture(_ liveViewFrame: LiveViewFrame) async throws(LiveViewMetalError) -> LeasedLiveViewTexture {
        guard let pool = texturePool else { throw LiveViewMetalError.metalNotSupported }
        guard liveViewFrame.rawPixelFormatDescription.mediaSubType == .pixelFormat_24RGB else {
            throw LiveViewMetalError.pixelFormatNotSupported
        }

        // Metal doesn't support RGB24, so we need to transform it to BGRA (MTLPixelFormatBGRA8Unorm).
        let rawPixelSize: CGSize = liveViewFrame.rawPixelSize
        let bgraData: Data = try cpuConvertRGB24ToBGRA32(liveViewFrame.rawPixelData, ofSize: rawPixelSize)

        // We now have pixel data of the right type.
        let texture = try await pool.leaseTextureWithSize(rawPixelSize)
        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: Int(rawPixelSize.width), height: Int(rawPixelSize.height), depth: 1))

        do {
            try bgraData.withUnsafeBytes({ bufferPointer in
                guard let base = bufferPointer.baseAddress else { throw LiveViewMetalError.unexpectedFailure }
                texture.texture.replace(region: region, mipmapLevel: 0, withBytes: base, bytesPerRow: Int(rawPixelSize.width) * 4)
            })
        }
        catch let error as LiveViewMetalError { throw error }
        catch { throw LiveViewMetalError.unexpectedFailure }

        return texture
    }

    // MARK: - Sample Buffer Loading (CPU)

    private func loadJPEGFrameToCPUSampleBuffer(_ liveViewFrame: LiveViewFrame) async throws -> SampleBufferContext {
        // Note: We're taking advantage of the fact that there's no camera that delivers JPEG frames that need scaling
        // as well as cropping (i.e., have a `naturalImageSize` that's different to the crop rect's size). Doing a
        // pixel-level crop/scale here is tricky since the buffer is encoded JPEG data (we're relying on a GPU
        // decode later), so we pass back the crop to be performed at the UI level.
        let sample = try CMSampleBuffer.sampleFromJPEGData(liveViewFrame.rawPixelData, ofSize: liveViewFrame.rawPixelSize)
        return SampleBufferContext(buffer: sample, crop: liveViewFrame.rawPixelCropRect,
                                   naturalImageSize: liveViewFrame.naturalImageSize)
    }

    private func loadRawPixelBufferFrameToCPUSampleBuffer(_ liveViewFrame: LiveViewFrame) async throws -> SampleBufferContext {
        guard liveViewFrame.rawPixelFormatDescription.mediaSubType == .pixelFormat_24RGB else {
            throw LiveViewMetalError.pixelFormatNotSupported
        }

        let sourceRGB24Data: Data = liveViewFrame.rawPixelData
        let sourcePixelSize: CGSize = liveViewFrame.rawPixelSize
        let uncroppedBgraData: Data = try cpuConvertRGB24ToBGRA32(sourceRGB24Data, ofSize: sourcePixelSize)

        let cropRect: CGRect = liveViewFrame.rawPixelCropRect
        let naturalImageSize: CGSize = liveViewFrame.naturalImageSize
        let needsCrop: Bool = (sourcePixelSize != cropRect.size)
        let needsResizeAfterCrop: Bool = (naturalImageSize != cropRect.size)

        let outputBytesPerRow: Int = Int(naturalImageSize.width) * 4
        let bgra32BytesPerPixel: Int = 4

        // For reasons that are beyond my understanding, creating a direct sample buffer like we do with
        // JPEG frames doesn't work. Well, it works, but `AVSampleBufferDisplayLayer` silently won't render them.
        // However, making an IOSurface, copying our bytes into it, then going to CMSampleBuffer via CVPixelBuffer
        // renders just fine. This also works with our plain RGB24 data, but for consistency's sake with everything
        // else we convert it to 32BGRA/MTLPixelFormatBGRA8Unorm anyway.
        guard let surface = IOSurface(properties: [
            .width: naturalImageSize.width,
            .height: naturalImageSize.height,
            .bytesPerElement: bgra32BytesPerPixel,
            .bytesPerRow: outputBytesPerRow,
            .pixelFormat: kCVPixelFormatType_32BGRA
        ]) else { throw LiveViewMetalError.unexpectedFailure }
        if let colorSpace = ColorSpaceUtilities.srgbColorSpaceData {
            #if os(iOS)
            IOSurfaceSetValue(unsafeBitCast(surface, to: IOSurfaceRef.self), kIOSurfaceColorSpace, colorSpace)
            #else
            IOSurfaceSetValue(surface, kIOSurfaceColorSpace, colorSpace)
            #endif
        }

        if (needsCrop || needsResizeAfterCrop) {

            let sourceBgraBytesPerRow: Int = Int(sourcePixelSize.width) * bgra32BytesPerPixel

            var cropSourcePixelData: Data = uncroppedBgraData
            try cropSourcePixelData.withUnsafeMutableBytes({ sourceBufferPointer in
                guard let sourceBasePointer = sourceBufferPointer.baseAddress else { throw LiveViewMetalError.unexpectedFailure }

                // We're kind of abusing our pixel layout in memory in order to perform a crop via a scale operation.
                // By offsetting the start of the buffer by the x coordinate of the crop but keeping the row length
                // the pre-crop width, we're effectively "wrapping around" the rows to include the trailing end of
                // a row and the leading end of the *next* row. This technically would be an overflow on the last
                // row, but vImageScale() doesn't read past source pixels it needs for the *destination* buffer,
                // so it's OK (since our destination buffer is smaller).
                let startOffset: Int = (Int(cropRect.origin.y) * sourceBgraBytesPerRow) + (Int(cropRect.origin.x) * bgra32BytesPerPixel)
                var sourceBuffer = vImage_Buffer(data: sourceBasePointer + startOffset,
                                                 height: vImagePixelCount(cropRect.height),
                                                 width: vImagePixelCount(cropRect.width),
                                                 rowBytes: sourceBgraBytesPerRow)

                surface.lock(seed: nil)
                var outputBuffer = vImage_Buffer(data: surface.baseAddress,
                                                 height: vImagePixelCount(naturalImageSize.height),
                                                 width: vImagePixelCount(naturalImageSize.width),
                                                 rowBytes: outputBytesPerRow)
                let cropScaleResult: vImage_Error = vImageScale_ARGB8888(&sourceBuffer, &outputBuffer, nil, 0)
                surface.unlock(seed: nil)

                guard cropScaleResult == kvImageNoError else { throw LiveViewMetalError.unexpectedFailure }
            })

        } else {
            // If we don't need to manipulate the pixels, we can just copy them right in.
            surface.lock(seed: nil)
            let buffer = UnsafeMutableRawBufferPointer(start: surface.baseAddress, count: uncroppedBgraData.count)
            uncroppedBgraData.copyBytes(to: buffer)
            surface.unlock(seed: nil)
        }

        var unmanagedBuffer: Unmanaged<CVPixelBuffer>? = nil
        #if os(iOS)
        CVPixelBufferCreateWithIOSurface(kCFAllocatorDefault, unsafeBitCast(surface, to: IOSurfaceRef.self), nil, &unmanagedBuffer)
        #else
        CVPixelBufferCreateWithIOSurface(kCFAllocatorDefault, surface, nil, &unmanagedBuffer)
        #endif

        guard let cvBuffer = unmanagedBuffer?.takeRetainedValue() else { throw LiveViewMetalError.unexpectedFailure }

        var format: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: cvBuffer,
                                                                  formatDescriptionOut: &format)
        guard status == noErr, let format else { throw LiveViewMetalError.unexpectedFailure }

        var timingInfo = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        let bufferStatus = CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: cvBuffer,
                                                                    formatDescription: format, sampleTiming: &timingInfo,
                                                                    sampleBufferOut: &sampleBuffer)

        guard bufferStatus == noErr, let sampleBuffer else { throw LiveViewMetalError.unexpectedFailure }

        let attachments: NSArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true)! as NSArray
        let dict: NSMutableDictionary = attachments[0] as! NSMutableDictionary
        dict[kCMSampleAttachmentKey_DisplayImmediately as NSString] = true as NSNumber

        return SampleBufferContext(buffer: sampleBuffer, crop: CGRect(origin: .zero, size: naturalImageSize),
                                   naturalImageSize: naturalImageSize)
    }

    // MARK: - Internal Helpers

    private func cpuConvertRGB24ToBGRA32(_ rawPixelData: Data, ofSize rawPixelSize: CGSize) throws(LiveViewMetalError) -> Data {
        let premultiply: Bool = true
        let rgb24BytesPerPixel: Int = 3
        let bgra32BytesPerPixel: Int = 4

        let bgraPixelByteCount: Int = (Int(rawPixelSize.width) * Int(rawPixelSize.height) * bgra32BytesPerPixel)

        var rawPixelData: Data = rawPixelData
        do {
            return try rawPixelData.withUnsafeMutableBytes({ sourceBufferPointer in
                guard let sourceBasePointer = sourceBufferPointer.baseAddress else { throw LiveViewMetalError.unexpectedFailure }
                var sourceBuffer = vImage_Buffer(data: sourceBasePointer,
                                                 height: vImagePixelCount(rawPixelSize.height),
                                                 width: vImagePixelCount(rawPixelSize.width),
                                                 rowBytes: Int(rawPixelSize.width) * rgb24BytesPerPixel)

                var destinationData = Data(count: bgraPixelByteCount)
                let error: vImage_Error = try destinationData.withUnsafeMutableBytes({ destinationBufferPointer in
                    guard let destinationBasePointer = destinationBufferPointer.baseAddress else { throw LiveViewMetalError.unexpectedFailure }
                    var destinationBuffer = vImage_Buffer(data: destinationBasePointer,
                                                          height: vImagePixelCount(rawPixelSize.height),
                                                          width: vImagePixelCount(rawPixelSize.width),
                                                          rowBytes: Int(rawPixelSize.width) * bgra32BytesPerPixel)
                    return vImageConvert_RGB888toBGRA8888(&sourceBuffer, nil, 255, &destinationBuffer, premultiply, 0)
                })

                guard error == kvImageNoError else { throw LiveViewMetalError.unexpectedFailure }
                return destinationData
            })
        } catch let error as LiveViewMetalError {
            throw error
        } catch {
            throw LiveViewMetalError.unexpectedFailure
        }
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

// MARK: - Other Support

fileprivate extension CMFormatDescription {

    static func jpegFormatOfSize(_ size: CGSize) throws(LiveViewMetalError) -> CMFormatDescription {
        var format: CMFormatDescription? = nil
        let success = CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: kCMVideoCodecType_JPEG,
                                                     width: Int32(size.width), height: Int32(size.height),
                                                     extensions: nil, formatDescriptionOut: &format)
        guard let format, success == noErr else { throw LiveViewMetalError.pixelFormatNotSupported }
        return format
    }
}

fileprivate extension CMSampleBuffer {

    static func sampleFromJPEGData(_ data: Data, ofSize size: CGSize) throws(LiveViewMetalError) -> CMSampleBuffer {
        let format = try CMFormatDescription.jpegFormatOfSize(size)

        let blockBuffer: CMBlockBuffer
        do { blockBuffer = try data.toCMBlockBuffer() }
        catch { throw LiveViewMetalError.pixelFormatNotSupported }

        var timingInfo = CMSampleTimingInfo(duration: CMTime.invalid, presentationTimeStamp: CMTime.zero, decodeTimeStamp: CMTime.invalid)
        var sampleSize = data.count

        var sample: CMSampleBuffer? = nil
        let sampleResult = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: blockBuffer,
                                                     formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 1,
                                                     sampleTimingArray: &timingInfo, sampleSizeEntryCount: 1,
                                                     sampleSizeArray: &sampleSize, sampleBufferOut: &sample)
        guard let sample = sample, sampleResult == noErr else { throw LiveViewMetalError.pixelFormatNotSupported }

        let attachments: NSArray = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true)! as NSArray
        let dict: NSMutableDictionary = attachments[0] as! NSMutableDictionary
        dict[kCMSampleAttachmentKey_DisplayImmediately as NSString] = true as NSNumber

        return sample
    }
}

/// A basic wrapper around ``VTDecompressionSession`` to decode JPEG frames into a Metal texture via
/// the hardware-accelerated video decoders modern systems have.
fileprivate class VideoToolboxJPEGDecoder {

    /// Initialise a decoder session for the given video format.
    ///
    /// - Parameters:
    ///   - initialFormat: The format the decoder session will be expected to decode.
    ///   - device: The Metal device to create textures with.
    init(decoding initialFormat: CMFormatDescription, using device: MTLDevice) throws(LiveViewMetalError) {

        let decoderSpecification: [CFString: Any] = {
            if #available(iOS 17.0, macCatalyst 17.0, tvOS 17.0, macOS 10.9, visionOS 1.0, *) {
                return [kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: kCFBooleanTrue as Any]
            } else {
                return [:]
            }
        }()

        let bufferAttributes: [CFString: Any] = [
            kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue as Any,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [
                IOSurfacePropertyKey.bytesPerElement: 4,
                IOSurfacePropertyKey.pixelFormat: kCVPixelFormatType_32BGRA
            ]
        ]

        var session: VTDecompressionSession?
        let result = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault,
                                                  formatDescription: initialFormat,
                                                  decoderSpecification: (decoderSpecification as CFDictionary),
                                                  imageBufferAttributes: (bufferAttributes as CFDictionary),
                                                  outputCallback: nil,
                                                  decompressionSessionOut: &session)
        guard result == noErr, let session else { throw LiveViewMetalError.improperSetup }
        self.session = session
        self.device = device
    }

    deinit {
        VTDecompressionSessionInvalidate(session)
    }

    let session: VTDecompressionSession
    let device: MTLDevice

    /// Returns `true` if the session can decode frames of the given format, otherwise `false`.
    func canDecodeSampleOfFormat(_ format: CMFormatDescription) -> Bool {
        return VTDecompressionSessionCanAcceptFormatDescription(session, formatDescription: format)
    }

    /// Decode the given frame into a Metal texture.
    ///
    /// - Parameters:
    ///   - sample: The JPEG-encded frame sample.
    ///   - format: The format of the given frame.
    /// - Returns: Returns a Metal texture containing the decoded pixel data in BGRA32/MTLPixelFormatBGRA8Unorm format.
    func decodeSample(_ sample: CMSampleBuffer, format: CMFormatDescription) throws(LiveViewMetalError) -> MTLTexture {

        guard canDecodeSampleOfFormat(format) else {
            throw LiveViewMetalError.pixelFormatNotSupported
        }

        struct FrameBox {
            var frame: CVImageBuffer? = nil
        }

        var frameBox = FrameBox()
        // With a clear set of flags, this method is documented to call its outputHandler before returning.
        let status = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample, flags: [], infoFlagsOut: nil,
                                                       outputHandler: { _, decodeInfo, imageBuffer, _, _ in
            frameBox.frame = imageBuffer
        })

        guard status == noErr, let outputFrame = frameBox.frame, let unmanagedSurface = CVPixelBufferGetIOSurface(outputFrame) else {
            throw LiveViewMetalError.unexpectedFailure
        }

        let renderedFrameSurface = unmanagedSurface.takeUnretainedValue()
        if let colorSpace = ColorSpaceUtilities.srgbColorSpaceData {
            IOSurfaceSetValue(renderedFrameSurface, kIOSurfaceColorSpace, colorSpace)
        }

        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.usage.formUnion(.shaderWrite)
        textureDescriptor.pixelFormat = .bgra8Unorm
        textureDescriptor.width = Int(format.dimensions.width)
        textureDescriptor.height = Int(format.dimensions.height)

        // For reasons that are beyond my understanding (as of 2024-07-17), we can't just hand the IOSurface
        // that VideoToolbox renders into to a texture on Intel machines - we get a blank texture. Doing the
        // same on Apple Silicon/iOS devices works fine, perhaps due to the shared memory architecture.
        let texture: MTLTexture?

        #if arch(arm64)
        texture = device.makeTexture(descriptor: textureDescriptor, iosurface: renderedFrameSurface, plane: 0)
        #else

        let surfaceCopy = try IOSurface.create(forBacking: textureDescriptor)
        surfaceCopy.lock(seed: nil)
        IOSurfaceLock(renderedFrameSurface, .readOnly, nil)
        memcpy(surfaceCopy.baseAddress, IOSurfaceGetBaseAddress(renderedFrameSurface),
               IOSurfaceGetBytesPerRow(renderedFrameSurface) * IOSurfaceGetHeight(renderedFrameSurface))
        IOSurfaceUnlock(renderedFrameSurface, .readOnly, nil)
        surfaceCopy.unlock(seed: nil)

        #if os(iOS)
        texture = device.makeTexture(descriptor: textureDescriptor, iosurface: unsafeBitCast(surfaceCopy, to: IOSurfaceRef.self), plane: 0)
        #else
        texture = device.makeTexture(descriptor: textureDescriptor, iosurface: surfaceCopy, plane: 0)
        #endif // os(iOS)
        #endif // arch(arm64)

        guard let texture else { throw LiveViewMetalError.unexpectedFailure }
        return texture
    }
}
