import Foundation

enum ExportManifestValidation {
    static func validate(in root: URL) throws {
        let file = root.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath:file.path) else { return }
        let object = try JSONSerialization.jsonObject(with:SafePackageRead.data(file,root:root,maximum:16*1_048_576))
        // Other native/project manifests have different contracts; validate file inventories when present.
        guard let manifest = object as? [String:Any],let items = manifest["items"] as? [[String:Any]] else { return }
        guard items.count <= 10_000 else { throw CocoaError(.fileReadTooLarge) }
        var used = Set<String>()
        for item in items {
            try Task.checkCancellation()
            guard let path = item["path"] as? String,!path.isEmpty,!path.hasPrefix("/"),!path.contains("\\"),!path.contains(":"),
                  !path.split(separator:"/").contains(where:{ $0 == "." || $0 == ".." }),used.insert(path.lowercased()).inserted,
                  let bytes = item["bytes"] as? NSNumber,bytes.int64Value >= 0 else { throw CocoaError(.fileReadCorruptFile) }
            let target = root.appendingPathComponent(path)
            let data = try SafePackageRead.data(target,root:root,preflight:false)
            guard Int64(data.count) == bytes.int64Value else { throw CocoaError(.fileReadCorruptFile) }
            if let expected = item["sha256"] as? String {
                guard expected == (try ExportChecksum.sha256(target)) else { throw CocoaError(.fileReadCorruptFile) }
            }
        }
    }
}
