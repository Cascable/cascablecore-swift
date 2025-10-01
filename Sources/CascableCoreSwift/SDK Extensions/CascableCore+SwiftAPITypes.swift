import Foundation
import CascableCore

// MARK: - Types

public typealias TypedCommonValue = Equatable & TranslateableFromObjCCommonValue
public typealias TypedCommonExposureValue = Equatable & UniversalExposurePropertyValue & TranslateableFromObjCCommonValue

/// A `TypedIdentifier` is a strongly-typed replacement for `CBLPropertyIdentifier`.
public struct TypedIdentifier<CommonValueType: TypedCommonValue>: Equatable {
    public let propertyIdentifier: PropertyIdentifier

    fileprivate init(identifier: PropertyIdentifier) {
        propertyIdentifier = identifier
    }
}

/// The common value for video format properties, allowing inspection of frame rate and size.
public struct VideoFormatValue: Equatable {
    /// The video format's frame rate, or `nil` if not available.
    public let frameRate: Int?

    /// The video format's frame size (in pixels), or `nil` if not available.
    public let frameSize: CGSize?

    /// The video format's compression level, or `nil` if not available.
    public let compressionLevel: VideoFormatCompressionLevel?
}

public struct LiveViewZoomLevelValue: Equatable {
    /// Returns `true` if the value represents a "zoomed in" value, otherwise `false`.
    public let zoomedIn: Bool

    /// The value's zoom factor. No zoom is `1.0`. Can be `nil` if the factor is unknown.
    public let zoomFactor: Double?
}

// MARK: - Property Identifier Declarations

public extension TypedIdentifier where CommonValueType == ApertureValue {
    static let aperture = TypedIdentifier(identifier: .aperture)
    static let videoAperture = TypedIdentifier(identifier: .videoAperture)
}

public extension TypedIdentifier where CommonValueType == ShutterSpeedValue {
    static let shutterSpeed = TypedIdentifier(identifier: .shutterSpeed)
    static let videoShutterSpeed = TypedIdentifier(identifier: .videoShutterSpeed)
}

public extension TypedIdentifier where CommonValueType == ISOValue {
    static let iso = TypedIdentifier(identifier: .isoSpeed)
    static let videoISO = TypedIdentifier(identifier: .videoISOSpeed)
}

public extension TypedIdentifier where CommonValueType == ExposureCompensationValue {
    static let exposureCompensation = TypedIdentifier(identifier: .exposureCompensation)
    static let videoExposureCompensation = TypedIdentifier(identifier: .videoExposureCompensation)
    static let lightMeterReading = TypedIdentifier(identifier: .lightMeterReading)
}

public extension TypedIdentifier where CommonValueType == Bool {
    static let lensStatus = TypedIdentifier(identifier: .lensStatus)
    static let mirrorLockupEnabled = TypedIdentifier(identifier: .mirrorLockupEnabled)
    static let dofPreviewEnabled = TypedIdentifier(identifier: .dofPreviewEnabled)
    static let digitalZoomEnabled = TypedIdentifier(identifier: .digitalZoom)
    static let inCameraBracketingEnabled = TypedIdentifier(identifier: .inCameraBracketingEnabled)
    static let readyForCapture = TypedIdentifier(identifier: .readyForCapture)
}

public extension TypedIdentifier where CommonValueType == PropertyCommonValuePowerSource {
    static let powerSource = TypedIdentifier(identifier: .powerSource)
}

public extension TypedIdentifier where CommonValueType == PropertyCommonValueBatteryLevel {
    static let batteryPowerLevel = TypedIdentifier(identifier: .batteryLevel)
}

public extension TypedIdentifier where CommonValueType == PropertyCommonValueFocusMode {
    static let focusMode = TypedIdentifier(identifier: .focusMode)
}

public extension TypedIdentifier where CommonValueType == PropertyCommonValueAutoExposureMode {
    static let autoExposureMode = TypedIdentifier(identifier: .autoExposureMode)
}

public extension TypedIdentifier where CommonValueType == PropertyCommonValueWhiteBalance {
    static let whiteBalance = TypedIdentifier(identifier: .whiteBalance)
}

public extension TypedIdentifier where CommonValueType == PropertyCommonValueLightMeterStatus {
    static let lightMeterStatus = TypedIdentifier(identifier: .lightMeterStatus)
}

public extension TypedIdentifier where CommonValueType == Int {
    static let shotsAvailable = TypedIdentifier(identifier: .shotsAvailable)
}

public extension TypedIdentifier where CommonValueType == PropertyCommonValueMirrorLockupStage {
    static let mirrorLockupStage = TypedIdentifier(identifier: .mirrorLockupStage)
}

public extension TypedIdentifier where CommonValueType == PropertyCommonValueAFSystem {
    static let afSystem = TypedIdentifier(identifier: .afSystem)
}

public extension TypedIdentifier where CommonValueType == PropertyCommonValueDriveMode {
    static let driveMode = TypedIdentifier(identifier: .driveMode)
}

public extension TypedIdentifier where CommonValueType == PropertyCommonValueImageDestination {
    static let imageDestination = TypedIdentifier(identifier: .imageDestination)
}

public extension TypedIdentifier where CommonValueType == VideoFormatValue {
    static let videoRecordingFormat = TypedIdentifier(identifier: .videoRecordingFormat)
}

public extension TypedIdentifier where CommonValueType == LiveViewZoomLevelValue {
    static let liveViewZoomLevel = TypedIdentifier(identifier: .liveViewZoomLevel)
}

public extension TypedIdentifier where CommonValueType == NoCommonValues {

    // Things we don't have common values for yet
    static let colorTone = TypedIdentifier(identifier: .colorTone)
    static let artFilter = TypedIdentifier(identifier: .artFilter)
    static let noiseReduction = TypedIdentifier(identifier: .noiseReduction)
    static let imageQuality = TypedIdentifier(identifier: .imageQuality)
    static let exposureMeteringMode = TypedIdentifier(identifier: .exposureMeteringMode)
}

// MARK: - Extensions to CascableCore Identifiers

extension PropertyIdentifier: @retroactive CaseIterable {
    static public var allCases: [PropertyIdentifier] = {
        return (0..<PropertyIdentifier.max.rawValue).compactMap { PropertyIdentifier(rawValue: $0) }
    }()
}

public extension PropertyCategory {

    /// Returns the property identifiers that are contained within this category.
    var propertyIdentifiers: [PropertyIdentifier] {
        // TODO: This is inefficient.
        return PropertyIdentifier.allCases.filter({ $0.category == self })
    }
}

public extension PropertyIdentifier {

    /// Returns the category that the property identifier belongs to.
    var category: PropertyCategory {
        switch self {
        case .isoSpeed, .shutterSpeed, .aperture, .exposureCompensation, .lightMeterReading,
                .videoISOSpeed, .videoShutterSpeed, .videoAperture, .videoExposureCompensation:
            return .exposureSetting

        case .afSystem, .focusMode, .driveMode, .mirrorLockupEnabled, .mirrorLockupStage, .digitalZoom:
            return .captureSetting

        case .whiteBalance, .colorTone, .artFilter, .autoExposureMode, .exposureMeteringMode:
            return .imagingSetting

        case .inCameraBracketingEnabled, .noiseReduction, .imageQuality, .imageDestination:
            return .configurationSetting

        case .batteryLevel, .powerSource, .shotsAvailable, .lensStatus, .lightMeterStatus, .dofPreviewEnabled, .readyForCapture:
            return .information

        case .videoRecordingFormat:
            return .videoFormat

        case .liveViewZoomLevel:
            return .liveViewZoomLevel

        case .max, .unknown:
            return .unknown

        @unknown default:
            return .unknown
        }
    }
}

// MARK: - Observation Helpers

public protocol PropertyObserverInvalidation: AnyObject {

    /// Remove the given observer from the property.
    /// 
    /// - Parameter observer: The observer to remove.
    func removeObserver(_ observer: CameraPropertyObservation)
}

internal class CameraPropertyObserverToken: NSObject, CameraPropertyObservation {

    static func == (lhs: CameraPropertyObserverToken, rhs: CameraPropertyObserverToken) -> Bool {
        return lhs.internalToken == rhs.internalToken
    }

    init(observing property: PropertyObserverInvalidation) {
        self.property = property
        self.internalToken = UUID().uuidString
    }

    override var hash: Int {
        return internalToken.hash
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? CameraPropertyObserverToken else { return false }
        return internalToken == other.internalToken
    }

    private(set) internal var internalToken: String
    private(set) weak var property: PropertyObserverInvalidation?

    func invalidate() {
        property?.removeObserver(self)
        property = nil
    }

    deinit {
        invalidate()
    }
}

// MARK: - Translation from CascableCore Types to Common Values

/// CascableCore properties that don't have any common value mappings (art filters, etc) will be declared as
/// having a `CommonValueType` of `NoCommonValues`, and values will always have a `commonValue` of `nil`.
public struct NoCommonValues: Equatable, TranslateableFromObjCCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> NoCommonValues? {
        return nil
    }
}

/// This protocol is to allow us to translate to strong types for our Swift API from the weaker types in the ObjC API.
public protocol TranslateableFromObjCCommonValue {
    static func translateFromCommonValue(_ commonValue: Any) -> Self?
}

extension Bool: TranslateableFromObjCCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> Bool? {
        guard let value = commonValue as? PropertyCommonValue else { return nil }
        guard value != PropertyCommonValueNone else { return nil }
        guard let boolValue = PropertyCommonValueBoolean(rawValue: value) else { return nil }
        return (boolValue == .true)
    }
}

extension Int: TranslateableFromObjCCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> Int? {
        guard let value = commonValue as? PropertyCommonValue else { return nil }
        guard value != PropertyCommonValueNone else { return nil }
        return value
    }
}

extension PropertyCommonValuePowerSource: TranslateableFromObjCCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> PropertyCommonValuePowerSource? {
        guard let typedValue = commonValue as? PropertyCommonValue else { return nil }
        guard typedValue != PropertyCommonValueNone else { return nil }
        return PropertyCommonValuePowerSource(rawValue: typedValue)
    }
}

extension PropertyCommonValueBatteryLevel: TranslateableFromObjCCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> PropertyCommonValueBatteryLevel? {
        guard let typedValue = commonValue as? PropertyCommonValue else { return nil }
        guard typedValue != PropertyCommonValueNone else { return nil }
        return PropertyCommonValueBatteryLevel(rawValue: typedValue)
    }
}

extension PropertyCommonValueFocusMode: TranslateableFromObjCCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> PropertyCommonValueFocusMode? {
        guard let typedValue = commonValue as? PropertyCommonValue else { return nil }
        guard typedValue != PropertyCommonValueNone else { return nil }
        return PropertyCommonValueFocusMode(rawValue: typedValue)
    }
}

extension PropertyCommonValueAutoExposureMode: TranslateableFromObjCCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> PropertyCommonValueAutoExposureMode? {
        guard let typedValue = commonValue as? PropertyCommonValue else { return nil }
        guard typedValue != PropertyCommonValueNone else { return nil }
        return PropertyCommonValueAutoExposureMode(rawValue: typedValue)
    }
}

extension PropertyCommonValueWhiteBalance: TranslateableFromObjCCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> PropertyCommonValueWhiteBalance? {
        guard let typedValue = commonValue as? PropertyCommonValue else { return nil }
        guard typedValue != PropertyCommonValueNone else { return nil }
        return PropertyCommonValueWhiteBalance(rawValue: typedValue)
    }
}

extension PropertyCommonValueMirrorLockupStage: TranslateableFromObjCCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> PropertyCommonValueMirrorLockupStage? {
        guard let typedValue = commonValue as? PropertyCommonValue else { return nil }
        guard typedValue != PropertyCommonValueNone else { return nil }
        return PropertyCommonValueMirrorLockupStage(rawValue: typedValue)
    }
}

extension PropertyCommonValueLightMeterStatus: TranslateableFromObjCCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> PropertyCommonValueLightMeterStatus? {
        guard let typedValue = commonValue as? PropertyCommonValue else { return nil }
        guard typedValue != PropertyCommonValueNone else { return nil }
        return PropertyCommonValueLightMeterStatus(rawValue: typedValue)
    }
}

extension PropertyCommonValueAFSystem: TranslateableFromObjCCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> PropertyCommonValueAFSystem? {
        guard let typedValue = commonValue as? PropertyCommonValue else { return nil }
        guard typedValue != PropertyCommonValueNone else { return nil }
        return PropertyCommonValueAFSystem(rawValue: typedValue)
    }
}

extension PropertyCommonValueDriveMode: TranslateableFromObjCCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> PropertyCommonValueDriveMode? {
        guard let typedValue = commonValue as? PropertyCommonValue else { return nil }
        guard typedValue != PropertyCommonValueNone else { return nil }
        return PropertyCommonValueDriveMode(rawValue: typedValue)
    }
}

extension PropertyCommonValueImageDestination: TranslateableFromObjCCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> PropertyCommonValueImageDestination? {
        guard let typedValue = commonValue as? PropertyCommonValue else { return nil }
        guard typedValue != PropertyCommonValueNone else { return nil }
        return PropertyCommonValueImageDestination(rawValue: typedValue)
    }
}

extension ISOValue: TranslateableFromObjCCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> Self? {
        return commonValue as? Self
    }
}

extension ApertureValue: TranslateableFromObjCCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> Self? {
        return commonValue as? Self
    }
}

extension ShutterSpeedValue: TranslateableFromObjCCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> Self? {
        return commonValue as? Self
    }
}

extension ExposureCompensationValue: TranslateableFromObjCCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> Self? {
        return commonValue as? Self
    }
}

extension VideoFormatValue: TranslateableFromObjCCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> VideoFormatValue? {
        guard let typedValue = commonValue as? VideoFormatPropertyValue else { return nil }
        let rate: Int? = (typedValue.frameRate == NSNotFound || typedValue.frameRate == 0) ? nil : typedValue.frameRate
        let size: CGSize? = (typedValue.frameSize == .zero) ? nil : typedValue.frameSize
        let compression: VideoFormatCompressionLevel? = (typedValue.compressionLevel == .unknown) ? nil : typedValue.compressionLevel
        return VideoFormatValue(frameRate: rate, frameSize: size, compressionLevel: compression)
    }
}

extension LiveViewZoomLevelValue: TranslateableFromObjCCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> LiveViewZoomLevelValue? {
        guard let typedValue = commonValue as? LiveViewZoomLevelPropertyValue else { return nil }
        return LiveViewZoomLevelValue(zoomedIn: typedValue.isZoomedIn,
                                      zoomFactor: typedValue.zoomFactor > 0.0 ? typedValue.zoomFactor : nil)
    }
}
