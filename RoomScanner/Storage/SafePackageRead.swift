import Foundation

enum SafePackageRead {
    static func validate(_ root: URL,entries maximumEntries: Int = 10_000,total maximumBytes: Int = 1_073_741_824) throws {
        let fm = FileManager.default
        let info = try root.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
        guard info.isDirectory == true,info.isSymbolicLink != true else { throw CocoaError(.fileReadCorruptFile) }
        var failure: Error?
        guard let items = fm.enumerator(at:root,includingPropertiesForKeys:[.isSymbolicLinkKey,.isRegularFileKey,.isDirectoryKey,.fileSizeKey],errorHandler:{ _,error in failure = error; return false }) else { throw CocoaError(.fileReadUnknown) }
        var count = 0,total = 0
        for case let file as URL in items {
            count += 1; guard count <= maximumEntries else { throw CocoaError(.fileReadTooLarge) }
            let attrs = try file.resourceValues(forKeys:[.isSymbolicLinkKey,.isRegularFileKey,.isDirectoryKey,.fileSizeKey])
            guard attrs.isSymbolicLink != true,attrs.isDirectory == true || attrs.isRegularFile == true else { throw CocoaError(.fileReadCorruptFile) }
            let size = attrs.isRegularFile == true ? attrs.fileSize ?? Int.max : 0
            guard size >= 0,size <= maximumBytes-total else { throw CocoaError(.fileReadTooLarge) }
            total += size
        }
        if let failure { throw failure }
    }
    static func data(_ file: URL,root: URL,maximum: Int = 256*1_048_576,preflight: Bool = true) throws -> Data {
        if preflight { try validate(root) }
        let base = root.standardizedFileURL,original = file.standardizedFileURL
        guard original.path.hasPrefix(base.path+"/") else { throw CocoaError(.fileReadNoPermission) }
        let relative = String(original.path.dropFirst(base.path.count+1))
        let canonical = base.resolvingSymlinksInPath().appendingPathComponent(relative)
        guard canonical.resolvingSymlinksInPath() == canonical else { throw CocoaError(.fileReadNoPermission) }
        let attrs = try canonical.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        let limit = file.lastPathComponent == "meta.json" ? min(maximum,1_048_576) : maximum
        guard attrs.isRegularFile == true,attrs.isSymbolicLink != true,let size = attrs.fileSize,size >= 0,size <= limit else { throw CocoaError(.fileReadTooLarge) }
        let data = try Data(contentsOf:canonical,options:.mappedIfSafe)
        guard data.count <= limit else { throw CocoaError(.fileReadTooLarge) }
        return data
    }
}
