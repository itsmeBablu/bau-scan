import Foundation

/// One read adapter for saved 2D/3D evidence. Photo metadata stays lazy; a corrupt
/// note library does not hide valid photos and a bad photo index does not hide notes.
/// Cancellation is never converted to an availability warning.
enum SavedScanEvidence {
    struct Snapshot {
        var notes: [ARNote] = []
        var photos: [ProjectPhotoAsset] = []
        var noteFailure: String?
        var photoFailure: String?
    }
    static func load(packageURL:URL,house:House,notesRoot:URL) throws -> Snapshot {
        try Task.checkCancellation()
        var result = Snapshot()
        do { result.notes = try ScanVoiceNoteLibrary.registeredNotes(packageURL:packageURL,house:house,catalogueRoot:notesRoot) }
        catch is CancellationError { throw CancellationError() }
        catch { result.noteFailure = error.localizedDescription }
        try Task.checkCancellation()
        do {
            guard let id = UUID(uuidString:packageURL.deletingPathExtension().lastPathComponent) else { throw CocoaError(.fileReadCorruptFile) }
            let reference = ScanVoiceNoteLibrary.reference(itemID:id,kind:packageURL.pathExtension == "housescan" ? .house : .room,
                                                          storageRoot:packageURL.deletingLastPathComponent().deletingLastPathComponent(),catalogueRoot:notesRoot)
            result.photos = try ProjectPhotoAsset.list(from:packageURL,house:house,reference:reference)
        } catch is CancellationError { throw CancellationError() }
        catch { result.photoFailure = error.localizedDescription }
        try Task.checkCancellation()
        return result
    }
}
