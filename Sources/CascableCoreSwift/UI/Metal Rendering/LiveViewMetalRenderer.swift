import Foundation
import MetalKit
import CascableCore
import MetalPerformanceShaders
import CoreVideo
import IOSurface

/// Errors that can occur during live view rendering.
public enum LiveViewMetalError: Error {
    /// Metal is not supported on the device (are we in a virtual machine?)
    case metalNotSupported
    /// Some configuration error occurred. This is usually a programmer error.
    case improperSetup
    /// A pixel format was used that isn't supported by Metal.
    case pixelFormatNotSupported
    /// Some other unexpected failure occurred. This is usually fatal to the operation at hand.
    case unexpectedFailure
}

/// This class implements a GPU-backed pipeline for rendering live view frames using Metal as well as a CPU-backed
/// fallback for when GPU processing isn't available (such as when in the background on iOS). It's designed to be an
/// end-to-end process, in which live view frames from CascableCore go in and fully-rendered buffers come out ready
/// for display.
public class LiveViewMetalRenderer {

    private static var device: MTLDevice? = {
        return MTLCreateSystemDefaultDevice()
    }()

    // MARK: - General API

    /// Returns `true` if the system supports Metal with enough of a feature set to render live view frames on the GPU.
    public static var metalRenderingSupported: Bool {
        guard let device else { return false }
        #if targetEnvironment(simulator)
        // Simulator is .apple2, which doesn't support nonuniform threadgroup sizes. We need to special-case for it.
        // https://developer.apple.com/documentation/metal/developing_metal_apps_that_run_in_simulator
        return device.supportsFamily(.apple2)
        #else
        return device.supportsFamily(.common3) || device.supportsFamily(.apple4) || device.supportsFamily(.mac2)
        #endif
    }

    /// Create a new instance of the receiver. Will throw an error if Metal isn't supported or a setup error occurs.
    public init() throws(LiveViewMetalError) {
        guard Self.metalRenderingSupported, let device = Self.device else { throw LiveViewMetalError.metalNotSupported }

        self.device = device
        do { library = try device.makeDefaultLibrary(bundle: Bundle(for: type(of: self))) }
        catch { throw .improperSetup }
        guard let queue = device.makeCommandQueue() else { throw LiveViewMetalError.metalNotSupported }
        commandQueue = queue

        loader = LiveViewPixelBufferLoader(device: device)
        guard let pool = loader.texturePool else { throw LiveViewMetalError.metalNotSupported }
        texturePool = pool
    }

    // MARK: - Rendering API

    /// The pixel buffer loader used by the renderer.
    public let loader: LiveViewPixelBufferLoader

    /// The texture pool used by the renderer.
    public let texturePool: LiveViewTexturePool

    /// The Metal device used for rendering.
    public let device: MTLDevice

    /// The Metal library containing shaders and other functions relavent to live view rendering.
    public let library: MTLLibrary

    /// The Metal command queue used to schedule work onto the GPU.
    public let commandQueue: MTLCommandQueue

    /// Render the given live view frame into a Metal texture using the GPU pipeline.
    ///
    /// - Parameter frame: The frame to render.
    /// - Returns: Returns an `IOSurface`-backed `MTLTexture`.
    /// - Throws: Will throw an error if a rendering error occurs, or if called on iOS if the process is in the background.
    public func renderLiveViewFrameToTexture(_ frame: LiveViewFrame) async throws -> LeasedLiveViewTexture {
        let renderedTexture = try await _renderLiveViewFrameToTexture(frame)
        guard renderedTexture.texture.iosurface == nil else { return renderedTexture }

        // The texture isn't IOSurface-backed, which our pipeline requires. This means that we need to copy the texture
        // into an IOSurface-backed one (MTKTextureLoader doesn't let us start with IOSurface).
        let surfaceBackedCopy = try await texturePool.leaseTextureWithSize(CGSize(width: renderedTexture.texture.width,
                                                                                  height: renderedTexture.texture.height))

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let blitCommand = commandBuffer.makeBlitCommandEncoder() else {
            throw LiveViewMetalError.unexpectedFailure
        }

        blitCommand.copy(from: renderedTexture.texture, to: surfaceBackedCopy.texture)
        blitCommand.endEncoding()
        commandBuffer.commit()

        return surfaceBackedCopy
    }

    /// Render the given live view frame into a `CMSampleBuffer` using either the GPU or the CPU pipeline.
    ///
    /// - Parameters:
    ///   - frame: The frame to render.
    ///   - useMetal: Pass `true` to use the Metal-backed GPU pipeline, or `false` to use the CPU pipeline.
    /// - Returns: Returns a `SampleBufferContext` object with the rendered frame and a rectangle describing
    ///            any further crop needed.
    /// - Throws: Will throw an error if a rendering error occurs, or if called on iOS if the process is in
    ///           the background and `useMetal` is `true`.
    public func renderLiveViewFrameToSampleBuffer(_ frame: LiveViewFrame, usingMetal useMetal: Bool) async throws -> LiveViewPixelBufferLoader.SampleBufferContext {
        guard useMetal else { return try await loader.loadFrameToCPUSampleBuffer(frame) }

        let renderedTexture = try await renderLiveViewFrameToTexture(frame)
        guard let surface = renderedTexture.texture.iosurface else { throw LiveViewMetalError.improperSetup }

        var unmanagedBuffer: Unmanaged<CVPixelBuffer>? = nil
        CVPixelBufferCreateWithIOSurface(kCFAllocatorDefault, surface, nil, &unmanagedBuffer)
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

        // Crops and scales are always done by our metal rendering pipeline, so there's never a further crop to be done.
        let crop = CGRect(x: 0, y: 0, width: renderedTexture.texture.width, height: renderedTexture.texture.height)
        return .init(buffer: sampleBuffer, crop: crop, naturalImageSize: crop.size)
    }

    // MARK: - Rendering (Private)

    private func _renderLiveViewFrameToTexture(_ frame: LiveViewFrame) async throws -> (LeasedLiveViewTexture) {
        let sourceImageTexture = try await loader.loadFrameToGPUTexture(frame)
        var computeSourceTexture: LeasedLiveViewTexture = sourceImageTexture

        let rawPixelSize: CGSize = frame.rawPixelSize
        let cropRect: CGRect = frame.rawPixelCropRect
        let naturalImageSize: CGSize = frame.naturalImageSize

        let needsCrop: Bool = (rawPixelSize != cropRect.size)
        let needsResizeAfterCrop: Bool = (naturalImageSize != cropRect.size)
        let cropRectHasNonZeroOrigin: Bool = (Int(cropRect.origin.x) > 0 || Int(cropRect.origin.y) > 0)

        if (needsCrop || needsResizeAfterCrop) {
            // We crop and resize in one operation by creating a new texture of the final image size, then
            // scheduling a transform operation into it from our image source texture.
            let cropDestinationTexture = try await texturePool.leaseTextureWithSize(naturalImageSize)

            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                throw LiveViewMetalError.unexpectedFailure
            }

            // Be a bit conservative over floating point oddness by only calculating values if needed.
            let scaleX: Double = needsResizeAfterCrop ? (naturalImageSize.width / cropRect.width) : 1.0
            let scaleY: Double = needsResizeAfterCrop ? (naturalImageSize.height / cropRect.height) : 1.0
            let translateX: Double = cropRectHasNonZeroOrigin ? (-cropRect.origin.x) * scaleX : 0.0
            let translateY: Double = cropRectHasNonZeroOrigin ? (-cropRect.origin.y) * scaleY : 0.0

            // A linear scale is fast but lesser quality. It's fine enough I guess.
            let filter = MPSImageBilinearScale(device: device)
            var transform = MPSScaleTransform(scaleX: scaleX, scaleY: scaleY, translateX: translateX, translateY: translateY)
            withUnsafePointer(to: &transform, { transformPtr in
                filter.scaleTransform = transformPtr
                filter.encode(commandBuffer: commandBuffer,
                              sourceTexture: sourceImageTexture.texture,
                              destinationTexture: cropDestinationTexture.texture)
            })

            commandBuffer.commit()
            computeSourceTexture = cropDestinationTexture
        }

        return computeSourceTexture
    }
}

#if os(iOS)
fileprivate extension UIColor {
    convenience init(srgbRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
#endif

fileprivate extension MTLTexture {
    /// Utility function for building a descriptor that matches this texture
    func createMatchingDescriptor() -> MTLTextureDescriptor {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = textureType
        // NOTE: We should be more careful to select a renderable pixel format here,
        // especially if operating on a compressed texture.
        descriptor.pixelFormat = pixelFormat
        descriptor.width = width
        descriptor.height = height
        descriptor.depth = depth
        descriptor.mipmapLevelCount = mipmapLevelCount
        descriptor.arrayLength = arrayLength
        // NOTE: We don't set resourceOptions here, since we explicitly set cache and storage modes below.
        descriptor.cpuCacheMode = cpuCacheMode
        descriptor.storageMode = storageMode
        descriptor.usage = usage
        return descriptor
    }
}
