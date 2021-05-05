import CascableCore
import Foundation

public extension Error {

    /// Returns the error expressed as a CascableCore error code, or `.generic` if the error doesn't appear to
    /// be a valid CascableCore error code.
    var asCascableCoreError: CascableCoreErrorCode {
        guard let code = CascableCoreErrorCode(rawValue: UInt(bitPattern: (self as NSError).code)) else { return .generic }
        // This nasty switch filters out the "@unknown default" case, since we can init ObjC-backed enums
        // with arbitrary values.
        switch code {
        case .generic: return .generic
        case .noError: return .noError
        case .notConnected: return .notConnected
        case .deviceBusy: return .deviceBusy
        case .cancelledByUser: return .cancelledByUser
        case .invalidPropertyValue: return .invalidPropertyValue
        case .writeProtected: return .writeProtected
        case .noThumbnail: return .noThumbnail
        case .notAvailable: return .notAvailable
        case .incorrectCommandCategory: return .incorrectCommandCategory
        case .autoFocusFailed: return .autoFocusFailed
        case .genericProtocolFailure: return .genericProtocolFailure
        case .invalidInput: return .invalidInput
        case .cameraNeedsSoftwareUpdate: return .cameraNeedsSoftwareUpdate
        case .timeout: return .timeout
        case .focusDidNotMove: return .focusDidNotMove
        case .unsupportedFileFormat: return .unsupportedFileFormat
        case .noMetadata: return .noMetadata
        case .needsNewPairing: return .needsNewPairing
        @unknown default: return .generic
        }
    }
}
