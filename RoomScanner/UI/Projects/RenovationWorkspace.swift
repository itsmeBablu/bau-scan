import Foundation
import Observation

@MainActor @Observable final class RenovationWorkspace {
    private(set) var index = ProjectIndex()
    private(set) var entries: [ProjectLibraryEntry] = []
    var currentProjectID: UUID?
    var error: String?
    private(set) var loading = false
    private var catalogueRoot = StorageLocation.local().documentsURL
    private var ready = false
    var currentProject: RenovationProject? { index.projects.first { $0.id == currentProjectID } }
    func title(_ entry: ProjectLibraryEntry) -> String { index.displayNames?[entry.id] ?? entry.title }
    func rename(_ entry: ProjectLibraryEntry, to name: String) {
        let clean = name.trimmingCharacters(in:.whitespacesAndNewlines); guard !clean.isEmpty else { return }
        change { if $0.displayNames == nil { $0.displayNames = [:] }; $0.displayNames?[entry.id] = clean }
    }
    func duplicate(_ entry: ProjectLibraryEntry) async {
        do {
            // Reuse package readers/importers. Originals are read only; the copy gets its own ID.
            let owner = index.projects.first { $0.references.contains(entry.reference) }?.id
            let location = StorageLocation(kind:entry.reference.library == "icloud" ? .iCloud : .local,documentsURL:entry.root)
            let sourceKind: ProjectReference.Kind = entry.reference.kind == .designHouse ? .house : entry.reference.kind == .designRoom ? .room : entry.reference.kind == .designTechnical ? .technicalRoom : entry.reference.kind
            let sourceURL: URL = entry.isDesign ? (sourceKind == .house ? location.housePackageURL(for:entry.reference.itemID) : sourceKind == .room ? location.packageURL(for:entry.reference.itemID) : entry.root.appendingPathComponent("TechnicalRooms/\(entry.reference.itemID.uuidString).technicalroom")) : entry.url
            let newID: UUID
            if sourceKind == .technicalRoom {
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("technicalroom")
                defer { try? FileManager.default.removeItem(at:temp) }
                try FileManager.default.copyItem(at:sourceURL,to:temp)
                newID = try await TechnicalRoomLibraryStore(root:entry.root.appendingPathComponent("TechnicalRooms")).importPackage(temp)
            } else {
                newID = try RoomStore(location:location,allowsCloud:false).importAny(from:sourceURL).id
            }
            if entry.isDesign {
                let source: SceneEditDocument.Source = sourceKind == .house ? .house : sourceKind == .room ? .room : .technical
                guard var copy = try SceneEditStore.read(entry.url,source:source,id:entry.reference.itemID) else { throw CocoaError(.fileNoSuchFile) }
                copy.sourceID = newID
                try SceneEditStore.write(copy,to:SceneEditStore.url(root:entry.root,source:source,id:newID))
            }
            await reload(location:location)
            if let owner {
                assign(.init(kind:sourceKind,itemID:newID,library:entry.reference.library),to:owner)
                if entry.isDesign { assign(.init(kind:entry.reference.kind,itemID:newID,library:entry.reference.library),to:owner) }
            }
        } catch { self.error = error.localizedDescription }
    }
    func project(_ id: UUID) -> RenovationProject? { index.projects.first { $0.id == id } }
    func entry(_ reference: ProjectReference) -> ProjectLibraryEntry? {
        if let saved = entries.first(where:{ $0.reference == reference }) { return saved }
        let sourceKind: ProjectReference.Kind
        switch reference.kind { case .designHouse: sourceKind = .house; case .designRoom: sourceKind = .room; case .designTechnical: sourceKind = .technicalRoom; default: return nil }
        guard let source = entries.first(where:{ $0.reference.itemID == reference.itemID && $0.reference.library == reference.library && $0.reference.kind == sourceKind }) else { return nil }
        return .init(reference:reference,title:source.title,date:source.date,area:source.area,roomCount:source.roomCount,root:source.root,url:source.url)
    }

    func reload(location: StorageLocation) async {
        guard !loading else { return }; loading = true
        defer { loading = false }
        let local = RootView.hasForcedRoot ? location.documentsURL : StorageLocation.local().documentsURL
        catalogueRoot = local
        let roots: [(String, URL)] = location.kind == .iCloud ? [("icloud",location.documentsURL),("local",local)] : [("local",local)]
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                var found: [ProjectLibraryEntry] = [], warnings: [String] = []
                for (library, root) in roots {
                    func files(_ directory: String, _ suffix: String) throws -> [URL] {
                        let url = root.appendingPathComponent(directory)
                        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
                        return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles).filter { $0.pathExtension == suffix }
                    }
                    for url in try files("Rooms", "roomscan") {
                        do {
                            let r = try RoomPackage.readRecord(from: url)
                            found.append(.init(reference:.init(kind:.room,itemID:r.id,library:library),title:r.name,date:r.createdAt,area:r.areaM2,roomCount:1,root:root,url:url))
                        } catch { warnings.append(url.lastPathComponent) }
                    }
                    for url in try files("Houses", "housescan") {
                        do {
                            let r = try HousePackage.readRecord(from: url)
                            found.append(.init(reference:.init(kind:.house,itemID:r.id,library:library),title:r.name,date:r.createdAt,area:r.areaM2,roomCount:r.roomCount,root:root,url:url))
                        } catch { warnings.append(url.lastPathComponent) }
                    }
                    for url in try files("TechnicalRooms", "technicalroom") {
                        do {
                            let r = try TechnicalRoomPackage.readManifest(from:url)
                            found.append(.init(reference:.init(kind:.technicalRoom,itemID:r.id,library:library),title:r.name,date:r.modifiedAt,area:nil,roomCount:1,root:root,url:url))
                        } catch { warnings.append(url.lastPathComponent) }
                    }
                    for url in try files("SceneEdits", "json") {
                        do {
                            let name = url.deletingPathExtension().lastPathComponent
                            guard let split = name.firstIndex(of:"-"), let source = SceneEditDocument.Source(rawValue:String(name[..<split])),
                                  let id = UUID(uuidString:String(name[name.index(after:split)...])),
                                  let doc = try SceneEditStore.read(url,source:source,id:id) else { continue }
                            let kind: ProjectReference.Kind = source == .house ? .designHouse : source == .room ? .designRoom : .designTechnical
                            let date = (try url.resourceValues(forKeys:[.contentModificationDateKey])).contentModificationDate ?? .distantPast
                            found.append(.init(reference:.init(kind:kind,itemID:id,library:library),title:doc.title,date:date,area:nil,roomCount:doc.shell.allRooms.count,root:root,url:url))
                        } catch { warnings.append(url.lastPathComponent) }
                    }
                }
                return (try ProjectIndexStore.read(root:local),found.sorted { $0.date > $1.date },warnings)
            }.value
            var updated = result.0
            updated.reconcile(result.1.map(\.reference))
            // Attach discovered designs to the same project as their source scan.
            for design in result.1 where design.isDesign {
                let scanKind: ProjectReference.Kind = design.reference.kind == .designHouse ? .house : design.reference.kind == .designRoom ? .room : .technicalRoom
                let scan = ProjectReference(kind:scanKind,itemID:design.reference.itemID,library:design.reference.library)
                if let owner = updated.projects.first(where:{ !$0.isUnsorted && $0.references.contains(scan) }) { try updated.assign(design.reference,to:owner.id) }
            }
            try ProjectIndexStore.write(updated,root:local)
            index = updated; entries = result.1; ready = true
            if currentProjectID == nil { currentProjectID = index.projects.first(where:{ !$0.isUnsorted })?.id ?? index.projects.first?.id }
            error = result.2.isEmpty ? nil : "Some library items could not be read: " + result.2.joined(separator:", ")
        } catch { self.error = error.localizedDescription }
    }
    func change(_ edit: (inout ProjectIndex) throws -> Void) {
        guard ready else { error = "Wait for the project catalogue to finish loading."; return }
        do { var next = index; try edit(&next); try ProjectIndexStore.write(next,root:catalogueRoot); index = next }
        catch { self.error = error.localizedDescription }
    }
    func create(_ name: String) {
        let clean = name.trimmingCharacters(in:.whitespacesAndNewlines); guard !clean.isEmpty else { return }
        let project = RenovationProject(name:clean)
        change { $0.projects.append(project) }
        if index.projects.contains(where:{ $0.id == project.id }) { currentProjectID = project.id }
    }
    func assign(_ reference: ProjectReference, to id: UUID) { change { try $0.assign(reference,to:id) } }
    func note(_ text: String, projectID: UUID) {
        change { index in
            guard let i = index.projects.firstIndex(where:{ $0.id == projectID }) else { return }
            index.projects[i].notes = text; index.projects[i].modifiedAt = Date()
        }
    }
}
