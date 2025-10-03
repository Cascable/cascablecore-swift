import Foundation
import MetalKit

/// An object representing a lease to a resusable Metal texture. When instances of this object are deallocated,
/// the texture contained within is returned to the owning pool for lease to a new caller.
public class LeasedLiveViewTexture {

    fileprivate init(with texture: MTLTexture, relinquishHandler: ((LeasedLiveViewTexture) -> Void)?) {
        self.texture = texture
        self.relinquishHandler = relinquishHandler
    }

    /// The texture available for use. It may contain existing pixel data that's safe to overwrite.
    public let texture: MTLTexture

    /// The handler to call when it's time for the texture to be re-added to the pool. Can be `nil` for orphaned textures.
    let relinquishHandler: ((LeasedLiveViewTexture) -> Void)?

    deinit { relinquishHandler?(self) }
}

/// A class implementing a pool of reusable textures.
public actor LiveViewTexturePool {

    // MARK: - API

    /// Create a new texture pool, using the given device to create new textures.
    public init(device metalDevice: MTLDevice) {
        device = metalDevice
    }

    /// The device being used to create new textures.
    public let device: MTLDevice

    /// Return a lease to a pooled texture of the given size. When the returned `LeasedLiveViewTexture` object is
    /// deallocated, the GPU texture will be returned to the pool for lease to a new caller. It's important to keep
    /// the returned object alive as long as its containing texture is needed to be available.
    ///
    /// - Parameter size: The size of the texture required.
    /// - Returns: Returns a `PooledLiveViewTexture` object containing a texture available for use.
    /// - Throws: If a new texture needs to be created and fails, that error will be thrown.
    public func leaseTextureWithSize(_ size: CGSize) throws(LiveViewMetalError) -> LeasedLiveViewTexture {
        let key = size.asPoolKey
        var availableTextures = availableTexturesBySize[key, default: []]
        if !availableTextures.isEmpty {
            let texture = availableTextures.removeFirst()
            availableTexturesBySize[key] = availableTextures
            return LeasedLiveViewTexture(with: texture, relinquishHandler: { [weak self] in
                self?.notePooledTextureRelinquished($0)
            })
        }

        let newTexture = try device.makeSurfaceBackedTexture(size: size)
        return LeasedLiveViewTexture(with: newTexture, relinquishHandler: { [weak self] in
            self?.notePooledTextureRelinquished($0)
        })
    }

    /// Create a lease to an orphaned texture - i.e., a texture that shouldn't be returned to the pool for future use.
    ///
    /// - Parameter texture: The texture to embed in the returned `LeasedLiveViewTexture` object.
    /// - Returns: Returns a `PooledLiveViewTexture` object containing the given texture. When the returned object
    ///            is deallocated, the texture is NOT returned to the pool.
    public nonisolated func orphanedLeasedTexture(containing texture: MTLTexture) -> LeasedLiveViewTexture {
        return LeasedLiveViewTexture(with: texture, relinquishHandler: nil)
    }

    // MARK: - Internals

    fileprivate struct SizeKey: Hashable, Sendable {
        let width: Int
        let height: Int
    }

    private var availableTexturesBySize: [SizeKey: [MTLTexture]] = [:]

    nonisolated fileprivate func notePooledTextureRelinquished(_ pooledTexture: LeasedLiveViewTexture) {
        // This has to be nonisolated because it's called from the deinit of a `PooledLiveViewTexture`.
        // We also can't use it in an async context since it's in the middle of being deallocated.
        let textureToRecycle: MTLTexture = pooledTexture.texture
        let key = SizeKey(width: textureToRecycle.width, height: textureToRecycle.height)
        Task { await _isolatedNotePooledTextureRelinquished(textureToRecycle, with: key) }
    }

    private func _isolatedNotePooledTextureRelinquished(_ textureToRecycle: MTLTexture, with key: SizeKey) {
        var textures = availableTexturesBySize[key, default: []]
        assert(!textures.contains(where: { $0 === textureToRecycle }))
        textures.append(textureToRecycle)
        availableTexturesBySize[key] = textures
    }
}

private extension CGSize {
    var asPoolKey: LiveViewTexturePool.SizeKey {
        return .init(width: Int(width), height: Int(height))
    }
}

fileprivate extension MTLDevice {
    func makeSurfaceBackedTexture(descriptor: MTLTextureDescriptor) throws(LiveViewMetalError) -> MTLTexture {
        let surface = try IOSurface.create(forBacking: descriptor)
        #if os(iOS)
        guard let texture = makeTexture(descriptor: descriptor, iosurface: unsafeBitCast(surface, to: IOSurfaceRef.self), plane: 0) else {
            throw LiveViewMetalError.unexpectedFailure
        }
        #else
        guard let texture = makeTexture(descriptor: descriptor, iosurface: surface, plane: 0) else {
            throw LiveViewMetalError.unexpectedFailure
        }
        #endif
        return texture
    }

    func makeSurfaceBackedTexture(size: CGSize) throws(LiveViewMetalError) -> MTLTexture {
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.usage.formUnion(.shaderWrite)
        textureDescriptor.pixelFormat = .bgra8Unorm
        textureDescriptor.width = Int(size.width)
        textureDescriptor.height = Int(size.height)
        return try makeSurfaceBackedTexture(descriptor: textureDescriptor)
    }

    func makeMetalFXTexture(size: CGSize) throws -> MTLTexture {
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.usage = [.shaderRead, .renderTarget]
        textureDescriptor.pixelFormat = .bgra8Unorm
        textureDescriptor.width = Int(size.width)
        textureDescriptor.height = Int(size.height)
        textureDescriptor.storageMode = .private

        guard let scaledOutputTexture = makeTexture(descriptor: textureDescriptor) else {
            throw LiveViewMetalError.unexpectedFailure
        }

        return scaledOutputTexture
    }
}

struct ColorSpaceUtilities {
    static var srgbColorSpaceData: CFData? = {
        return CGColorSpace(name: CGColorSpace.sRGB)?.copyICCData()
    }()
}

extension IOSurface {
    static func create(forBacking textureDescriptor: MTLTextureDescriptor) throws(LiveViewMetalError) -> IOSurface {
        guard let surface = IOSurface(properties: [
            .width: textureDescriptor.width,
            .height: textureDescriptor.height,
            .bytesPerElement: 4,
            .pixelFormat: kCVPixelFormatType_32BGRA
        ]) else { throw LiveViewMetalError.unexpectedFailure }

        if let colorSpace = ColorSpaceUtilities.srgbColorSpaceData {
            #if os(iOS)
            IOSurfaceSetValue(unsafeBitCast(surface, to: IOSurfaceRef.self), kIOSurfaceColorSpace, colorSpace)
            #else
            IOSurfaceSetValue(surface, kIOSurfaceColorSpace, colorSpace)
            #endif
        }

        return surface
    }
}
