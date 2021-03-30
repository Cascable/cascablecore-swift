import Foundation
import CascableCore
import Combine

// MARK: - Public API

public extension CameraProperties {

    /// Create a publisher for a given property identifier that emits a new value whenever the current or
    /// valid settable values for that property changes.
    ///
    /// The created publisher will immediately emit the property's current state.
    ///
    /// - Parameter propertyIdentifier: The property identifier to create a publisher for.
    @available(iOS 13.0, macOS 10.15, *)
    func publisher<CommonValueType>(for propertyIdentifier: TypedIdentifier<CommonValueType>) ->
        AnyPublisher<TypedCameraProperty<CommonValueType>, Never> {

        return TypedPropertyValuePublisher(observing: property(for: propertyIdentifier), on: [.value, .validSettableValues],
                                           valueTranslation: { $0 }).eraseToAnyPublisher()
    }

    /// Create a publisher for values of the given property identifier.
    ///
    /// The created publisher will immediately emit the property's current value.
    ///
    /// - Parameter propertyIdentifier: The property identifier to create a publisher for.
    @available(iOS 13.0, macOS 10.15, *)
    func valuePublisher<CommonValueType>(for propertyIdentifier: TypedIdentifier<CommonValueType>) ->
        AnyPublisher<TypedCameraPropertyValue<CommonValueType>?, Never> {

        return TypedPropertyValuePublisher(observing: property(for: propertyIdentifier), on: .value,
                                           valueTranslation: { $0.currentValue }).eraseToAnyPublisher()
    }

    /// Create a publisher for the valid settable values of the given property identifier.
    ///
    /// The created publisher will immediately emit the property's current valid settable values.
    ///
    /// - Parameter propertyIdentifier: The property identifier to create a publisher for.
    @available(iOS 13.0, macOS 10.15, *)
    func settableValuesPublisher<CommonValueType>(for propertyIdentifier: TypedIdentifier<CommonValueType>) ->
            AnyPublisher<[TypedCameraPropertyValue<CommonValueType>], Never> {

        return TypedPropertyValuePublisher(observing: property(for: propertyIdentifier), on: .validSettableValues,
                                           valueTranslation: { $0.validSettableValues }).eraseToAnyPublisher()
    }

}

@available(iOS 13.0, macOS 10.15, *)
public extension Publisher {

    /**
     This extension contains convenience publishers for flattening out combined publishers.

     For instance:

     ```
     camera.valuePublisher(for: .shutterSpeed)
         .combineLatest(camera.valuePublisher(for: .aperture))
         .combineLatest(camera.valuePublisher(for: .iso))
         .flatten()
         .sink { shutter, aperture, iso in
             print("The exposure triangle is shutter: \(shutter), aperture: \(aperture), ISO: \(iso?)")
         }
     ```
     */

    /// Returns a publisher where the nested tuples are flattened into a single tuple.
    func flatten<A, B, C>() -> Publishers.Map<Self, (A, B, C)> where Output == ((A, B), C) {
        map { tuple in (tuple.0.0, tuple.0.1, tuple.1) }
    }

    /// Returns a publisher where the nested tuples are flattened into a single tuple.
    func flatten<A, B, C, D>() -> Publishers.Map<Self, (A, B, C, D)> where Output == (((A, B), C), D) {
        map { tuple in (tuple.0.0.0, tuple.0.0.1, tuple.0.1, tuple.1) }
    }

    /// Returns a publisher where the nested tuples are flattened into a single tuple.
    func flatten<A, B, C, D, E>() -> Publishers.Map<Self, (A, B, C, D, E)> where Output == ((((A, B), C), D), E) {
        map { tuple in (tuple.0.0.0.0, tuple.0.0.0.1, tuple.0.0.1, tuple.0.1, tuple.1) }
    }

    /// Returns a publisher where the nested tuples are flattened into a single tuple.
    func flatten<A, B, C, D, E, F>() -> Publishers.Map<Self, (A, B, C, D, E, F)> where Output == (((((A, B), C), D), E), F) {
        map { tuple in (tuple.0.0.0.0.0, tuple.0.0.0.0.1, tuple.0.0.0.1, tuple.0.0.1, tuple.0.1, tuple.1) }
    }
}

/// A Combine publisher that delivers property values.
@available(iOS 13.0, macOS 10.15, *)
public struct TypedPropertyValuePublisher<CommonValueType: TypedCommonValue, PublishedType>: Publisher {
    public typealias Output = PublishedType
    public typealias Failure = Never

    public typealias TypedPropertyConversionHandler = (TypedCameraProperty<CommonValueType>) -> PublishedType
    private let observedProperty: TypedCameraProperty<CommonValueType>
    private let valueTranslationHandler: TypedPropertyConversionHandler
    private let changeTypes: PropertyChangeType

    /// Create a new publisher from the given property.
    ///
    /// - Parameters:
    ///   - property: The property to publish values from.
    ///   - propertyChangeTypes: The property change types to trigger on - `.value`, `.validSettableValues`, or both.
    ///   - valueTranslation: A closure that will be called when a change is triggered. Use this to generate the publisher's published value.
    public init(observing property: TypedCameraProperty<CommonValueType>, on propertyChangeTypes: PropertyChangeType,
         valueTranslation: @escaping TypedPropertyConversionHandler) {
        observedProperty = property
        valueTranslationHandler = valueTranslation
        changeTypes = propertyChangeTypes
    }

    public func receive<S>(subscriber: S) where S : Subscriber, Self.Failure == S.Failure, Self.Output == S.Input {
        subscriber.receive(subscription: Subscription(observing: observedProperty, on: changeTypes,
                                                      translationHandler: valueTranslationHandler, subscriber: subscriber))
    }

    fileprivate final class Subscription<Subscriber>: Combine.Subscription
        where Subscriber: Combine.Subscriber, Subscriber.Failure == Failure, Subscriber.Input == Output {

        private let subscriber: Subscriber
        private let property: TypedCameraProperty<CommonValueType>
        private let valueTranslationHandler: TypedPropertyConversionHandler
        private let changeTypes: PropertyChangeType
        private var observerToken: CameraPropertyObservation?

        fileprivate init(observing property: TypedCameraProperty<CommonValueType>, on propertyChangeType: PropertyChangeType,
                         translationHandler: @escaping TypedPropertyConversionHandler, subscriber: Subscriber) {
            self.property = property
            self.subscriber = subscriber
            self.changeTypes = propertyChangeType
            self.valueTranslationHandler = translationHandler
        }

        private var subscriptionDemand: Subscribers.Demand = .none

        func request(_ demand: Subscribers.Demand) {
            subscriptionDemand += demand

            // If there's no demand, don't subscribe yet.
            guard demand > .none else { return }

            // If there *is* demand but we've already started observing, nothing else to do.
            guard observerToken == nil else { return }

            observerToken = property.addObserver({ [weak self] sender, change in
                guard let self = self, !change.union(self.changeTypes).isEmpty else { return }
                guard self.subscriptionDemand > .none else { return }
                self.deliverValue(from: sender)
            })

            // TODO: Do we want this?
            deliverValue(from: property)
        }

        private func deliverValue(from property: TypedCameraProperty<CommonValueType>) {
            subscriptionDemand -= 1
            subscriptionDemand += subscriber.receive(valueTranslationHandler(property))
        }

        func cancel() {
            observerToken?.invalidate()
            observerToken = nil
        }
    }
}

