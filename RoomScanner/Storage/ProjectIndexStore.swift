import Foundation

/// Local project catalogue, separate from all existing package formats.
enum ProjectIndexStore {
    enum NotesConflict: LocalizedError {
        case stale
        var errorDescription: String? { AppLanguage.text("Project notes changed elsewhere. Your draft was not saved. Reload the latest notes before retrying.") }
    }
    static func updateNotes(_ text:String,projectID:UUID,expected:String,root:URL) throws -> ProjectIndex {
        try update(root:root) { index in
            guard let i = index.projects.firstIndex(where:{ $0.id == projectID }) else { throw CocoaError(.fileNoSuchFile) }
            guard index.projects[i].notes == expected || index.projects[i].notes == text else { throw NotesConflict.stale }
            index.projects[i].notes = text; index.projects[i].modifiedAt = Date()
        }
    }
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
    /// Read/modify/write under one coordinated lock, so independent windows do not
    /// overwrite newer notes or resurrect a project deleted from Settings.
    static func update(root: URL, _ edit: (inout ProjectIndex) throws -> Void) throws -> ProjectIndex {
        let file = url(root:root)
        try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
        var result = ProjectIndex()
        try RoomPackage.coordinatedWrite(at:file,options:.forMerging) { target in
            var next = ProjectIndex()
            if FileManager.default.fileExists(atPath:target.path) {
                let info = try target.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
                guard info.isRegularFile == true,info.isSymbolicLink != true,(info.fileSize ?? Int.max) < 16_777_216 else { throw CocoaError(.fileReadCorruptFile) }
                next = try JSONDecoder().decode(ProjectIndex.self,from:Data(contentsOf:target)); try next.validate()
            }
            try edit(&next); try next.validate()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
            let data = try encoder.encode(next)
            guard data.count < 16_777_216 else { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to:target,options:.atomic); result = next
        }
        return result
    }
}
