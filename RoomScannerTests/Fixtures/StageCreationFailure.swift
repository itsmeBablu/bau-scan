import Foundation

/// Explicit fault injection, not a genuinely full filesystem.
final class StageCreationOutOfSpaceFileManager: FileManager, @unchecked Sendable {
    override func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool,
                                  attributes: [FileAttributeKey: Any]? = nil) throws {
        if url.lastPathComponent.hasPrefix(".package-writing-") || url.lastPathComponent.hasPrefix(".technical-writing-") {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        try super.createDirectory(at:url,withIntermediateDirectories:createIntermediates,attributes:attributes)
    }
}

/// Byte-for-byte transaction fixture snapshot; no runtime/app use.
enum PackageTestSnapshot {
    static func files(_ root:URL) throws -> [String:Data] {
        let fm = FileManager.default
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        var failure: Error?
        guard let enumerator = fm.enumerator(at:base,includingPropertiesForKeys:[.isRegularFileKey],errorHandler:{ _,error in
            failure = error; return false
        }) else { throw CocoaError(.fileReadUnknown) }
        var result:[String:Data] = [:]
        for case let file as URL in enumerator {
            if try file.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile == true {
                result[String(file.path.dropFirst(base.path.count+1))] = try Data(contentsOf:file)
            }
        }
        if let failure { throw failure }
        return result
    }
}
