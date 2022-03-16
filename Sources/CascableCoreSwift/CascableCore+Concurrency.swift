import CascableCore
import Foundation

public extension TypedCameraProperty {

    // MARK: Setting Values

    /// Set the value of the property to the passed value. Only valid when `valueSetType` contains `.enumeration`.
    ///
    /// - Parameters:
    ///   - newValue: The value to set.
    ///   - waitUntilReflectedByCamera: If `true`, the async task will wait for the camera to reflect the passed value
    ///                                 as the current value for the property. If `false`, the task will return when
    ///                                 the message is successfully sent to the camera. Defaults to `true`.
    ///   - timeout: If `waitUntilReflectedByCamera` is `true`, the maximum time to wait for the camera to reflect
    ///              the passed value as the current value for the property. Defaults to `1.0` second.
    ///
    /// - Throws: If an error is encountered while setting the property, or if `waitUntilReflectedByCamera` is
    ///           `true` and the `timeout` interval passes before the value is reflected by the camera, an error is
    ///           thrown with the appropriate error code.
    func setValue(_ newValue: TypedCameraPropertyValue<CommonValueType>, waitUntilReflectedByCamera: Bool = true,
                  timeout: TimeInterval = 1.0) async throws {

        try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<Void, Error>) in
            setValue(newValue, completionQueue: .main, completionHandler: { error in
                if let error = error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            })
        })

        // The `setValue(…)` methods trigger their completion callback when the message has been successfully
        // sent to the camera. However, many cameras will take a moment before that value has been "committed"
        // and reflected in the camera's property values. It can be useful to wait until that happens, so we
        // can optionally wait for the camera to reflect the new value.
        guard waitUntilReflectedByCamera else { return }
        try await waitForValueToChange(to: newValue, timeout: timeout)
    }

    /// Increment the property's value by one step. Only useable if the property's `valueSetType` contains `.stepping`.
    ///
    /// - Note: If you're constructing a UI in a left-to-right locale (such as English) like this, this method should
    /// be called when the user taps on the right arrow: `[<] f/2.8 [>]`, or the down arrow: `[↑] f/2.8 [↓]`. In other
    /// words, this method is moving the value towards the end of a list of values.
    ///
    /// - Parameter timeout: The timeout period for the incremented value becoming available. Defaults to `1.0` second.
    /// - Returns: Returns the new value of the property.
    /// - Throws: If an error is encountered while setting the property, or the `timeout` interval passes before a
    ///           new value is reflected by the camera, an error is thrown with the appropriate error code.
    func incrementValue(timeout: TimeInterval = 1.0) async throws -> TypedCameraPropertyValue<CommonValueType>? {
        let valueBeforeStep = currentValue
        try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<Void, Error>) in
            incrementValue(completionQueue: .main, completionHandler: { error in
                if let error = error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            })
        })

        // The `incrementValue(…)` method triggers the completion callback when the message has been successfully
        // sent to the camera. However, many cameras will take a moment before that value has been "committed"
        // and reflected in the camera's property values. It's useful to wait until that happens, so we wait for the
        // camera to reflect the new value.
        return try await waitForValueToChange(from: valueBeforeStep, timeout: timeout)
    }

    /// Decrement the property's value by one step. Only useable if the property's `valueSetType` contains `.stepping`.
    ///
    /// - Note: If you're constructing a UI in a left-to-right locale (such as English) like this, this method should
    /// be called when the user taps on the left arrow: `[<] f/2.8 [>]`, or the up arrow: `[↑] f/2.8 [↓]`. In other
    /// words, this method is moving the value towards the beginning of a list of values.
    ///
    /// - Parameter timeout: The timeout period for the decremented value becoming available. Defaults to `1.0` second.
    /// - Returns: Returns the new value of the property.
    /// - Throws: If an error is encountered while setting the property, or the `timeout` interval passes before a
    ///           new value is reflected by the camera, an error is thrown with the appropriate error code.
    func decrementValue(timeout: TimeInterval = 1.0) async throws -> TypedCameraPropertyValue<CommonValueType>? {
        let valueBeforeStep = currentValue
        try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<Void, Error>) in
            decrementValue(completionQueue: .main, completionHandler: { error in
                if let error = error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            })
        })

        // The `decrementValue(…)` method triggers the completion callback when the message has been successfully
        // sent to the camera. However, many cameras will take a moment before that value has been "committed"
        // and reflected in the camera's property values. It's useful to wait until that happens, so we wait for the
        // camera to reflect the new value.
        return try await waitForValueToChange(from: valueBeforeStep, timeout: timeout)
    }

    // MARK: - Observing Values

    /// Wait for the property's `currentValue` to become the given value before returning. Returns immediately if the
    /// property's value is already equal to `expectedValue`.
    ///
    /// - Parameters:
    ///   - expectedValue: The value to wait for.
    ///   - timeout: The maximum time for to wait before erroring out. Defaults to `10.0` seconds.
    ///
    /// - Throws: If the `timeout` interval passes before the new value is reflected by the camera, an error is
    ///           thrown with the appropriate error code (`.timeout`).
    func waitForValueToChange(to expectedValue: TypedCameraPropertyValue<CommonValueType>?,
                              timeout: TimeInterval = 10.0) async throws {

        if currentValue == expectedValue { return }

        try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<Void, Error>) in
            var observation: CameraPropertyObservation? = nil
            var didTimeout: Bool = false

            // It's possible that the camera will never reflect the set value — either because something else
            // set the value to something else really quickly, or the requested value gets adjusted on-the-fly
            // by the camera to fit with some other setting or environmental condition. So, we need a timeout.
            let timeoutTimer = Timer(timeInterval: max(0.25, timeout), repeats: false, block: { [weak self] timer in
                timer.invalidate()
                didTimeout = true
                if let observation = observation { self?.removeObserver(observation) }
                continuation.resume(throwing: NSError(cblErrorCode: .timeout))
            })

            RunLoop.main.add(timeoutTimer, forMode: .common)

            // With a timeout in place, we can add an observer to the property's value and wait until it
            // changes to the value we set.
            observation = addObserver({ sender, changeType in
                guard !didTimeout else { return }
                guard changeType.contains(.value) else { return }
                if sender.currentValue == expectedValue {
                    timeoutTimer.invalidate()
                    if let observation = observation { sender.removeObserver(observation) }
                    continuation.resume(returning: ())
                }
            })
        })
    }

    /// Wait for the property's `currentValue` to change.
    ///
    /// - Parameter timeout: The maximum time for to wait before erroring out. Defaults to `10.0` seconds.
    /// - Returns: Returns the property's new value once it switches away from the current value within the timeout period.
    /// - Throws: If the `timeout` interval passes before a different value is reflected by the camera, an error is
    ///           thrown with the appropriate error code (`.timeout`).
    func waitForValueToChangeFromCurrent(timeout: TimeInterval = 10.0) async throws -> TypedCameraPropertyValue<CommonValueType>? {
        return try await waitForValueToChange(from: currentValue, timeout: timeout)
    }

    /// Wait for the property's `currentValue` to _not_ be the given value before returning. Returns immediately if the
    /// property's value is already not equal to `unwantedValue`.
    ///
    /// - Parameters:
    ///   - unwantedValue: The value the property shouldn't be.
    ///   - timeout: The maximum time for to wait before erroring out. Defaults to `10.0` seconds.
    ///
    /// - Returns: Returns the property's new value once it switches away from the given value within the timeout period.
    /// - Throws: If the `timeout` interval passes before a different value is reflected by the camera, an error is
    ///           thrown with the appropriate error code (`.timeout`).
    func waitForValueToChange(from unwantedValue: TypedCameraPropertyValue<CommonValueType>?,
                              timeout: TimeInterval = 10.0) async throws -> TypedCameraPropertyValue<CommonValueType>? {

        if currentValue != unwantedValue { return currentValue }

        return try await withCheckedThrowingContinuation({ continuation in
            var observation: CameraPropertyObservation? = nil
            var didTimeout: Bool = false

            // It's possible that the camera will never reflect a new value (maybe we're at the end of a list?).
            // So, we need a timeout.
            let timeoutTimer = Timer(timeInterval: max(0.25, timeout), repeats: false, block: { [weak self] timer in
                timer.invalidate()
                didTimeout = true
                if let observation = observation { self?.removeObserver(observation) }
                continuation.resume(throwing: NSError(cblErrorCode: .timeout))
            })

            RunLoop.main.add(timeoutTimer, forMode: .common)

            // With a timeout in place, we can add an observer to the property's value and wait until it
            // changes to the value we set.
            observation = addObserver({ sender, changeType in
                guard !didTimeout else { return }
                guard changeType.contains(.value) else { return }
                if sender.currentValue != unwantedValue {
                    timeoutTimer.invalidate()
                    if let observation = observation { sender.removeObserver(observation) }
                    continuation.resume(returning: sender.currentValue)
                }
            })
        })
    }
}

