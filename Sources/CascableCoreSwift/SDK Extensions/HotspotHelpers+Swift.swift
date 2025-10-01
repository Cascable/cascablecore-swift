import Foundation
import CascableCore

public extension HotspotHelpers {

    /// Attempt to join the given WiFi network.
    ///
    /// - Note: Joining a WiFi network can take upwards of 20-30 seconds.
    ///
    /// - Parameters:
    ///   - ssid: The SSID of the network to join.
    ///   - password: The password of the network to join.
    ///   - promptForLocation: If the current platform requires location permission to connect to a network, pass `true`
    ///                        to automatically prompt for that permission if needed.
    ///   - completionHandler: The completion handler to be called with the result of the operation.
    ///   - completionQueue: The queue on which to call the completion handler.
    func attemptToJoinWiFiNetwork(_ ssid: String, password: String,
                                  promptingForLocationIfNeeded promptForLocation: Bool = true,
                                  completionHandler: @escaping (Result<HotspotConfiguration, Error>) -> Void,
                                  completionQueue: DispatchQueue) {

        attemptToJoinWiFiNetwork(ssid, password: password, promptingForLocationIfNeeded: promptForLocation,
                                 completionHandler: { config, error in
            if let config {
                completionHandler(.success(config))
            } else if let error {
                completionHandler(.failure(error))
            } else {
                completionHandler(.failure(NSError(cblErrorCode: .networkChangeFailed)))
            }
        }, completionQueue: completionQueue)
    }

    /// Attempt to join the given WiFi network.
    ///
    /// - Note: Joining a WiFi network can take upwards of 20-30 seconds.
    ///
    /// - Parameters:
    ///   - ssid: The SSID of the network to join.
    ///   - password: The password of the network to join.
    ///   - promptForLocation: If the current platform requires location permission to connect to a network, pass `true`
    ///                        to automatically prompt for that permission if needed.
    /// - Returns: Upon successful connection, returns a `HotspotConfiguration` object describing the network.
    func attemptToJoinWiFiNetwork(_ ssid: String, password: String,
                                  promptingForLocationIfNeeded promptForLocation: Bool = true) async throws -> HotspotConfiguration {

        return try await withCheckedThrowingContinuation({ continuation in
            attemptToJoinWiFiNetwork(ssid, password: password, promptingForLocationIfNeeded: promptForLocation,
                                     completionHandler: { result in
                continuation.resume(with: result)
            }, completionQueue: .main)
        })
    }

    /// Attempt to join the WiFi network described by the given QR code scanning result.  See `CameraQRDecoding` for details.
    ///
    /// - Note: Joining a WiFi network can take upwards of 20-30 seconds.
    ///
    /// - Parameters:
    ///   - networkDetails The details of the network to join.
    ///   - promptForLocation: If the current platform requires location permission to connect to a network, pass `true`
    ///                        to automatically prompt for that permission if needed.
    ///   - completionHandler: The completion handler to be called with the result of the operation.
    ///   - completionQueue: The queue on which to call the completion handler.
    func attemptToJoinQRCodeNetwork(_ networkDetails: CameraWiFiDetails,
                                    promptingForLocationIfNeeded promptForLocation: Bool = true,
                                    completionHandler: @escaping (Result<HotspotConfiguration, Error>) -> Void,
                                    completionQueue: DispatchQueue) {

        attemptToJoinQRCodeNetwork(networkDetails, promptingForLocationIfNeeded: promptForLocation,
                                   completionHandler: { config, error in
            if let config {
                completionHandler(.success(config))
            } else if let error {
                completionHandler(.failure(error))
            } else {
                completionHandler(.failure(NSError(cblErrorCode: .networkChangeFailed)))
            }
        }, completionQueue: completionQueue)
    }

    /// Attempt to join the WiFi network described by the given QR code scanning result.  See `CameraQRDecoding` for details.
    ///
    /// - Note: Joining a WiFi network can take upwards of 20-30 seconds.
    ///
    /// - Parameters:
    ///   - networkDetails The details of the network to join.
    ///   - promptForLocation: If the current platform requires location permission to connect to a network, pass `true`
    ///                        to automatically prompt for that permission if needed.
    /// - Returns: Upon successful connection, returns a `HotspotConfiguration` object describing the network.
    func attemptToJoinQRCodeNetwork(_ networkDetails: CameraWiFiDetails,
                                    promptingForLocationIfNeeded promptForLocation: Bool = true) async throws -> HotspotConfiguration {

        return try await withCheckedThrowingContinuation({ continuation in
            attemptToJoinQRCodeNetwork(networkDetails, promptingForLocationIfNeeded: promptForLocation,
                                       completionHandler: { result in
                continuation.resume(with: result)
            }, completionQueue: .main)
        })
    }
}
