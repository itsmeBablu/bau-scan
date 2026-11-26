import Foundation
import Observation

@MainActor @Observable final class RenovationWorkspace {
    private(set) var index = ProjectIndex()
    private var libraryEntries: [ProjectLibraryEntry] = []
    private(set) var scanSummaries: [String:ProjectScanSummary] = [:]
    private(set) var catalogueRevision = 0
    var entries: [ProjectLibraryEntry] { libraryEntries.map(resolvedEntry) }
    var currentProjectID: UUID?
    var error: String?
    private(set) var loading = false
    private var catalogueRoot = StorageLocation.local().documentsURL
    var notesRoot: URL { catalogueRoot }
    private var ready = false
    private var pendingReload: StorageLocation?
    var currentProject: RenovationProject? { index.projects.first { $0.id == currentProjectID } }
    func title(_ entry: ProjectLibraryEntry) -> String {
        title(entry,locale:AppLanguage.locale)
    }
    func title(_ entry:ProjectLibraryEntry,locale:Locale) -> String {
        index.displayNames?[entry.id] ?? organization(for:entry.reference)?.displayName(locale:locale) ?? entry.title
    }
    func organization(for reference: ProjectReference) -> ScanOrganization? {
        if let value = index.scanOrganization?[reference.id] { return value }
        let sourceKind: ProjectReference.Kind
        switch reference.kind {
        case .designHouse: sourceKind = .house
        case .designRoom: sourceKind = .room
        case .designTechnical: sourceKind = .technicalRoom
        default: return nil
        }
        return index.scanOrganization?[ProjectReference(kind:sourceKind,itemID:reference.itemID,library:reference.library).id]
    }
    private func resolvedEntry(_ entry: ProjectLibraryEntry) -> ProjectLibraryEntry {
        localizedEntry(entry,locale:AppLanguage.locale)
    }
    func localizedEntry(_ entry:ProjectLibraryEntry,locale:Locale) -> ProjectLibraryEntry {
        .init(reference:entry.reference,title:title(entry,locale:locale),date:entry.date,area:entry.area,roomCount:entry.roomCount,root:entry.root,url:entry.url)
    }
    @discardableResult func organize(_ value:ScanOrganization, reference:ProjectReference, expected:ScanOrganization?) -> Bool {
        guard ready else { error = AppLanguage.text("Wait for the project catalogue to finish loading."); return false }
        do {
            index = try ProjectIndexStore.update(root:catalogueRoot) { current in
                guard current.scanOrganization?[reference.id] == expected else { throw OrganizationConflict() }
                try current.setOrganization(value,for:reference)
                current.displayNames?.removeValue(forKey:reference.id)
            }
            catalogueRevision &+= 1; error = nil; return true
        } catch { self.error = error.localizedDescription; return false }
    }
    private struct OrganizationConflict: LocalizedError {
        var errorDescription:String? { AppLanguage.text("Scan organization changed elsewhere. Reopen this editor before saving.") }
    }
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
        libraryEntries.first { $0.reference == reference }.map(resolvedEntry)
    }
    func destination(_ reference: ProjectReference) -> ProjectLibraryEntry? {
        if let saved = entries.first(where:{ $0.reference == reference }) { return saved }
        let sourceKind: ProjectReference.Kind
        switch reference.kind { case .designHouse: sourceKind = .house; case .designRoom: sourceKind = .room; case .designTechnical: sourceKind = .technicalRoom; default: return nil }
        guard let source = entries.first(where:{ $0.reference.itemID == reference.itemID && $0.reference.library == reference.library && $0.reference.kind == sourceKind }) else { return nil }
        return .init(reference:reference,title:source.title,date:source.date,area:source.area,roomCount:source.roomCount,root:source.root,url:source.url)
    }

    func reload(location: StorageLocation) async {
        guard !loading else { pendingReload = location; return }; loading = true
        let interval = PerformanceTrace.begin("CatalogueLoad")
        defer { interval.end() }
        defer {
            loading = false
            if let next = pendingReload { pendingReload = nil; Task { await reload(location:next) } }
        }
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
                    let rooms = try PackageCatalogue.rooms(in: root.appendingPathComponent("Rooms"))
                    warnings += rooms.problems.map { $0.url.lastPathComponent }
                    for r in rooms.records {
                        guard let url = rooms.urls[r.id] else { continue }
                        found.append(.init(reference:.init(kind:.room,itemID:r.id,library:library),title:r.name,date:r.createdAt,area:r.areaM2,roomCount:1,root:root,url:url))
                    }
                    let houses = try PackageCatalogue.houses(in: root.appendingPathComponent("Houses"))
                    warnings += houses.problems.map { $0.url.lastPathComponent }
                    for r in houses.records {
                        guard let url = houses.urls[r.id] else { continue }
                        found.append(.init(reference:.init(kind:.house,itemID:r.id,library:library),title:r.name,date:r.createdAt,area:r.areaM2,roomCount:r.roomCount,root:root,url:url))
                    }
                    let technical = try PackageCatalogue.technicalRooms(in: root.appendingPathComponent("TechnicalRooms"))
                    warnings += technical.problems.map { $0.url.lastPathComponent }
                    for r in technical.records {
                        guard let url = technical.urls[r.id] else { continue }
                        found.append(.init(reference:.init(kind:.technicalRoom,itemID:r.id,library:library),title:r.name,date:r.modifiedAt,area:nil,roomCount:1,root:root,url:url))
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
            let updated = try ProjectIndexStore.update(root:local) { updated in
            let discovered = result.1.filter { FileManager.default.fileExists(atPath:$0.url.path) }.map(\.reference)
            updated.reconcile(discovered)
            // Attach discovered designs to the same project as their source scan.
            for design in result.1 where design.isDesign && FileManager.default.fileExists(atPath:design.url.path) {
                let scanKind: ProjectReference.Kind = design.reference.kind == .designHouse ? .house : design.reference.kind == .designRoom ? .room : .technicalRoom
                let scan = ProjectReference(kind:scanKind,itemID:design.reference.itemID,library:design.reference.library)
                if let owner = updated.projects.first(where:{ !$0.isUnsorted && $0.references.contains(scan) }) { try updated.assign(design.reference,to:owner.id) }
            }
            }
            let available = result.1.filter { FileManager.default.fileExists(atPath:$0.url.path) }
            let summaries = try await ProjectScanSummaryCache.shared.summaries(for:available)
            index = updated; libraryEntries = available; scanSummaries = summaries; ready = true
            catalogueRevision &+= 1
            if currentProjectID == nil || !index.projects.contains(where:{ $0.id == currentProjectID }) { currentProjectID = index.projects.first(where:{ !$0.isUnsorted })?.id ?? index.projects.first?.id }
            error = result.2.isEmpty ? nil : AppLanguage.text("Some library items could not be read")+": " + result.2.joined(separator:", ")
        } catch { self.error = error.localizedDescription }
    }
    func change(_ edit: (inout ProjectIndex) throws -> Void) {
        guard ready else { error = AppLanguage.text("Wait for the project catalogue to finish loading."); return }
        do { index = try ProjectIndexStore.update(root:catalogueRoot,edit); catalogueRevision &+= 1 }
        catch { self.error = error.localizedDescription }
    }
    func create(_ name: String) {
        let clean = name.trimmingCharacters(in:.whitespacesAndNewlines); guard !clean.isEmpty else { return }
        let project = RenovationProject(name:clean)
        change { $0.projects.append(project) }
        if index.projects.contains(where:{ $0.id == project.id }) { currentProjectID = project.id }
    }
    func assign(_ reference: ProjectReference, to id: UUID) { change { try $0.assign(reference,to:id) } }
    func remove(_ entry:ProjectLibraryEntry) async {
        guard ready else { error = AppLanguage.text("Wait for the project catalogue to finish loading."); return }
        let expected = index,root = catalogueRoot
        do {
            let updated = try await Task.detached(priority:.utility) { try ProjectScanRemoval.remove(entry,expected:expected,catalogueRoot:root) }.value
            index = updated; libraryEntries.removeAll { $0.reference == entry.reference }; scanSummaries.removeValue(forKey:entry.id); catalogueRevision &+= 1
        } catch { self.error = error.localizedDescription }
    }
    func saveDetails(_ details:ProjectDetails,projectID:UUID,expected:ProjectDetails?) throws {
        guard ready else { throw CocoaError(.fileReadUnknown) }
        do {
            index = try ProjectIndexStore.updateDetails(details,projectID:projectID,expected:expected,root:catalogueRoot)
            catalogueRevision &+= 1
        } catch {
            if let current = try? ProjectIndexStore.read(root:catalogueRoot) { index = current; catalogueRevision &+= 1 }
            throw error
        }
    }
    @discardableResult func note(_ text:String,projectID:UUID,expected:String) -> Bool {
        guard ready else { error = AppLanguage.text("Wait for the project catalogue to finish loading."); return false }
        do { index = try ProjectIndexStore.updateNotes(text,projectID:projectID,expected:expected,root:catalogueRoot); catalogueRevision &+= 1; return true }
        catch {
            self.error = error.localizedDescription
            if let current = try? ProjectIndexStore.read(root:catalogueRoot) { index = current }
            return false
        }
    }
}
