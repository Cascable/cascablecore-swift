import CascableCore
import Foundation

public extension CameraCore {

    /// Returns the type of camera the receiver represents.
    var cameraType: CameraType {
        return cameraFamily.type
    }
}

public extension CameraFamily {

    /// Returns the corresponding camera type of the receiver.
    var type: CameraType {
        return CameraType(rawValue: self)
    }
}
