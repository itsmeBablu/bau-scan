import Foundation

/// Explicit library removal: keep source dependencies and move one item to hidden
/// sibling trash before removing its catalogue reference. No project notes erased.
enum ProjectScanRemoval {
    enum Failure:LocalizedError {
        case designDependsOnSource,changed
        var errorDescription:String? {
            switch self {
            case .designDependsOnSource: AppLanguage.text("A Studio design depends on this scan. Remove the design first; the source scan has been kept.")
            case .changed: AppLanguage.text("The project library changed. Refresh before removing this item.")
            }
        }
    }
    static func remove(_ entry:ProjectLibraryEntry,expected:ProjectIndex,catalogueRoot:URL) throws -> ProjectIndex {
        try expected.validate()
        let reference = entry.reference
        let source:SceneEditDocument.Source
        switch reference.kind {
        case .room,.designRoom: source = .room
        case .house,.designHouse: source = .house
        case .technicalRoom,.designTechnical: source = .technical
        }
        let designURL = SceneEditStore.url(root:entry.root,source:source,id:reference.itemID)
        let location = StorageLocation(kind:reference.library == "icloud" ? .iCloud : .local,documentsURL:entry.root)
        let target = entry.isDesign ? designURL : source == .house ? location.housePackageURL(for:reference.itemID) : source == .room ? location.packageURL(for:reference.itemID) : entry.root.appendingPathComponent("TechnicalRooms/\(reference.itemID.uuidString).technicalroom")
        guard entry.url.standardizedFileURL == target.standardizedFileURL else { throw CocoaError(.fileWriteNoPermission) }
        let root = entry.root.resolvingSymlinksInPath().standardizedFileURL
        let relative = Array(target.standardizedFileURL.pathComponents.dropFirst(entry.root.standardizedFileURL.pathComponents.count))
        guard target.standardizedFileURL.pathComponents.starts(with:entry.root.standardizedFileURL.pathComponents),relative.count == 2 else { throw CocoaError(.fileWriteNoPermission) }
        let parent = root.appendingPathComponent(relative[0]),checked = parent.appendingPathComponent(relative[1])
        for file in [parent,checked] {
            let info = try file.resourceValues(forKeys:[.isSymbolicLinkKey])
            guard info.isSymbolicLink != true,file.resolvingSymlinksInPath().standardizedFileURL == file.standardizedFileURL else { throw CocoaError(.fileWriteNoPermission) }
        }
        let trash = parent.appendingPathComponent(".removed-"+UUID().uuidString+"-"+target.lastPathComponent)
        var moved = false
        do {
            return try ProjectIndexStore.update(root:catalogueRoot) { index in
                guard index == expected,index.projects.contains(where:{ $0.references.contains(reference) }) else { throw Failure.changed }
                if !entry.isDesign {
                    let indexedDesign = index.projects.flatMap(\.references).contains { $0.library == reference.library && $0.itemID == reference.itemID && $0.kind.rawValue.hasPrefix("design") }
                    guard !indexedDesign,!FileManager.default.fileExists(atPath:designURL.path) else { throw Failure.designDependsOnSource }
                }
                try RoomPackage.coordinatedWrite(at:checked,options:.forMoving) { try FileManager.default.moveItem(at:$0,to:trash) }
                moved = true
                for i in index.projects.indices where index.projects[i].references.contains(reference) {
                    index.projects[i].references.removeAll { $0 == reference }; index.projects[i].modifiedAt = Date()
                }
                index.scanOrganization?.removeValue(forKey:reference.id); index.displayNames?.removeValue(forKey:reference.id)
                index.pins?.removeAll { $0.reference == reference }; index.distanceChecks?.removeAll { $0.reference == reference }
            }
        } catch {
            if moved { try FileManager.default.moveItem(at:trash,to:checked) }
            throw error
        }
    }
}
