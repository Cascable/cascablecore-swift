import CascableCore
import Foundation

/// Errors that can occur during license key activation.
public enum LicenseKeyVerificationError: Error {

    /// The license key failed to be verified (usually due to a connectivity issue), and a valid offline token was not
    /// provided. The SDK will not function.
    case failedWithoutValidOfflineToken

    /// The license key is not valid in the current environment (for example, a trial license was attempted to be used
    /// in the App Store). The SDK will not function.
    case notAllowedInCurrentEnvironment

    /// The license is not valid for this process (wrong bundle ID, platform, etc). The SDK will not function.
    case invalidLicense

    public var localizedDescription: String {
        switch self {
        case .failedWithoutValidOfflineToken:
            return "The license key failed to be verified (usually due to a connectivity issue), and a valid offline token was not provided."
        case .notAllowedInCurrentEnvironment:
            return "The license key is not valid in the current environment (i.e., a testing-only key was used in production)."
        case .invalidLicense: 
            return "The license key is not valid for the current process."
        }
    }
}

public extension CascableCoreLicenseVerification {
    
    /// Applies the given license key. This should be done before calling any other CascableCore APIs, otherwise
    /// an "unlicensed" dialog may be shown to the user.
    ///
    /// The CascableCore license key verification process involves connecting to the Cascable licensing service to
    /// verify the license key and retrieve an offline activation token. Once verified, that token is returned via
    /// the completion callback for the caller to store and supply in subsequent calls to this method. Activation
    /// tokens are small (less than a kilobyte) and appropriate for storing in the Keychain, User Defaults, etc.
    ///
    /// **NOTE:** Offline activation tokens are per end-user device, and shouldn't be synced around.
    ///
    /// If you provide a valid offline activation token alongside your license key, CascableCore will not need to connect
    /// to the licensing service again so long as the token isn't expired. By default, CascableCore won't contact the
    /// service to get a new token unless the given one has less than seven days of validity remaining.
    ///
    /// You can customise this behaviour with the `refreshMode` parameter. It's also safe to call this method more than
    /// once in your app's lifecycle, so if you're aware that your app may be entering an extended period with no internet
    /// access, you can call this with the `.always` refresh mode to get a new token for the longest offline validity period.
    ///
    /// If the connection to the licensing service fails for whatever reason, the overall operation will succeed as long
    /// as a valid offline activation token is present, no matter the value of `refreshMode`. In practice, this means
    /// that the only time an internet connection is **required** is if you have no token at all (i.e., an end-user
    /// installation's first launch) or if your previously granted token has expired.
    ///
    /// - Parameters:
    ///   - licenseKey: Your CascableCore license key.
    ///   - offlineToken: A previously-issued offline activation token, if you have one.
    ///   - refreshMode: The token refresh mode. Defaults to `.automatic`.
    ///
    /// - Throws: Throws a `LicenseKeyVerificationError` error if activation fails.
    /// - Returns: Returns an offline activation token upon successful activation.
    @MainActor static func apply(_ licenseKey: String, offlineToken: Data?,
                                 refreshMode: LicenseKeyOfflineTokenRefreshMode = .automatic) async throws -> LicenseKeyOfflineToken {
        let result: Result<LicenseKeyOfflineToken, LicenseKeyVerificationError> = await withCheckedContinuation({ continuation in
            apply(licenseKey: licenseKey, offlineToken: offlineToken, refreshMode: refreshMode) { result, token in
                switch result {
                case .activated:
                    // CascableCore's API is guaranteed to return a non-nil token alongside an `.activated` result.
                    if let token { continuation.resume(returning: .success(token)) }
                    else { continuation.resume(returning: .failure(.failedWithoutValidOfflineToken)) }
                case .failedWithoutValidOfflineToken:
                    continuation.resume(returning: .failure(.failedWithoutValidOfflineToken))
                case .notAllowedInCurrentEnvironment:
                    continuation.resume(returning: .failure(.notAllowedInCurrentEnvironment))
                case .invalidLicense:
                    continuation.resume(returning: .failure(.invalidLicense))
                @unknown default:
                    print("WARNING: Got an unknow-at-compile-time value for license key activation. Please update CascableCoreSwift.")
                    continuation.resume(returning: .failure(.invalidLicense))
                }
            }
        })

        switch result {
        case .success(let token): return token
        case .failure(let error): throw error
        }
    }
}
