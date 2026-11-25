import Foundation

enum ProjectPrivacyStore {
    /// Preflight every path before deleting anything. Unknown/offline libraries abort the operation.
    static func deletionTargets(index: ProjectIndex, roots: [String:URL], catalogueRoot: URL, projectID: UUID? = nil) throws -> [URL] {
        try index.validate()
        let deleting = index.projects.filter { projectID == nil || $0.id == projectID }
        guard projectID == nil || deleting.count == 1 else { throw CocoaError(.fileNoSuchFile) }
        let retained = index.projects.filter { project in !deleting.contains(where:{ $0.id == project.id }) }.flatMap(\.references)
        let selected = deleting.flatMap(\.references)
        var targets = Set<URL>()
        func checked(_ target: URL, root: URL) throws -> URL {
            let base = root.standardizedFileURL.resolvingSymlinksInPath()
            let originalRoot = root.standardizedFileURL
            guard target.standardizedFileURL.path.hasPrefix(originalRoot.path+"/") else { throw CocoaError(.fileWriteNoPermission) }
            let relative = String(target.standardizedFileURL.path.dropFirst(originalRoot.path.count+1))
            let url = base.appendingPathComponent(relative).standardizedFileURL
            guard url.path.hasPrefix(base.path+"/"),url.resolvingSymlinksInPath() == url else { throw CocoaError(.fileWriteNoPermission) }
            return url
        }
        for ref in selected {
            guard let root = roots[ref.library] else { throw CocoaError(.fileReadNoPermission) }
            // Keep a source scan when another project's design still depends on it.
            let familyRetained = retained.contains { $0.library == ref.library && $0.itemID == ref.itemID }
            if retained.contains(ref) || (!ref.kind.rawValue.hasPrefix("design") && familyRetained) { continue }
            let target: URL
            switch ref.kind {
            case .room: target = root.appendingPathComponent("Rooms/\(ref.itemID.uuidString).roomscan")
            case .house: target = root.appendingPathComponent("Houses/\(ref.itemID.uuidString).housescan")
            case .technicalRoom: target = root.appendingPathComponent("TechnicalRooms/\(ref.itemID.uuidString).technicalroom")
            case .designRoom,.designHouse,.designTechnical:
                let source = ref.kind == .designRoom ? "room" : ref.kind == .designHouse ? "house" : "technical"
                target = root.appendingPathComponent("SceneEdits/\(source)-\(ref.itemID.uuidString).json")
            }
            targets.insert(try checked(target,root:root))
        }
        for project in deleting { targets.insert(try checked(catalogueRoot.appendingPathComponent("Projects/\(project.id.uuidString)"),root:catalogueRoot)) }
        return targets.sorted { $0.path < $1.path }
    }
    static func delete(index: ProjectIndex, roots: [String:URL], catalogueRoot: URL, projectID: UUID? = nil,
                       move: ((URL,URL) throws -> Void)? = nil) throws -> ProjectIndex {
        let fm = FileManager.default,transaction = UUID().uuidString
        let rename = move ?? { try fm.moveItem(at:$0,to:$1) }
        var moved: [(original:URL,trash:URL)] = []
        do {
        let result = try ProjectIndexStore.update(root:catalogueRoot) { current in
        guard current == index else { throw CocoaError(.fileWriteUnknown) }
        let targets = try deletionTargets(index:index,roots:roots,catalogueRoot:catalogueRoot,projectID:projectID)
        for target in targets where fm.fileExists(atPath:target.path) {
            // Sibling trash is on the same volume. Its name retains the original name
            // for recovery if the process exits before the catalogue commit.
            let trash = target.deletingLastPathComponent().appendingPathComponent(".privacy-trash-"+transaction+"-"+target.lastPathComponent)
            try RoomPackage.coordinatedWrite(at:target,options:.forMoving) { try rename($0,trash) }
            moved.append((target,trash))
        }
        let ids = Set(index.projects.filter { projectID == nil || $0.id == projectID }.map(\.id))
        var updated = index
        let refs = Set(updated.projects.filter { ids.contains($0.id) }.flatMap(\.references))
        updated.projects.removeAll { ids.contains($0.id) }
        updated.pins?.removeAll { ids.contains($0.projectID) }; updated.distanceChecks?.removeAll { ids.contains($0.projectID) }
        updated.displayNames = updated.displayNames?.filter { key,_ in !refs.contains(where:{ $0.id == key }) }
        current = updated
        }
        // The index is committed. A failed purge leaves a recoverable trash item;
        // it must not resurrect references to data already partially purged.
        for item in moved { try? fm.removeItem(at:item.trash) }
        return result
        } catch {
            let failure = error
            for item in moved.reversed() {
                try RoomPackage.coordinatedWrite(at:item.original,options:.forReplacing) { try fm.moveItem(at:item.trash,to:$0) }
            }
            throw failure
        }
    }
}
