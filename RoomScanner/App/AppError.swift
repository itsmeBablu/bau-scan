import Foundation

/// Domain errors presented to the user. Each case has an identified cause
/// and localized message; no errors are silenced.
enum AppError: LocalizedError, Equatable {
    case unsupportedDevice
    case cameraDenied
    case scanFailed(String)
    case scanCancelled
    case exportFailed(format: String, reason: String)
    case storageFailed(String)
    case cloudUnavailable
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedDevice: String(localized: "error.unsupportedDevice", bundle: .main, locale: AppLanguage.locale)
        case .cameraDenied: String(localized: "error.cameraDenied", bundle: .main, locale: AppLanguage.locale)
        case .scanFailed(let why): String(localized: "error.scanFailed \(why)", bundle: .main, locale: AppLanguage.locale)
        case .scanCancelled: String(localized: "error.scanCancelled", bundle: .main, locale: AppLanguage.locale)
        case .exportFailed(let f, let why): String(localized: "error.exportFailed \(f) \(why)", bundle: .main, locale: AppLanguage.locale)
        case .storageFailed(let why): String(localized: "error.storageFailed \(why)", bundle: .main, locale: AppLanguage.locale)
        case .cloudUnavailable: String(localized: "error.cloudUnavailable", bundle: .main, locale: AppLanguage.locale)
        case .downloadFailed(let why): String(localized: "error.downloadFailed \(why)", bundle: .main, locale: AppLanguage.locale)
        }
    }
}
