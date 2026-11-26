import Foundation

enum ScanVoiceNoteLibrary {
    static var root:URL { UserDefaults.standard.string(forKey:"RoomScannerStorageRoot").map { URL(fileURLWithPath:$0) } ?? StorageLocation.local().documentsURL }
    static func notes(for reference:ProjectReference,root:URL = root) throws -> [ARNote] {
        let index = try ProjectIndexStore.read(root:root)
        var owners = index.projects.filter { $0.references.contains(reference) }.map(\.id)
        // Older direct-capture screens saved evidence in Unsorted before a
        // project catalogue existed. Keep those spatial notes discoverable.
        if !owners.contains(ProjectIndex.unsortedID) { owners.append(ProjectIndex.unsortedID) }
        var seen = Set<UUID>()
        return try owners.flatMap { owner in
            try ARNoteStore.index(root:root,projectID:owner).notes.filter { $0.reference == reference && seen.insert($0.id).inserted }
        }
    }
    static func reference(itemID:UUID,kind:ProjectReference.Kind,storageRoot:URL,catalogueRoot:URL = root) -> ProjectReference {
        let local = storageRoot.resolvingSymlinksInPath().standardizedFileURL.path == catalogueRoot.resolvingSymlinksInPath().standardizedFileURL.path
        return .init(kind:kind,itemID:itemID,library:local ? "local" : "icloud")
    }
    static func registeredNotes(packageURL:URL,house:House,catalogueRoot:URL = root) throws -> [ARNote] {
        guard let id = UUID(uuidString:packageURL.deletingPathExtension().lastPathComponent) else { throw CocoaError(.fileReadCorruptFile) }
        let kind:ProjectReference.Kind = packageURL.pathExtension == FileLayout.housePackageExtension ? .house : .room
        let ref = reference(itemID:id,kind:kind,storageRoot:packageURL.deletingLastPathComponent().deletingLastPathComponent(),catalogueRoot:catalogueRoot)
        let values = try notes(for:ref,root:catalogueRoot)
        guard !values.isEmpty else { return [] }
        let scans:[ScanInput] = kind == .house ? try HousePackage.readStructure(from:packageURL)?.rooms ?? [] : try RoomPackage.readScan(from:packageURL).map { [$0] } ?? []
        return ScanNoteRegistration.registered(values,house:house,scans:scans,singleRoom:kind == .room)
    }
}
