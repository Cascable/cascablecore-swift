import Foundation
import CascableCore

// MARK: - Public API

extension CameraType {

    /// Generic cameras are typically USB-connected cameras we can't fully remote control.
    public static let generic = CameraType(rawValue: CameraFamilyGeneric)

    /// Canon EOS, EOS M, EOS R, and some PowerShot cameras.
    public static let canon = CameraType(rawValue: CameraFamilyCanon)

    /// Fujifilm X-series cameras.
    public static let fuji = CameraType(rawValue: CameraFamilyFuji)

    /// Nikon D series SLRs and Z series mirrorless cameras.
    public static let nikon = CameraType(rawValue: CameraFamilyNikon)

    /// Olympus OM-D, PEN, and TG series cameras.
    public static let olympus = CameraType(rawValue: CameraFamilyOlympus)

    /// Panasonic LUMIX cameras.
    public static let panasonic = CameraType(rawValue: CameraFamilyPanasonic)

    /// Sony Alpha and RX cameras.
    public static let sony = CameraType(rawValue: CameraFamilySony)
}

/// A network interface, such as "en0".
public struct NetworkInterface: ExpressibleByStringLiteral, Equatable {
    public let interfaceName: String
}

/// An IPv4 address, such as "192.168.0.1".
public struct IPv4Address: ExpressibleByStringLiteral, Equatable {
    public let stringValue: String
}

/// A description (usually user-supplied) of a camera somewhere on the network. Needs a camera type
/// (Canon, Nikon, etc) and a location on the network.
public struct Descriptor: Equatable {

    /// Where on the network should we look?
    public enum NetworkLocation: Equatable {

        /// The "suggested" network interface's gateway. CascableCore will derive the most likely network interface
        /// automatically (usually the WiFi network interface).
        case atSuggestedGateway

        /// The given network interface's gateway.
        case atGatewayOfInterface(NetworkInterface)

        /// A specific IP address.
        case atIPAddress(IPv4Address)
    }

    /// The descriptor's network location.
    public let location: NetworkLocation

    /// The descriptor's camera type.
    public let cameraType: CameraType

    /// A descriptor for a camera of the given type at the "suggested" network interface's gateway. Usually used
    /// for cameras that create their own WiFi network. CascableCore will derive the most likely network interface
    /// automatically (usually the WiFi network interface).
    public static func cameraAtSuggestedGateway(_ type: CameraType) -> Descriptor {
        return Descriptor(location: .atSuggestedGateway, cameraType: type)
    }

    /// A descriptor for a camera of the given type at the given network interface's gateway. Usually used for
    /// cameras that create their own WiFi network.
    public static func cameraType(_ type: CameraType, atGatewayOfInterface interface: NetworkInterface) -> Descriptor {
        return Descriptor(location: .atGatewayOfInterface(interface), cameraType: type)
    }

    /// A descriptor for a camera of the given type at the given IPv4 address.
    public static func cameraType(_ type: CameraType, at ipAddress: IPv4Address) -> Descriptor {
        return Descriptor(location: .atIPAddress(ipAddress), cameraType: type)
    }
}

public extension CameraManualDiscovery {

    /// Attempt to discover a camera with the given descriptor. 
    ///
    /// - Parameters:
    ///   - descriptor: The descriptor for the camera to discover.
    ///   - callbackQueue: The queue on which the completion handler should be called.
    ///   - completionHandler: The completion handler to call when the operation succeeds or fails.
    func discover(_ descriptor: Descriptor, callbackQueue: DispatchQueue = .main, completionHandler: @escaping (Result<Camera, Error>) -> Void) {
        attemptToDiscoverCamera(at: descriptor.cascableCoreDescriptor(), completionQueue: callbackQueue) { camera, error in
            if let camera = camera {
                completionHandler(.success(camera))
            } else if let error = error {
                completionHandler(.failure(error))
            } else {
                completionHandler(.failure(NSError(cblErrorCode: .genericProtocolFailure)))
            }
        }
    }
}

public extension CameraDiscovery {

    /// A nicer accessor for `CBLWiFiConnectivityDidChangeNotificationName`. Doesn't need an active discovery session to fire.
    static var wifiConnectivityDidChangeNotification: NSNotification.Name = {
        NSNotification.Name(rawValue: CBLWiFiConnectivityDidChangeNotificationName)
    }()

    /// A nicer to use accessor to the shared camera discovery object.
    static var shared: CameraDiscovery {
        return sharedInstance()
    }
}

// MARK: - Internal API

public struct CameraType: RawRepresentable, Equatable {
    public let rawValue: CameraFamily
    public init(rawValue: CameraFamily) {
        self.rawValue = rawValue
    }
}

public extension IPv4Address {
    init(stringLiteral value: StringLiteralType) {
        stringValue = value
    }
}

public extension NetworkInterface {
    init(stringLiteral value: StringLiteralType) {
        interfaceName = value
    }
}

fileprivate extension Descriptor {
    func cascableCoreDescriptor() -> CameraDescriptor {
        switch location {
        case .atSuggestedGateway:
            return CameraDescriptor.descriptor(atSuggestedGatewayFor: cameraType.rawValue)
        case .atGatewayOfInterface(let interface):
            return CameraDescriptor.descriptor(for: cameraType.rawValue, atGatewayOf: interface.interfaceName)
        case .atIPAddress( let ipAddress):
            return CameraDescriptor.descriptor(for: cameraType.rawValue, at: ipAddress.stringValue)
        }
    }
}
