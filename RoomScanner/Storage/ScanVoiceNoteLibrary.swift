import Foundation

enum ScanVoiceNoteLibrary {
    static var root:URL { UserDefaults.standard.string(forKey:"RoomScannerStorageRoot").map { URL(fileURLWithPath:$0) } ?? StorageLocation.local().documentsURL }
    static func notes(for reference:ProjectReference,root:URL = root) throws -> [ARNote] {
        let index = try ProjectIndexStore.read(root:root)
        return try index.projects.filter { $0.references.contains(reference) }.flatMap {
            try ARNoteStore.index(root:root,projectID:$0.id).notes.filter { $0.reference == reference }
        }
    }
}
