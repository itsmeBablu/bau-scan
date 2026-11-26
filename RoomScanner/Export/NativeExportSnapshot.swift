import Foundation

/// A coordinated byte-preserving snapshot, independent of native package writers.
enum NativeExportSnapshot {
    static func copy(from source: URL,to destination: URL) throws {
        try Task.checkCancellation()
        try RoomPackage.coordinatedRead(at:source) { folder in
            try SafePackageRead.validate(folder)
            try FileManager.default.copyItem(at:folder,to:destination)
        }
        try SafePackageRead.validate(destination)
    }

    static func files(in root: URL) throws -> [String] {
        try SafePackageRead.validate(root)
        var failure: Error?
        guard let enumerator = FileManager.default.enumerator(at:root,includingPropertiesForKeys:[.isRegularFileKey],errorHandler:{ _,error in failure = error; return false }) else { throw CocoaError(.fileReadUnknown) }
        var result: [String] = []
        for case let file as URL in enumerator {
            try Task.checkCancellation()
            if try file.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile == true {
                let base = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
                let path = file.resolvingSymlinksInPath().standardizedFileURL.pathComponents
                guard path.starts(with:base),path.count > base.count else { throw CocoaError(.fileReadNoPermission) }
                result.append(path.dropFirst(base.count).joined(separator:"/"))
            }
        }
        if let failure { throw failure }
        return result.sorted()
    }
}
