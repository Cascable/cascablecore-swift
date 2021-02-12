//
//  CascableCore+Swift.swift
//  CascableCore
//
//  Created by Daniel Kennett (Cascable) on 2021-01-23.
//  Copyright © 2021 Cascable AB. All rights reserved.
//

import Foundation
import StopKit
import CascableCore
import ObjectiveC

public extension Camera {

    /// Get a property object for the given identifier. If the property is currently unknown, returns an object
    /// with `currentValue`, `validSettableValues`, etc set to `nil`.
    ///
    /// The returned object is owned by the receiver, and the same object will be returned on subsequent calls to this
    /// method with the same identifier.
    ///
    /// - Parameter identifier: The identifier for the property.
    func property<CommonValueType>(for identifier: TypedIdentifier<CommonValueType>) -> TypedCameraProperty<CommonValueType> {
        if let existingProperty = propertyStorage[identifier.propertyIdentifier] as? TypedCameraProperty<CommonValueType> {
            return existingProperty
        }

        let new = TypedCameraProperty(identifier: identifier, wrapping: property(with: identifier.propertyIdentifier))
        propertyStorage[identifier.propertyIdentifier] = new
        return new
    }
}

fileprivate var typedPropertyStorageObjCHandle: UInt8 = 0

extension Camera {
    // Private API

    private var propertyStorage: [PropertyIdentifier: Any] {
        get { return objc_getAssociatedObject(self, &typedPropertyStorageObjCHandle) as? [PropertyIdentifier: Any] ?? [:] }
        set { objc_setAssociatedObject(self, &typedPropertyStorageObjCHandle, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

// MARK: -

/// An object representing the values for a property on the camera.
public class TypedCameraProperty<CommonValueType: Equatable & TranslateableFromCommonValue>: PropertyObserverInvalidation {

    fileprivate init(identifier propertyIdentifier: TypedIdentifier<CommonValueType>, wrapping property: CameraProperty) {
        identifier = propertyIdentifier
        category = identifier.propertyIdentifier.category
        wrappedProperty = property
        localizedDisplayName = property.localizedDisplayName
        camera = property.camera
        // ----- super.init() -----
        updateCurrentValue()
        updateValidSettableValues()
        setupObservers(to: property)
    }

    deinit {
        backingPropertyObserverToken?.invalidate()
    }

    /// The property's category.
    public let category: PropertyCategory

    /// The property's identifier.
    public let identifier: TypedIdentifier<CommonValueType>

    /// The camera from which the property is derived.
    public private(set) weak var camera: Camera?

    /// The untyped CascableCore property the receiver is wrapping.
    private let wrappedProperty: CameraProperty

    /// The property's display name.
    public let localizedDisplayName: String?

    // MARK: - Observation

    /// The callback signature for property observer callbacks.
    ///
    /// - Parameter sender: The property object that triggered the observation.
    /// - Parameter changeType: The change(s) that occurred. Can contain `.value`, `.validSettableValues`, or both.
    public typealias TypedCameraPropertyObservationCallback = (_ sender: TypedCameraProperty<CommonValueType>, _ changeType: PropertyChangeType) -> Void

    /// Add an observer to the property.
    ///
    /// The given observer callback will be called whenever the receiver's `currentValue` or `validSettableValues`
    /// properties change.
    ///
    /// The returned token is used to maintain ownership of the observation. The observation will be invalidated when
    /// the token is deallocated, `invalidate()` is called on the token, or the token is passed to the
    /// `removeObserver(_:)` method. Therefore, you must maintain a strong reference to the returned token in order
    /// to keep the observation active.
    ///
    /// - Parameter observer: The observer callback to add.
    /// - Returns: Returns an observer token. The observation will be removed when this token is deallocated.
    public func addObserver(_ observer: @escaping TypedCameraPropertyObservationCallback) -> CameraPropertyObservation {
        let token = CameraPropertyObserverToken(observing: self)
        observerStorage[token.internalToken] = observer
        return token
    }

    /// Remove the given observer from the property.
    ///
    /// - Parameter observer: The observer to remove.
    public func removeObserver(_ observer: CameraPropertyObservation) {
        guard let ourObserver = observer as? CameraPropertyObserverToken else { return }
        observerStorage.removeValue(forKey: ourObserver.internalToken)
    }

    // MARK: - Getting and Setting Values

    /// The current value of the property.
    private(set) public var currentValue: TypedCameraPropertyValue<CommonValueType>? = nil

    /// The values that are considered valid for this property.
    private(set) public var validSettableValues: [TypedCameraPropertyValue<CommonValueType>] = []

    /// Attempt to find a valid settable value for the given common value.
    ///
    /// - Parameter commonValue: The common value to find a value for.
    /// - Returns: Returns a valid settable value for the given target, or `nil` if no value matches.
    public func validValue(matching commonValue: CommonValueType) -> TypedCameraPropertyValue<CommonValueType>? {
        return validSettableValues.first(where: { $0.commonValue == commonValue })
    }

    /// Attempt to set a new value for the property. The value must be in the `validSettableValues` property.
    ///
    /// - Parameters:
    ///   - newValue: The value to set.
    ///   - completionQueue: The queue on which to call the completion handler.
    ///   - completionHandler: The completion handler to call when the operation succeeds or fails.
    public func setValue(_ newValue: TypedCameraPropertyValue<CommonValueType>, completionQueue: DispatchQueue = .main,
                  completionHandler: @escaping ErrorableOperationCallback) {
        wrappedProperty.setValue(newValue.wrappedPropertyValue, completionQueue: completionQueue, completionHandler: completionHandler)
    }

    // MARK: - Convenience Getters

    /// Returns the common value of the current value.
    ///
    /// - Note: Only a small number of property values have their values mapped into "common" values — a `nil` result
    /// from this property does not mean that `currentValue` is also `nil`.
    public var currentCommonValue: CommonValueType? {
        return currentValue?.commonValue
    }

    /// Returns the localized display value representing the current value.
    ///
    /// - Note: There are circumstances where a value may not have a localized display value — a `nil` result
    /// from this property does not mean that `currentValue` is also `nil`.
    public var currentLocalizedDisplayValue: String? {
        return currentValue?.localizedDisplayValue
    }

    /// Returns a debug-level string value representing the current value.
    ///
    /// - Note: A `nil` result from this property **does** mean that `currentValue` is `nil`.
    public var currentStringValue: String? {
        return currentValue?.stringValue
    }

    // MARK: - Private/Internal API

    private var observerStorage: [String: TypedCameraPropertyObservationCallback] = [:]
    private var backingPropertyObserverToken: CameraPropertyObservation?

    private func setupObservers(to property: CameraProperty) {
        backingPropertyObserverToken = property.addObserver({ [weak self] property, changeType in
            guard let self = self else { return }
            if changeType.contains(.value) { self.updateCurrentValue() }
            if changeType.contains(.validSettableValues) { self.updateValidSettableValues() }
            let observers = self.observerStorage.values
            observers.forEach({ $0(self, changeType) })
        })
    }

    private func updateCurrentValue() {
        if let value = wrappedProperty.currentValue {
            currentValue = TypedCameraPropertyValue<CommonValueType>(wrapping: value, of: identifier)
        } else {
            currentValue = nil
        }
    }

    private func updateValidSettableValues() {
        validSettableValues = wrappedProperty.validSettableValues?.compactMap({
            TypedCameraPropertyValue<CommonValueType>(wrapping: $0, of: identifier)
        }) ?? []
    }
}

extension TypedCameraProperty where CommonValueType: ExposureCompensationValue {

    /// Returns the item value in `validSettableValues` that is considered the "zero" value.
    /// For most properties this will be the first item in the array, but in some (for example,
    /// E.V.) it will be a value somewhere in the middle.
    ///
    /// Values at a lesser index than this value in `validSettableValues` are considered to
    /// be negative. This can be useful when constructing UI.

    /// Guaranteed to return a non-nil value if `validSettableValues` isn't empty.

    var validZeroValue: TypedCameraPropertyValue<ExposureCompensationValue>? {
        guard let exposureCompensations = validSettableValues as? [TypedCameraPropertyValue<ExposureCompensationValue>] else { return nil }
        let zeroEV = ExposureCompensationValue.zeroEV
        return exposureCompensations.first(where: { $0.commonValue == zeroEV })
    }
}

extension TypedCameraProperty where CommonValueType: ISOValue {

    /// Returns the value in `validSettableValues` that, when set, will cause the camera to
    /// attempt to derive the value for this property automatically.
    ///
    /// If there is no such value, returns `nil`.
    var validAutomaticValue: TypedCameraPropertyValue<ISOValue>? {
        guard let isos = validSettableValues as? [TypedCameraPropertyValue<ISOValue>] else { return nil }
        let autoISO = ISOValue.automaticISO
        return isos.first(where: { $0.commonValue == autoISO })
    }
}

// MARK: -

/// A property value. This could either be the current value of a property, or something in the list of values that can be set.
public struct TypedCameraPropertyValue<CommonValueType: Equatable & TranslateableFromCommonValue> {

    init(wrapping propertyValue: PropertyValue, of type: TypedIdentifier<CommonValueType>) {
        localizedDisplayValue = propertyValue.localizedDisplayValue
        stringValue = propertyValue.stringValue
        opaqueValue = propertyValue.opaqueValue
        wrappedPropertyValue = propertyValue

        if let exposureValue = propertyValue as? ExposurePropertyValue {
            commonValue = CommonValueType.translateFromCommonValue(exposureValue.exposureValue)
        } else {
            commonValue = CommonValueType.translateFromCommonValue(propertyValue.commonValue)
        }
    }

    /// The untyped CascableCore value the receiver is wrapping.
    public let wrappedPropertyValue: PropertyValue

    /// The common value that this value matches, or `nil` if it doesn't match any common value.
    public let commonValue: CommonValueType?

    /// A localized display value for the value. May be `nil` if the value is unknown to CascableCore and
    /// a display value is not provided by the camera.
    public let localizedDisplayValue: String?

    /// A string value for the value. Will always return *something*, but the quality is not guaranteed — particularly
    /// if the value is unknown to CascableCore and a display value is not provided by the camera.
    public let stringValue: String

    /// An opaque value representing the property. Not guaranteed to be anything in particular, as this is an internal
    /// implementation detail for each particular camera.
    public let opaqueValue: Any
}
