import CascableCore
import Foundation

public extension CameraCore {

    /// Returns the type of camera the receiver represents.
    var cameraType: CameraType {
        return CameraType(rawValue: cameraFamily)
    }
}
