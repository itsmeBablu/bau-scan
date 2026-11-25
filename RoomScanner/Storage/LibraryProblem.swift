import Foundation

struct LibraryProblem: Identifiable, Equatable {
    enum Reason: String {
        case notDownloaded, corrupt, unsupportedSchema, ioError
        var title: String {
            switch self {
            case .notDownloaded: AppLanguage.text("library.problem.notDownloaded")
            case .corrupt: AppLanguage.text("library.problem.corrupt")
            case .unsupportedSchema: AppLanguage.text("library.problem.unsupportedSchema")
            case .ioError: AppLanguage.text("library.problem.ioError")
            }
        }
    }
    var url: URL
    var reason: Reason
    var detail: String
    var id: URL { url }
    static func classify(_ error: Error,downloaded: Bool = true) -> Reason {
        if !downloaded { return .notDownloaded }
        if error is DecodingError { return .corrupt }
        return .ioError
    }
}
