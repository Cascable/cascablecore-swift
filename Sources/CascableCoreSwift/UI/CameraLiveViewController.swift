#if canImport(UIKit)
import CascableCore
import Foundation
import UIKit
import AVKit

/// View controller for rendering camera live view frames. Note: This view's API must be used from the main thread.
public class CameraLiveViewController: UIViewController {

    public init() {
        if LiveViewMetalRenderer.metalRenderingSupported, let renderer = try? LiveViewMetalRenderer() {
            metalRenderer = renderer
            fallbackLoader = renderer.loader
        } else {
            metalRenderer = nil
            fallbackLoader = LiveViewPixelBufferLoader(device: nil)
        }
        sampleImageView = HighPerformanceImageView()
        sampleImageView.translatesAutoresizingMaskIntoConstraints = false
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        if LiveViewMetalRenderer.metalRenderingSupported, let renderer = try? LiveViewMetalRenderer() {
            metalRenderer = renderer
            fallbackLoader = renderer.loader
        } else {
            metalRenderer = nil
            fallbackLoader = LiveViewPixelBufferLoader(device: nil)
        }
        sampleImageView = HighPerformanceImageView()
        sampleImageView.translatesAutoresizingMaskIntoConstraints = false
        super.init(coder: coder)
    }

    // MARK: - API

    public enum Orientation {
        /// Match the rendered image to the orientation reported by each live view frame.
        case syncWithCamera
        /// Lock the rendered image to the given orientation.
        case overridden(LiveViewFrameOrientation)
    }

    /// The target orientation for the live view image. Won't take effect until the next frame is rendered.
    public var orientation: Orientation = .syncWithCamera

    /// Returns a layout guide that matches the frame of the rendered image. Use this for positioning overlays.
    public lazy var liveViewImageLayoutGuide: UILayoutGuide = {
        let guide = UILayoutGuide()
        view.addLayoutGuide(guide)
        guide.leadingAnchor.constraint(equalTo: sampleImageView.leadingAnchor).isActive = true
        guide.trailingAnchor.constraint(equalTo: sampleImageView.trailingAnchor).isActive = true
        guide.topAnchor.constraint(equalTo: sampleImageView.topAnchor).isActive = true
        guide.bottomAnchor.constraint(equalTo: sampleImageView.bottomAnchor).isActive = true
        return guide
    }()

    /// Call to pause/resume rendering, perhaps due to a UI animation.
    public func setPauseRendering(_ pause: Bool) {
        pauseRendering = pause

        if pause {
            // We need create a snapshot of the current state and put that onscreen while we're paused.
            // This is because the image view doesn't play nice with UIKit animations,
            // which this API is usually used for - so that can't be onscreen while paused.

            pauseRenderingOverlayView?.removeFromSuperview()
            guard let snapshotView = sampleImageView.snapshotView(afterScreenUpdates: false) else { return }
            snapshotView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(snapshotView)
            NSLayoutConstraint.activate([
                snapshotView.leadingAnchor.constraint(equalTo: liveViewImageLayoutGuide.leadingAnchor),
                snapshotView.trailingAnchor.constraint(equalTo: liveViewImageLayoutGuide.trailingAnchor),
                snapshotView.topAnchor.constraint(equalTo: liveViewImageLayoutGuide.topAnchor),
                snapshotView.bottomAnchor.constraint(equalTo: liveViewImageLayoutGuide.bottomAnchor)
            ])
            pauseRenderingOverlayView = snapshotView
            sampleImageView.isHidden = true

        } else {
            onRenderResume?()
            onRenderResume = nil
            pauseRenderingOverlayView?.removeFromSuperview()
            pauseRenderingOverlayView = nil
            sampleImageView.isHidden = false
        }
    }

    /// Render the given live view frame to the screen.
    ///
    /// - Important: This API must be called from the main thread. Since this view offloads rendering to the GPU or
    ///              a background thread, a correctly-configured camera live view stream (i.e., one with the
    ///              `.skipImageDecoding` option set) is OK to be delivered on the main thread here.
    ///
    /// - Note: Frame rendering is asynchronous in some instances — the completion handler will be called when
    ///         rendering is complete and any pending layout changes have been performed. The rendered orientation
    ///         of the frame is passed to the completion handler, and may differ from the `orientation` property
    ///         due to the asynchronous nature of rendering.
    ///
    /// - Parameters:
    ///   - frame: The frame to render.
    ///   - completionHandler: The handler to call, on the main queue, when rendering is complete. The completion is
    ///                        the effective orientation, and the effective pre-scaled, rotated size.
    public func render(frame: LiveViewFrame, completionHandler: @escaping (LiveViewFrameOrientation, CGSize) -> Void) {
        if !Thread.isMainThread {
            print("WARNING: CameraLiveViewController.render(frame:completionHandler:) wasn't called on the main thread!")
        }

        guard !pauseRendering else {
            onRenderResume = { [weak self] in self?.render(frame: frame, completionHandler: completionHandler) }
            return
        }
        if !canRenderFrames { canRenderFrames = true }
        let isFirstFrame: Bool = (lastFrame == nil)

        if isFirstFrame {
            if frame.image != nil {
                print("****************************************************************")
                print("*                      !!!!! WARNING !!!!!                     *")
                print("*                                                              *")
                print("* CameraLiveViewController was passed a live view frame with   *")
                print("* a non-nil image value. You're consuming a significant amount *")
                print("* of resources rendering to a UI/NSImage that isn't being      *")
                print("* used. Pass the .skipImageDecoding option when starting live  *")
                print("* view to significantly reduce CPU usage!                      *")
                print("****************************************************************")
            }
        }

        let layoutOrientation: LiveViewFrameOrientation = {
            switch orientation {
            case .syncWithCamera: return frame.orientation
            case .overridden(let overriddenOrientation): return overriddenOrientation
            }
        }()

        let effectiveRenderedSize: CGSize = {
            if layoutOrientation.isLandscape {
                return frame.naturalImageSize
            } else {
                return CGSize(width: frame.naturalImageSize.height, height: frame.naturalImageSize.width)
            }
        }()

        Task.detached { [weak self] in
            guard let self else { return }
            await self.displayFrameWithMetalRenderer(frame, orientation: layoutOrientation.uiKitOrientation)
            await self.updateOrientation(to: layoutOrientation, with: frame, force: isFirstFrame)
            Task { @MainActor in
                self.lastFrame = frame
                completionHandler(layoutOrientation, effectiveRenderedSize)
            }
        }
    }

    /// Clear the live view image.
    public func clearDisplay() {
        sampleImageView.clearDisplay()
        lastFrame = nil
        canRenderFrames = false
    }

    // MARK: - Internal Properties

    private let sampleImageView: HighPerformanceImageView
    private var lastFrame: LiveViewFrame? = nil
    private let metalRenderer: LiveViewMetalRenderer?
    private let fallbackLoader: LiveViewPixelBufferLoader
    private var currentlyDisplayedOrientation: LiveViewFrameOrientation?
    private var aspectRatioConstraint: NSLayoutConstraint?
    private var canRenderFrames: Bool = false

    private var pauseRendering: Bool = false
    private var onRenderResume: (() -> Void)? = nil
    private var pauseRenderingOverlayView: UIView? = nil

    public override func loadView() {
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false

        sampleImageView.isOpaque = false
        sampleImageView.backgroundColor = .clear
        sampleImageView.contentMode = .scaleAspectFill
        containerView.addSubview(sampleImageView)
        sampleImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor).isActive = true
        sampleImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor).isActive = true
        sampleImageView.topAnchor.constraint(greaterThanOrEqualTo: containerView.topAnchor).isActive = true
        sampleImageView.leadingAnchor.constraint(greaterThanOrEqualTo: containerView.leadingAnchor).isActive = true

        let pinnedLeading = sampleImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor)
        pinnedLeading.priority = .defaultHigh
        pinnedLeading.isActive = true

        let pinnedTop = sampleImageView.topAnchor.constraint(equalTo: containerView.topAnchor)
        pinnedTop.priority = .defaultHigh
        pinnedTop.isActive = true

        aspectRatioConstraint = sampleImageView.widthAnchor.constraint(equalTo: sampleImageView.heightAnchor,
                                                                       multiplier: 1.5)
        aspectRatioConstraint?.isActive = true

        view = containerView
    }

    // MARK: - Internal

    private func displayFrameWithMetalRenderer(_ frame: LiveViewFrame, orientation: UIImage.Orientation) async {

        let isInForeground: Bool = (UIApplication.shared.applicationState == .active)

        if let metalRenderer, isInForeground {
            do {
                let pixelBuffer = try await metalRenderer.renderLiveViewFrameToSampleBuffer(frame, usingMetal: true)
                sampleImageView.display(buffer: pixelBuffer.buffer, orientation: orientation,
                                        bufferCrop: pixelBuffer.crop, size: pixelBuffer.naturalImageSize)
            } catch {
                await displayFrameWithCPUFallback(frame, orientation: orientation)
            }
        } else {
            await displayFrameWithCPUFallback(frame, orientation: orientation)
        }
    }

    private func displayFrameWithCPUFallback(_ frame: LiveViewFrame, orientation: UIImage.Orientation) async {
        do {
            let pixelBuffer = try await fallbackLoader.loadFrameToCPUSampleBuffer(frame)
            sampleImageView.display(buffer: pixelBuffer.buffer, orientation: orientation,
                                    bufferCrop: pixelBuffer.crop, size: frame.naturalImageSize)
        } catch {
            print("CPU fallback rendering failed with error: \(error)")
        }
    }

    @MainActor
    private func updateOrientation(to orientation: LiveViewFrameOrientation, with frame: LiveViewFrame, force: Bool) {
        guard frame.rawPixelCropRect.size != .zero else { return }

        var effectiveImageSize: CGSize = frame.rawPixelCropRect.size
        if !orientation.isLandscape {
            effectiveImageSize = CGSize(width: effectiveImageSize.height, height: effectiveImageSize.width)
        }

        let aspectRatio: CGFloat = effectiveImageSize.width / effectiveImageSize.height
        let currentAspectRatio: CGFloat = aspectRatioConstraint?.multiplier ?? 0.0

        let needsUpdate = (force || !aspectRatio.almostEqual(to: currentAspectRatio) ||
                           orientation != currentlyDisplayedOrientation)

        guard needsUpdate else { return }

        aspectRatioConstraint?.isActive = false
        aspectRatioConstraint = sampleImageView.widthAnchor.constraint(equalTo: sampleImageView.heightAnchor,
                                                                       multiplier: aspectRatio)
        aspectRatioConstraint?.isActive = true
        currentlyDisplayedOrientation = orientation
    }
}

// MARK: - Extensions

fileprivate extension CGFloat {
    func almostEqual(to other: CGFloat, delta: CGFloat = 0.0000001) -> Bool {
        return abs(self - other) <= delta
    }
}

fileprivate extension LiveViewFrameOrientation {
    var uiKitOrientation: UIImage.Orientation {
        switch self {
        case .landscape: return .up
        case .landscapeUpsideDown: return .down
        case .portraitLeft: return .left
        case .portraitRight: return .right
        @unknown default: return .up
        }
    }

    var isLandscape: Bool {
        return self == .landscape || self == .landscapeUpsideDown
    }
}

fileprivate extension UIImage.Orientation {
    var flipped: UIImage.Orientation {
        // Flipping isn't quite the same as rotating. When in portrait, a flipped image will be the mirror of the opposing rotation.
        switch self {
        case .up: return .upMirrored
        case .down: return .downMirrored
        case .left: return .rightMirrored
        case .right: return .leftMirrored
        case .upMirrored: return .up
        case .downMirrored: return .down
        case .leftMirrored: return .right
        case .rightMirrored: return .left
        @unknown default: return self
        }
    }
}
#endif
