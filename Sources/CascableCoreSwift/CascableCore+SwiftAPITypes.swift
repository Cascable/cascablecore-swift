//
//  SwiftAPITypes.swift
//  CascableCore Demo
//
//  Created by Daniel Kennett (Cascable) on 2021-01-24.
//  Copyright © 2021 Cascable AB. All rights reserved.
//

import Foundation
import CascableCore

// MARK: - Types

/// A `TypedIdentifier` is a strongly-typed replacement for `CBLPropertyIdentifier`.
public struct TypedIdentifier<CommonValueType: Equatable & TranslateableFromCommonValue> {
    public let propertyIdentifier: PropertyIdentifier
    public let commonValueType: CommonValueType.Type

    fileprivate init(identifier: PropertyIdentifier, type: CommonValueType.Type) {
        propertyIdentifier = identifier
        commonValueType = type
    }
}

// MARK: - Property Identifier Declarations

public extension TypedIdentifier {

    // Exposure values
    static var aperture: TypedIdentifier<ApertureValue> { return PropertyIdentifierStorage.aperture }
    static var shutterSpeed: TypedIdentifier<ShutterSpeedValue> { return PropertyIdentifierStorage.shutterSpeed }
    static var iso: TypedIdentifier<ISOValue> { return PropertyIdentifierStorage.iso }
    static var exposureCompensation: TypedIdentifier<ExposureCompensationValue> { return PropertyIdentifierStorage.exposureCompensation }
    static var lightMeterReading: TypedIdentifier<ExposureCompensationValue> { return PropertyIdentifierStorage.lightMeterReading }

    // Bools
    static var lensStatus: TypedIdentifier<Bool> { return PropertyIdentifierStorage.lensStatus }
    static var mirrorLockupEnabled: TypedIdentifier<Bool> { return PropertyIdentifierStorage.mirrorLockupEnabled }
    static var dofPreviewEnabled: TypedIdentifier<Bool> { return PropertyIdentifierStorage.dofPreviewEnabled }
    static var digitalZoomEnabled: TypedIdentifier<Bool> { return PropertyIdentifierStorage.digitalZoomEnabled }
    static var inCameraBracketingEnabled: TypedIdentifier<Bool> { return PropertyIdentifierStorage.inCameraBracketingEnabled }
    static var readyForCapture: TypedIdentifier<Bool> { return PropertyIdentifierStorage.readyForCapture }

    // Others
    static var powerSource: TypedIdentifier<PropertyCommonValuePowerSource> { return PropertyIdentifierStorage.powerSource }
    static var batteryPowerLevel: TypedIdentifier<PropertyCommonValueBatteryLevel> { return PropertyIdentifierStorage.batteryPowerLevel }
    static var focusMode: TypedIdentifier<PropertyCommonValueFocusMode> { return PropertyIdentifierStorage.focusMode }
    static var autoExposureMode: TypedIdentifier<PropertyCommonValueAutoExposureMode> { return PropertyIdentifierStorage.autoExposureMode }
    static var whiteBalance: TypedIdentifier<PropertyCommonValueWhiteBalance> { return PropertyIdentifierStorage.whiteBalance }
    static var lightMeterStatus: TypedIdentifier<PropertyCommonValueLightMeterStatus> { return PropertyIdentifierStorage.lightMeterStatus }
    static var shotsAvailable: TypedIdentifier<Int> { return PropertyIdentifierStorage.shotsAvailable }
    static var mirrorLockupStage: TypedIdentifier<PropertyCommonValueMirrorLockupStage> { return PropertyIdentifierStorage.mirrorLockupStage }
    static var afSystem: TypedIdentifier<PropertyCommonValueAFSystem> { return PropertyIdentifierStorage.afSystem }
    static var driveMode: TypedIdentifier<PropertyCommonValueDriveMode> { return PropertyIdentifierStorage.driveMode }

    // Things we don't have common values for yet
    static var colorTone: TypedIdentifier<NoCommonValues> { return PropertyIdentifierStorage.colorTone }
    static var artFilter: TypedIdentifier<NoCommonValues> { return PropertyIdentifierStorage.artFilter }
    static var noiseReduction: TypedIdentifier<NoCommonValues> { return PropertyIdentifierStorage.noiseReduction }
    static var imageQuality: TypedIdentifier<NoCommonValues> { return PropertyIdentifierStorage.imageQuality }
    static var exposureMeteringMode: TypedIdentifier<NoCommonValues> { return PropertyIdentifierStorage.exposureMeteringMode }
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

// MARK: - Property Identifier Storage

// Swift doesn't let us have static stored properties in extensions _or_ in generic types (i.e., the original struct),
// so we need to do a bit of a song and dance to achieve that sort of API on our TypedIdentifier<> type.
fileprivate struct PropertyIdentifierStorage {
    // Exposure values
    static let aperture = TypedIdentifier<ApertureValue>(identifier: .aperture, type: ApertureValue.self)
    static let shutterSpeed = TypedIdentifier<ShutterSpeedValue>(identifier: .shutterSpeed, type: ShutterSpeedValue.self)
    static let iso = TypedIdentifier<ISOValue>(identifier: .isoSpeed, type: ISOValue.self)
    static let exposureCompensation = TypedIdentifier<ExposureCompensationValue>(identifier: .exposureCompensation, type: ExposureCompensationValue.self)
    static let lightMeterReading = TypedIdentifier<ExposureCompensationValue>(identifier: .lightMeterReading, type: ExposureCompensationValue.self)

    // Bools
    static let lensStatus = TypedIdentifier<Bool>(identifier: .lensStatus, type: Bool.self)
    static let mirrorLockupEnabled = TypedIdentifier<Bool>(identifier: .mirrorLockupEnabled, type: Bool.self)
    static let dofPreviewEnabled = TypedIdentifier<Bool>(identifier: .dofPreviewEnabled, type: Bool.self)
    static let digitalZoomEnabled = TypedIdentifier<Bool>(identifier: .digitalZoom, type: Bool.self)
    static let inCameraBracketingEnabled = TypedIdentifier<Bool>(identifier: .inCameraBracketingEnabled, type: Bool.self)
    static let readyForCapture = TypedIdentifier<Bool>(identifier: .readyForCapture, type: Bool.self)

    // Others
    static let powerSource = TypedIdentifier<PropertyCommonValuePowerSource>(identifier: .powerSource, type: PropertyCommonValuePowerSource.self)
    static let batteryPowerLevel = TypedIdentifier<PropertyCommonValueBatteryLevel>(identifier: .batteryLevel, type: PropertyCommonValueBatteryLevel.self)
    static let focusMode = TypedIdentifier<PropertyCommonValueFocusMode>(identifier: .focusMode, type: PropertyCommonValueFocusMode.self)
    static let autoExposureMode = TypedIdentifier<PropertyCommonValueAutoExposureMode>(identifier: .autoExposureMode, type: PropertyCommonValueAutoExposureMode.self)
    static let whiteBalance = TypedIdentifier<PropertyCommonValueWhiteBalance>(identifier: .whiteBalance, type: PropertyCommonValueWhiteBalance.self)
    static let lightMeterStatus = TypedIdentifier<PropertyCommonValueLightMeterStatus>(identifier: .lightMeterStatus, type: PropertyCommonValueLightMeterStatus.self)
    static let shotsAvailable = TypedIdentifier<Int>(identifier: .shotsAvailable, type: Int.self)
    static let mirrorLockupStage = TypedIdentifier<PropertyCommonValueMirrorLockupStage>(identifier: .mirrorLockupStage, type: PropertyCommonValueMirrorLockupStage.self)
    static let afSystem = TypedIdentifier<PropertyCommonValueAFSystem>(identifier: .afSystem, type: PropertyCommonValueAFSystem.self)
    static let driveMode = TypedIdentifier<PropertyCommonValueDriveMode>(identifier: .driveMode, type: PropertyCommonValueDriveMode.self)

    // Things we don't have common values for yet
    static let colorTone = TypedIdentifier<NoCommonValues>(identifier: .colorTone, type: NoCommonValues.self)
    static let artFilter = TypedIdentifier<NoCommonValues>(identifier: .artFilter, type: NoCommonValues.self)
    static let noiseReduction = TypedIdentifier<NoCommonValues>(identifier: .noiseReduction, type: NoCommonValues.self)
    static let imageQuality = TypedIdentifier<NoCommonValues>(identifier: .imageQuality, type: NoCommonValues.self)
    static let exposureMeteringMode = TypedIdentifier<NoCommonValues>(identifier: .exposureMeteringMode, type: NoCommonValues.self)
}
