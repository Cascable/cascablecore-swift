import Foundation
import CascableCore

// MARK: - Types

/// A `TypedIdentifier` is a strongly-typed replacement for `CBLPropertyIdentifier`.
public struct TypedIdentifier<CommonValueType: Equatable & TranslateableFromCommonValue> {
    public let propertyIdentifier: PropertyIdentifier

    fileprivate init(identifier: PropertyIdentifier) {
        propertyIdentifier = identifier
    }
}

// MARK: - Property Identifier Declarations

public extension TypedIdentifier where CommonValueType == ApertureValue {
    static let aperture = TypedIdentifier(identifier: .aperture)
}

public extension TypedIdentifier where CommonValueType == ShutterSpeedValue {
    static let shutterSpeed = TypedIdentifier(identifier: .shutterSpeed)
}

public extension TypedIdentifier where CommonValueType == ISOValue {
    static let iso = TypedIdentifier(identifier: .isoSpeed)
}

public extension TypedIdentifier where CommonValueType == ExposureCompensationValue {
    static let exposureCompensation = TypedIdentifier(identifier: .exposureCompensation)
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

public extension TypedIdentifier where CommonValueType == NoCommonValues {

    // Things we don't have common values for yet
    static let colorTone = TypedIdentifier(identifier: .colorTone)
    static let artFilter = TypedIdentifier(identifier: .artFilter)
    static let noiseReduction = TypedIdentifier(identifier: .noiseReduction)
    static let imageQuality = TypedIdentifier(identifier: .imageQuality)
    static let exposureMeteringMode = TypedIdentifier(identifier: .exposureMeteringMode)
}

// MARK: - Extensions to CascableCore Identifiers

extension PropertyIdentifier: CaseIterable {
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
        case .isoSpeed, .shutterSpeed, .aperture, .exposureCompensation, .lightMeterReading:
            return .exposureSetting

        case .afSystem, .focusMode, .driveMode, .mirrorLockupEnabled, .mirrorLockupStage, .digitalZoom:
            return .captureSetting

        case .whiteBalance, .colorTone, .artFilter, .autoExposureMode, .exposureMeteringMode:
            return .imagingSetting

        case .inCameraBracketingEnabled, .noiseReduction, .imageQuality:
            return .configurationSetting

        case .batteryLevel, .powerSource, .shotsAvailable, .lensStatus, .lightMeterStatus, .dofPreviewEnabled, .readyForCapture:
            return .information

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
public struct NoCommonValues: Equatable, TranslateableFromCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> NoCommonValues? {
        return nil
    }
}

/// This protocol is to allow us to translate to strong types for our Swift API from the weaker types in the ObjC API.
public protocol TranslateableFromCommonValue {
    static func translateFromCommonValue(_ commonValue: Any) -> Self?
}

extension Bool: TranslateableFromCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> Bool? {
        guard let value = commonValue as? PropertyCommonValue else { return nil }
        guard value != PropertyCommonValueNone else { return nil }
        guard let boolValue = PropertyCommonValueBoolean(rawValue: value) else { return nil }
        return (boolValue == .true)
    }
}

extension Int: TranslateableFromCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> Int? {
        guard let value = commonValue as? PropertyCommonValue else { return nil }
        guard value != PropertyCommonValueNone else { return nil }
        return value
    }
}

extension PropertyCommonValuePowerSource: TranslateableFromCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> PropertyCommonValuePowerSource? {
        guard let typedValue = commonValue as? PropertyCommonValue else { return nil }
        guard typedValue != PropertyCommonValueNone else { return nil }
        return PropertyCommonValuePowerSource(rawValue: typedValue)
    }
}

extension PropertyCommonValueBatteryLevel: TranslateableFromCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> PropertyCommonValueBatteryLevel? {
        guard let typedValue = commonValue as? PropertyCommonValue else { return nil }
        guard typedValue != PropertyCommonValueNone else { return nil }
        return PropertyCommonValueBatteryLevel(rawValue: typedValue)
    }
}

extension PropertyCommonValueFocusMode: TranslateableFromCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> PropertyCommonValueFocusMode? {
        guard let typedValue = commonValue as? PropertyCommonValue else { return nil }
        guard typedValue != PropertyCommonValueNone else { return nil }
        return PropertyCommonValueFocusMode(rawValue: typedValue)
    }
}

extension PropertyCommonValueAutoExposureMode: TranslateableFromCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> PropertyCommonValueAutoExposureMode? {
        guard let typedValue = commonValue as? PropertyCommonValue else { return nil }
        guard typedValue != PropertyCommonValueNone else { return nil }
        return PropertyCommonValueAutoExposureMode(rawValue: typedValue)
    }
}

extension PropertyCommonValueWhiteBalance: TranslateableFromCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> PropertyCommonValueWhiteBalance? {
        guard let typedValue = commonValue as? PropertyCommonValue else { return nil }
        guard typedValue != PropertyCommonValueNone else { return nil }
        return PropertyCommonValueWhiteBalance(rawValue: typedValue)
    }
}

extension PropertyCommonValueMirrorLockupStage: TranslateableFromCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> PropertyCommonValueMirrorLockupStage? {
        guard let typedValue = commonValue as? PropertyCommonValue else { return nil }
        guard typedValue != PropertyCommonValueNone else { return nil }
        return PropertyCommonValueMirrorLockupStage(rawValue: typedValue)
    }
}

extension PropertyCommonValueLightMeterStatus: TranslateableFromCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> PropertyCommonValueLightMeterStatus? {
        guard let typedValue = commonValue as? PropertyCommonValue else { return nil }
        guard typedValue != PropertyCommonValueNone else { return nil }
        return PropertyCommonValueLightMeterStatus(rawValue: typedValue)
    }
}

extension PropertyCommonValueAFSystem: TranslateableFromCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> PropertyCommonValueAFSystem? {
        guard let typedValue = commonValue as? PropertyCommonValue else { return nil }
        guard typedValue != PropertyCommonValueNone else { return nil }
        return PropertyCommonValueAFSystem(rawValue: typedValue)
    }
}

extension PropertyCommonValueDriveMode: TranslateableFromCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> PropertyCommonValueDriveMode? {
        guard let typedValue = commonValue as? PropertyCommonValue else { return nil }
        guard typedValue != PropertyCommonValueNone else { return nil }
        return PropertyCommonValueDriveMode(rawValue: typedValue)
    }
}

extension ISOValue: TranslateableFromCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> Self? {
        return commonValue as? Self
    }
}

extension ApertureValue: TranslateableFromCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> Self? {
        return commonValue as? Self
    }
}

extension ShutterSpeedValue: TranslateableFromCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> Self? {
        return commonValue as? Self
    }
}

extension ExposureCompensationValue: TranslateableFromCommonValue {
    public static func translateFromCommonValue(_ commonValue: Any) -> Self? {
        return commonValue as? Self
    }
}
