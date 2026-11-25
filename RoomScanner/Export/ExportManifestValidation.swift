import Foundation
import CoreFoundation

enum ExportManifestValidation {
    static func validate(in root: URL) throws {
        let file = root.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath:file.path) else { return }
        let object = try JSONSerialization.jsonObject(with:SafePackageRead.data(file,root:root,maximum:16*1_048_576))
        // Other native/project manifests have different contracts; validate file inventories when present.
        guard let manifest = object as? [String:Any] else { throw CocoaError(.fileReadCorruptFile) }
        guard let rawItems = manifest["items"] else { return }
        guard let items = rawItems as? [[String:Any]] else { throw CocoaError(.fileReadCorruptFile) }
        guard items.count <= 10_000 else { throw CocoaError(.fileReadTooLarge) }
        var used = Set<String>()
        for item in items {
            try Task.checkCancellation()
            guard let path = item["path"] as? String,!path.isEmpty,!path.hasPrefix("/"),!path.contains("\\"),!path.contains(":"),
                  path.split(separator:"/",omittingEmptySubsequences:false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  used.insert(path.precomposedStringWithCanonicalMapping.lowercased()).inserted,
                  let bytes = item["bytes"] as? NSNumber,CFGetTypeID(bytes) != CFBooleanGetTypeID(),
                  bytes.doubleValue.isFinite,bytes.doubleValue >= 0,bytes.doubleValue <= 1_073_741_824,
                  bytes.doubleValue.rounded(.towardZero) == bytes.doubleValue else { throw CocoaError(.fileReadCorruptFile) }
            let target = root.appendingPathComponent(path)
            // The root was preflighted above. Stream hashes instead of loading each large asset.
            let info = try target.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
            guard info.isRegularFile == true,info.isSymbolicLink != true,let size = info.fileSize,
                  Int64(size) == bytes.int64Value else { throw CocoaError(.fileReadCorruptFile) }
            if let raw = item["sha256"] {
                guard let expected = raw as? String,expected.count == 64,expected.allSatisfy(\.isHexDigit) else { throw CocoaError(.fileReadCorruptFile) }
                guard expected == (try ExportChecksum.sha256(target)) else { throw CocoaError(.fileReadCorruptFile) }
            }
        }
    }
}
