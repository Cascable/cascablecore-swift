import CascableCore
import Foundation
import StopKit

/// Stepped properties can be difficult to work with if you need to target specific values — for example, for
/// automation or saving/restoring camera settings. This file contains helper logic for targeting explicit
/// values for stepped exposure properties.

// MARK: - Public API

public extension TypedCameraProperty where CommonValueType: TypedCommonExposureValue {

    /// Attempt to step the property to the value closest to the target value.
    ///
    /// - Parameter targetValue: The value to search for.
    /// - Returns: Returns a search result containing the value the property was set to, and the type of match.
    /// - Throws: Throws a `SteppedSearchError` if an error occured.
    func stepToValue(closestTo targetValue: CommonValueType) async throws -> SteppedSearchResult<CommonValueType> {
        guard valueSetType == .stepping else { throw SteppedSearchError.propertyNotSteppable }
        guard targetValue.isDeterminate else { throw SteppedSearchError.invalidTargetValue }
        return try await SteppedPropertyValueSearch(self).stepToValue(closestTo: targetValue)
    }
}

/// The result of a stepped search operation.
public struct SteppedSearchResult<ValueType: TypedCommonExposureValue> {
    /// The common value of the value the property is now set to.
    public let commonValue: ValueType
    /// The type of match.
    public let matchType: MatchType

    public enum MatchType {
        /// The result is an exact match for the target value.
        case exact
        /// The result is an inexact match for the target value. For example, searching for ISO 125 when the camera
        /// is set to whole stops for ISO (100, 200, 400, …) would return an `.inexact` match with a result of ISO 100.
        case inexact
        /// The stepping operation reached the end of the range of values the property supports. For example, searching
        /// for an aperture of f/1.8 when the camera has an f/4 lens attached would return a `.reachedEndOfRange` match
        /// with a result of f/4.
        case reachedEndOfRange
    }
}

/// Errors that can occur during the stepping operation.
public enum SteppedSearchError: Error {
    /// The property isn't steppable.
    case propertyNotSteppable
    /// The property's current value is either `nil` or a non-determinate value ("Auto", "Bulb", etc).
    case invalidStartValue
    /// The given target value is inappropriate in some way — usually because it's non-determinate ("Auto", "Bulb", etc).
    case invalidTargetValue
    /// The property entered an unexpected state during the operation. This can happen if the camera is interfered with
    /// externally during the operation, which can be fairly long-running.
    case unexpectedState
    /// The stepping operation stepped too many times than is reasonable for the values given.
    case overrun
}

/// An object for stepping through a stepped property's values to find target values.
public actor SteppedPropertyValueSearch<CommonValueType: TypedCommonExposureValue> {

    /// Initialise the search object with the given property.
    public init(_ property: TypedCameraProperty<CommonValueType>) {
        steppedValueProvider = property
    }

    /// Attempt to set the target value by stepping through the property's values until the closest match is found.
    ///
    /// - Warning: This method should never be called more than once at the same time.
    ///
    /// - Parameter targetValue: The value to search for.
    /// - Returns: Returns a search result containing the value the property was set to, and the type of match.
    /// - Throws: Throws a `SteppedSearchError` if an error occured.
    public func stepToValue(closestTo targetValue: CommonValueType) async throws -> SteppedSearchResult<CommonValueType> {

        /*
         This is logic to find the value closest to the given value for our stepped property. For simplicity's sake,
         both the start value and target value must be deterministic values.

         Flow:
            - If the value already matches, exit early.
            - Make an assumption on whether to increment or decrement based on property type, current value, and given value.
            - In our first movement, verify our assumption is correct and switch directions if not.
            - Start making increments.
               - If we encounter a non-move (i.e., no value change), consider that the end of the list.
               - If we encounter a move into a non-deterministic value, reverse the previous move and consider that the end of the list.
               - If we encounter a move that significantly changes the delta, we may have gone around — reverse the move and consider that the end of the list.
               - If we overshoot, check the previous value for which is closest to the target. If the previous was, move back.
         */

        let property = self.steppedValueProvider
        guard targetValue.isDeterminate else { throw SteppedSearchError.invalidTargetValue }
        guard let startValue = property.currentUniversalCommonValue, startValue.isDeterminate else {
            throw SteppedSearchError.invalidStartValue
        }

        guard !startValue.isEqual(targetValue) else { return .init(commonValue: targetValue, matchType: .exact) }
        guard let startDelta = targetValue.stopsDifference(from: startValue) else { throw SteppedSearchError.unexpectedState }

        // We want to make a reasonably smart decision on which way to go. We're effectively iterating through a list
        // one item at a time, and cameras tend to lay out this list in particular ways.
        let assumedDirection: SteppedPropertyDirection = try {
            switch CommonValueType.self {
            case is ISOValue.Type:
                // ISO values are usually in ascending stop order (100 -> 200 -> 400 -> …)
                return startDelta.isNegative ? .decrement : .increment
            case is ExposureCompensationValue.Type:
                // EV values are usually in ascending stop order (-3.0 -> … -> 0.0 -> … -> +3.0)
                return startDelta.isNegative ? .decrement : .increment
            case is ApertureValue.Type:
                // Aperture values are usually in descending stop order (2.8 -> 4.0 -> 5.6 -> …)
                return startDelta.isNegative ? .increment : .decrement
            case is ShutterSpeedValue.Type:
                // Shutter speed values are usually in descending stop order (1" -> … -> 1/200 -> … 1/4000)
                return startDelta.isNegative ? .increment : .decrement
            default:
                // A classic "this shouldn't happen".
                throw SteppedSearchError.unexpectedState
            }
        }()

        let firstStepResult = try await property.step(in: assumedDirection)
        if firstStepResult.isEqual(targetValue) {
            // That was lucky!
            return .init(commonValue: firstStepResult as! CommonValueType, matchType: .exact)
        }

        let firstStepCorrectedResult: (correctedDirection: SteppedPropertyDirection,
                     correctionSteps: () async throws -> UniversalExposurePropertyValue?) = try {
            switch relationship(from: startValue, to: firstStepResult) {
            case .noChange:
                // We appear to be at the start/end of a list. If our assumption was wrong, going the other way once
                // *should* get us going in the correct direction.
                return (assumedDirection.reversed, {
                    return try await property.step(in: assumedDirection.reversed)
                })

            case .becameIndeterminate, .wrappedAround:
                // We appear to have gone off the end of the list of determinate values. If our assumption was wrong,
                // going the other way twice *should* put us back in the correct direction.
                return (assumedDirection.reversed, {
                    let _ = try await property.step(in: assumedDirection.reversed)
                    return try await property.step(in: assumedDirection.reversed)
                })

            case .normalStep:
                guard let deltaAfterFirstStep = targetValue.stopsDifference(from: firstStepResult) else {
                    throw SteppedSearchError.unexpectedState
                }

                let normalizedStartDelta = abs(startDelta.approximateDecimalValue)
                let normalizedNewDelta = abs(deltaAfterFirstStep.approximateDecimalValue)
                if normalizedNewDelta < normalizedStartDelta {
                    // We were right and we have the leeway to move!
                    return (assumedDirection, { return firstStepResult })
                } else {
                    // We went one step in the wrong direction. Go the other way twice to correct the mistake.
                    return (assumedDirection.reversed, {
                        let _ = try await property.step(in: assumedDirection.reversed)
                        return try await property.step(in: assumedDirection.reversed)
                    })
                }
            }
        }()

        // After our first operation, we may need to take corrective action. Do that now.
        let correctedDirection = firstStepCorrectedResult.correctedDirection
        guard let valueAfterCorrectedFirstStep = try await firstStepCorrectedResult.correctionSteps() else {
            throw SteppedSearchError.unexpectedState
        }

        // At this point, `valueAfterCorrectedFirstStep` _should_ be one step in the correct direction
        // from the start value. If it's not, we were correct with our initial assumption, but already at
        // the end of a list. If that's the case, go _back_ one step to put the property back where it started
        // and bail. If the valueAfterCorrectedFirstStep is the start value, the property is read-only.
        guard let newDelta = targetValue.stopsDifference(from: valueAfterCorrectedFirstStep) else {
            throw SteppedSearchError.unexpectedState
        }

        let normalizedStartDelta = abs(startDelta.approximateDecimalValue)
        let normalizedAfterFirstStepDelta = abs(newDelta.approximateDecimalValue)

        if normalizedAfterFirstStepDelta > normalizedStartDelta {
            // After correction, we ended up further away from the result than we wanted. That means that
            // we were correct about our assumption and the value was already as close to the target as we can get.
            let backToStartValue = try await property.step(in: correctedDirection.reversed)
            return .init(commonValue: backToStartValue as! CommonValueType, matchType: .reachedEndOfRange)

        } else if normalizedAfterFirstStepDelta <= normalizedStartDelta && startDelta.isNegative != newDelta.isNegative {
            // After correction, we skipped over the value and ended up closer to the target. This can happen
            // if the target is in between the first and second values in the list.
            return .init(commonValue: valueAfterCorrectedFirstStep as! CommonValueType, matchType: .inexact)
        }

        // Finally, we've confirmed our direction and that we can go in that direction. Time to get stepping!
        var previousValue = valueAfterCorrectedFirstStep
        var stepCount: Int = 0
        let overrunLimit: Int = Int(ceil(normalizedAfterFirstStepDelta * 6.0)) // Allow a few steps per stop.

        while stepCount < overrunLimit {
            let cameraCurrentValue = try await property.step(in: correctedDirection)
            if cameraCurrentValue.isEqual(targetValue) {
                return .init(commonValue: cameraCurrentValue as! CommonValueType, matchType: .exact)
            }

            let relationship = relationship(from: previousValue, to: cameraCurrentValue)
            switch relationship {
            case .noChange:
                // If the value is no longer changing, we're at the end of the list of values.
                return .init(commonValue: cameraCurrentValue as! CommonValueType, matchType: .reachedEndOfRange)

            case .becameIndeterminate, .wrappedAround:
                // We fell off the end of the list of values — back up a step.
                let correctedValue = try await property.step(in: correctedDirection.reversed)
                return .init(commonValue: correctedValue as! CommonValueType, matchType: .reachedEndOfRange)

            case .normalStep:
                // We did a normal step, and we didn't get an exact match.
                guard let currentValueStopsDifference = cameraCurrentValue.stopsDifference(from: targetValue),
                      let previousStopsDifference = previousValue.stopsDifference(from: targetValue) else {
                    throw SteppedSearchError.unexpectedState
                }

                let currentValueAbsoluteDifference = abs(currentValueStopsDifference.approximateDecimalValue)
                let previousValueAbsoluteDifference = abs(previousStopsDifference.approximateDecimalValue)

                if currentValueStopsDifference.isNegative != previousStopsDifference.isNegative {
                    // We overshot!
                    if currentValueAbsoluteDifference < previousValueAbsoluteDifference {
                        return .init(commonValue: cameraCurrentValue as! CommonValueType, matchType: .inexact)
                    } else {
                        // The previous result was closer — back it up!
                        let woahHangOnThere = try await property.step(in: correctedDirection.reversed)
                        return .init(commonValue: woahHangOnThere as! CommonValueType, matchType: .inexact)
                    }
                }

                // We didn't get there, but didn't overshoot. Carry on!
                if currentValueAbsoluteDifference >= previousValueAbsoluteDifference {
                    assertionFailure("WARNING!: We're stepping towards \(targetValue), but step is further away than previous")
                }

                previousValue = cameraCurrentValue
            }

            stepCount += 1
        }

        throw SteppedSearchError.overrun
    }

    // MARK: Implementation Details

    /// Initialise the search object with the given mock property stepper.
    internal init(_ mockProvider: SteppedPropertyValueProvider) {
        steppedValueProvider = mockProvider
    }

    private let steppedValueProvider: SteppedPropertyValueProvider

    private enum Relationship {
        /// The two values are the same.
        case noChange
        /// The value became indeterminate (i.e., an "Auto" or "Bulb" value).
        case becameIndeterminate
        /// The value wrapped around to the other end of a list of values.
        case wrappedAround
        /// The value is a "normal" step from the previous value.
        case normalStep
    }

    /// Determine the relationship between two values.
    /// - Parameters:
    ///   - previousValue: The old/previous value.
    ///   - currentValue: The new/current value.
    private func relationship(from previousValue: UniversalExposurePropertyValue,
                              to currentValue: UniversalExposurePropertyValue) -> Relationship {

        guard previousValue.isDeterminate, currentValue.isDeterminate else { return .becameIndeterminate }
        guard !currentValue.isEqual(previousValue) else { return .noChange }
        guard let stopsDifference = currentValue.stopsDifference(from: previousValue) else { return .becameIndeterminate }
        let absoluteDifference = abs(stopsDifference.approximateDecimalValue)
        // Assumption: A single step will never be more than two stops, and a wraparound will never be less.
        return absoluteDifference <= 2.0 ? .normalStep : .wrappedAround
    }
}

// MARK: - Internal Protocols and Helpers

// Allows us to use mocks for testing as well as a camera property.
internal protocol SteppedPropertyValueProvider {
    /// The current exposure value of the property.
    var currentUniversalCommonValue: UniversalExposurePropertyValue? { get }
    /// Step the property in the given direction. Returns when the next value is known.
    func step(in direction: SteppedPropertyDirection) async throws -> UniversalExposurePropertyValue
}

/// The direction in which to step a property value.
internal enum SteppedPropertyDirection {
    case increment
    case decrement

    /// Returns the opposite direction to the receiver.
    var reversed: SteppedPropertyDirection {
        switch self {
        case .increment: return .decrement
        case .decrement: return .increment
        }
    }
}

/// An implementation of `SteppedPropertyValueProvider` for `TypedCameraProperty`.
extension TypedCameraProperty: SteppedPropertyValueProvider where CommonValueType: TypedCommonExposureValue {

    var currentUniversalCommonValue: UniversalExposurePropertyValue? {
        return currentCommonValue
    }

    func step(in direction: SteppedPropertyDirection) async throws -> UniversalExposurePropertyValue {
        guard valueSetType == .stepping else { throw SteppedSearchError.propertyNotSteppable }
        guard let value: UniversalExposurePropertyValue = try await {
            switch direction {
            case .increment: return try await incrementValue(timeout: 2.0)?.commonValue
            case .decrement: return try await decrementValue(timeout: 2.0)?.commonValue
            }
        }() else { throw SteppedSearchError.unexpectedState }
        return value
    }
}
