import Foundation

/// Local project catalogue, separate from all existing package formats.
enum ProjectIndexStore {
    static func url(root: URL) -> URL { root.appendingPathComponent("Projects", isDirectory: true).appendingPathComponent("index-v1.json") }
    static func read(root: URL) throws -> ProjectIndex {
        let file = url(root: root)
        guard FileManager.default.fileExists(atPath: file.path) else { return .init() }
        return try RoomPackage.coordinatedRead(at: file) { url in
            let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard info.isRegularFile == true, info.isSymbolicLink != true, (info.fileSize ?? Int.max) < 16_777_216 else { throw CocoaError(.fileReadCorruptFile) }
            let index = try JSONDecoder().decode(ProjectIndex.self, from: Data(contentsOf: url))
            try index.validate(); return index
        }
    }
    static func write(_ index: ProjectIndex, root: URL) throws {
        try index.validate()
        let file = url(root: root)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(index)
        guard data.count < 16_777_216 else { throw CocoaError(.fileWriteOutOfSpace) }
        try RoomPackage.coordinatedWrite(at: file, options: .forReplacing) { target in
            guard (try? target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw CocoaError(.fileWriteNoPermission) }
            try data.write(to: target, options: .atomic)
        }
    }
}
