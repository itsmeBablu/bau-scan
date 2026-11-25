import Foundation
import Observation

/// Room library: list of `RoomRecord`s, creation, renaming,
/// suppression, import ; racine locale ou iCloud Drive (observation live,
/// downloads, conflicts — D16/D17).
@Observable
@MainActor
final class RoomStore {
    private(set) var location: StorageLocation
    private(set) var records: [RoomRecord] = []
    /// Houses (`.housescan`, v2), from newest to oldest.
    private(set) var houseRecords: [HouseRecord] = []
    private(set) var libraryProblems: [LibraryProblem] = []
    private(set) var lastError: AppError?
    /// iCloud status per package (empty in local storage).
    private(set) var cloudStatus: [UUID: CloudItemStatus] = [:]
    /// Count of iCloud packages not yet downloaded on this device.
    private(set) var pendingDownloads = 0
    /// `true` during container resolution at launch.
    private(set) var isResolvingCloud = false
    /// Forced root (`-RoomScannerStorageRoot`): no iCloud switching.
    let allowsCloud: Bool

    @ObservationIgnored private var monitor: UbiquityMonitor?
    /// Packages whose conflict resolution failed: avoids retrying on every monitor batch.
    @ObservationIgnored private var failedConflictResolutions: Set<URL> = []
    @ObservationIgnored private var isResolvingConflicts = false
    /// Houses already upgraded: a package without `structure.json`
    /// cannot be migrated, no need to reread on every `reload()`.
    @ObservationIgnored private var migratedHouses: Set<UUID> = []

    init(location: StorageLocation, allowsCloud: Bool = true) {
        self.location = location
        self.allowsCloud = allowsCloud
    }

    var isCloud: Bool { location.kind == .iCloud }

    // MARK: iCloud

    /// At launch: resolves the selected container off main thread without moving local files.
    /// switches and starts monitoring. Without account or container, stays local.
    func activateCloudIfAvailable() async {
        guard allowsCloud, !isCloud, !isResolvingCloud else { return }
        isResolvingCloud = true
        defer { isResolvingCloud = false }
        let cloud = await Task.detached(priority: .utility) { () -> StorageLocation? in
            guard let cloud = CloudAvailability.resolveLocation() else { return nil }
            // Project references retain their library identity. Opting into cloud does
            // not move or rewrite existing local packages.
            return cloud
        }.value
        guard let cloud else { return }
        switchLocation(to: cloud)
    }

    /// Setting 'Use iCloud Drive': immediate toggle. Disabling reverts to local folder
    /// (iCloud files remain in iCloud Drive; nothing is moved or deleted).
    func setCloudEnabled(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: CloudAvailability.preferenceKey)
        if enabled { await activateCloudIfAvailable() }
        else if isCloud { switchLocation(to: .local()) }
    }

    /// Switches storage root (iCloud ↔ local), reloads, and (re)starts file monitoring.
    func switchLocation(to newLocation: StorageLocation) {
        monitor?.stop(); monitor = nil
        cloudStatus = [:]; pendingDownloads = 0
        location = newLocation
        reload()
        if newLocation.kind == .iCloud {
            let m = UbiquityMonitor()
            m.onChange = { [weak self] items in self?.apply(cloudItems: items) }
            m.start()
            monitor = m
        }
    }

    private func apply(cloudItems items: [CloudItemStatus]) {
        var status: [UUID: CloudItemStatus] = [:]
        for item in items {
            if let id = UUID(uuidString: item.url.deletingPathExtension().lastPathComponent) { status[id] = item }
        }
        cloudStatus = status
        pendingDownloads = items.filter { !$0.isAvailableLocally }.count
        reload()
        let conflicts = items.filter { $0.hasUnresolvedConflicts && $0.isAvailableLocally && !failedConflictResolutions.contains($0.url) &&
            ([FileLayout.packageExtension,FileLayout.housePackageExtension].contains($0.url.pathExtension) || $0.url.deletingLastPathComponent().lastPathComponent == "SceneEdits") }.map(\.url)
        if !conflicts.isEmpty { resolveConflicts(at: conflicts) }
    }

    /// Resolves conflicts off the main thread, one batch at a time.
    private func resolveConflicts(at urls: [URL]) {
        guard !isResolvingConflicts else { return }
        isResolvingConflicts = true
        let suffix = AppLanguage.text("cloud.conflictSuffix")
        Task { [weak self] in
            let failures = await Task.detached(priority: .utility) { () -> [(URL, Error)] in
                var failed: [(URL, Error)] = []
                for url in urls {
                    do {
                        if url.pathExtension == FileLayout.packageExtension { try ConflictResolver.resolve(packageAt:url,suffix:suffix) }
                        else { try ConflictResolver.resolveAdditional(at:url,suffix:suffix) }
                    } catch { failed.append((url, error)) }
                }
                return failed
            }.value
            guard let self else { return }
            self.isResolvingConflicts = false
            for (url, error) in failures {
                self.failedConflictResolutions.insert(url)
                self.lastError = .storageFailed(error.localizedDescription)
            }
            self.reload()
        }
    }

    // MARK: Import / export

    /// Imports an incoming `.roomscan` (AirDrop, Files, double-click). If ID
    /// already exists, the imported room receives a new ID and suffix.
    @discardableResult
    func importPackage(from url: URL) throws -> RoomRecord {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        try location.prepare()
        var record = try RoomPackage.readRecord(from: url)
        let dest = location.packageURL(for: record.id)
        if FileManager.default.fileExists(atPath: dest.path) {
            // Copy is written to app's temporary folder (original folder is
            // not directly writable in sandbox), then moved to `Rooms/`.
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: staging) }
            let copy = try ConflictResolver.duplicateAsConflictCopy(packageAt: url, suffix: AppLanguage.text("cloud.importedSuffix"), into: staging)
            let tmpCopy = staging.appendingPathComponent(copy.id.uuidString).appendingPathExtension(FileLayout.packageExtension)
            try RoomPackage.coordinatedWrite(at: location.packageURL(for: copy.id), options: .forReplacing) { target in
                try FileManager.default.moveItem(at: tmpCopy, to: target)
            }
            record = copy
        } else {
            try RoomPackage.coordinatedWrite(at: dest, options: .forReplacing) { target in
                try FileManager.default.copyItem(at: url, to: target)
            }
        }
        reload()
        return record
    }

    /// Imports a `.roomscan` or `.housescan` depending on file extension.
    @discardableResult
    func importAny(from url: URL) throws -> LibraryItem {
        url.pathExtension == FileLayout.housePackageExtension ? .house(try importHousePackage(from: url)) : .room(try importPackage(from: url))
    }

    /// Imports a `.housescan`; an existing ID receives a new identity (the house
    /// and nested rooms) and a suffix.
    @discardableResult
    func importHousePackage(from url: URL) throws -> HouseRecord {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        try location.prepare()
        var record = try HousePackage.readRecord(from: url)
        let dest = location.housePackageURL(for: record.id)
        if FileManager.default.fileExists(atPath: dest.path) {
            let newID = UUID()
            record = try HouseImportCopy.write(from:url,to:location.housePackageURL(for:newID),
                name:record.name+" "+AppLanguage.text("cloud.importedSuffix"))
        } else {
            try RoomPackage.coordinatedWrite(at: dest, options: .forReplacing) { target in
                try FileManager.default.copyItem(at: url, to: target)
            }
        }
        reload()
        return record
    }

    /// Copies an export into `Exports/<Room>/` of the current root (iCloud Drive or local);
    /// visible in Files app / Finder and third-party tools.
    @discardableResult
    func saveExport(_ fileURL: URL, for record: RoomRecord) throws -> URL {
        try saveExport(fileURL, folderName: ExportService.folderName(for: record))
    }

    @discardableResult
    func saveExport(_ fileURL: URL, for subject: ExportSubject) throws -> URL {
        try saveExport(fileURL, folderName: ExportService.folderName(for: subject))
    }

    @discardableResult
    func saveExport(_ fileURL: URL, folderName: String) throws -> URL {
        let folder = location.exportsURL.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = folder.appendingPathComponent(fileURL.lastPathComponent)
        try RoomPackage.coordinatedWrite(at: dest, options: .forReplacing) { target in
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: fileURL, to: target)
        }
        return dest
    }

    /// Reloads list from disk (sorted newest to oldest).
    func reload() {
        do {
            try location.prepare()
            try PackageReplacement.recover(in:location.roomsURL)
            try PackageReplacement.recover(in:location.housesURL)
            let fm = FileManager.default
            let urls = try fm.contentsOfDirectory(at: location.roomsURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == FileLayout.packageExtension }
            // Undownloaded iCloud package has no readable `meta.json`: ignored
            // until notified by file monitor.
            libraryProblems = []
            func read<T>(_ url: URL,_ load: () throws -> T,_ version: (T) -> Int) -> T? {
                do {
                    let record = try load()
                    guard version(record) <= FloorPlan.schemaVersion else {
                        libraryProblems.append(.init(url:url,reason:.unsupportedSchema,detail:String(version(record)))); return nil
                    }
                    return record
                } catch {
                    let info = try? url.resourceValues(forKeys:[.isUbiquitousItemKey,.ubiquitousItemDownloadingStatusKey])
                    let downloaded = info?.isUbiquitousItem != true || info?.ubiquitousItemDownloadingStatus == .current
                    libraryProblems.append(.init(url:url,reason:LibraryProblem.classify(error,downloaded:downloaded),detail:error.localizedDescription))
                    return nil
                }
            }
            records = urls.compactMap { url in read(url,{ try RoomPackage.readRecord(from:url) },{ $0.schemaVersion }) }
                .sorted { $0.createdAt > $1.createdAt }
            let houseURLs = ((try? fm.contentsOfDirectory(at: location.housesURL, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == FileLayout.housePackageExtension }
            houseRecords = houseURLs.compactMap { url in read(url,{ try HousePackage.readRecord(from:url) },{ $0.schemaVersion }) }
                .sorted { $0.createdAt > $1.createdAt }
            // Schema upgrade: a house saved by an earlier version retains outdated
            // `meta.json` area and names (schema 2: room union, compound
            // names). Recomputed once here so library displays accurate values.
            // rather than stale cached values.
            for record in houseRecords where record.schemaVersion < FloorPlan.schemaVersion && !migratedHouses.contains(record.id) {
                migratedHouses.insert(record.id)
                _ = try? house(for: record)
            }
            lastError = nil
        } catch {
            lastError = .storageFailed(error.localizedDescription)
        }
    }

    func packageURL(for record: RoomRecord) -> URL { location.packageURL(for: record.id) }
    func retry(_ problem: LibraryProblem) {
        if problem.reason == .notDownloaded { do { try FileManager.default.startDownloadingUbiquitousItem(at:problem.url) } catch { lastError = .storageFailed(error.localizedDescription) } }
        reload()
    }
    func delete(_ problem: LibraryProblem) throws {
        guard libraryProblems.contains(problem),[location.roomsURL,location.housesURL].contains(problem.url.deletingLastPathComponent()) else { throw CocoaError(.fileWriteNoPermission) }
        try RoomPackage.coordinatedWrite(at:problem.url,options:.forDeleting) { try FileManager.default.removeItem(at:$0) }
        reload()
    }

    /// Suggested name for a new room, deduplicated against existing names.
    func proposedName(for label: RoomLabel) -> String {
        RoomNaming().proposedName(for: label, existingNames: records.map(\.name))
    }

    /// Saves a new package and adds it to the list.
    @discardableResult
    func save(_ package: RoomPackage) throws -> RoomRecord {
        try location.prepare()
        try package.write(to: location.packageURL(for: package.record.id))
        records.removeAll { $0.id == package.record.id }
        records.insert(package.record, at: 0)
        records.sort { $0.createdAt > $1.createdAt }
        return package.record
    }

    /// Room plan. When `scan.json` is present, the plan is recomputed by Domain
    /// logic (floor polygon, alignment); if differing from `plan.json`, the package
    /// is refreshed (plan + thumbnail) so devices converge. Without `scan.json`
    /// (minimal imported package), `plan.json` is authoritative.
    func plan(for record: RoomRecord) throws -> FloorPlan {
        let url = packageURL(for: record)
        let stored = try RoomPackage.readPlan(from: url)
        guard let scan = (try? RoomPackage.readScan(from: url)) ?? nil else { return stored }
        var rebuilt = FloorPlanBuilder().build(from: scan, name: record.name)
        rebuilt.id = stored.id; rebuilt.story = stored.story; rebuilt.transform = stored.transform
        if rebuilt != stored {
            var updated = record
            updated.areaM2 = RoomMeasurements(plan: rebuilt).floorArea
            try? RoomPackage.update(record: updated, plan: rebuilt, in: url)
            if let png = PlanRenderer.thumbnailPNG(for: rebuilt) { try? RoomPackage.writeThumbnail(png, in: url) }
            if let i = records.firstIndex(where: { $0.id == record.id }) { records[i] = updated }
        }
        return rebuilt
    }

    func rename(_ record: RoomRecord, to newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != record.name else { return }
        var plan = try plan(for: record)
        plan.name = trimmed
        var updated = record
        updated.name = trimmed
        try RoomPackage.update(record: updated, plan: plan, in: packageURL(for: record))
        if let i = records.firstIndex(where: { $0.id == record.id }) { records[i] = updated }
    }

    func delete(_ record: RoomRecord) throws {
        try RoomPackage.delete(at: packageURL(for: record))
        records.removeAll { $0.id == record.id }
    }

    // MARK: Houses (v2)

    func packageURL(for record: HouseRecord) -> URL { location.housePackageURL(for: record.id) }

    func packageURL(for item: LibraryItem) -> URL {
        switch item { case .room(let r): packageURL(for: r); case .house(let h): packageURL(for: h) }
    }

    /// Suggested name for a new house ('House', 'House 2', ...).
    func proposedHouseName() -> String {
        let base = AppLanguage.text("house.defaultName")
        let existing = Set(houseRecords.map(\.name))
        if !existing.contains(base) { return base }
        var n = 2
        while existing.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    @discardableResult
    func saveHouse(_ package: HousePackage) throws -> HouseRecord {
        try location.prepare()
        try package.write(to: packageURL(for: package.record))
        houseRecords.removeAll { $0.id == package.record.id }
        houseRecords.insert(package.record, at: 0)
        houseRecords.sort { $0.createdAt > $1.createdAt }
        return package.record
    }

    /// House package. When `structure.json` is present, house is recomputed by
    /// current Domain logic and package is updated if data or schema version
    /// differ; otherwise `house.json` is authoritative.
    ///
    /// Persisted room names are preserved — they may have been manually renamed.
    /// Exception: on schema version bump, names from older version are
    /// treated as automatic and recomputed (schema 2: compound names from all
    /// RoomPlan sections, e.g. 'Dining Room / Kitchen').
    func house(for record: HouseRecord) throws -> House {
        let url = packageURL(for: record)
        let stored = try HousePackage.readHouse(from: url)
        guard let structure = try? HousePackage.readStructure(from: url) else { return stored }
        var rebuilt = HouseBuilder().build(from: structure, name: record.name)
        rebuilt.id = stored.id
        if record.schemaVersion >= FloorPlan.schemaVersion {
            let storedNames = Dictionary(stored.allRooms.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
            for s in rebuilt.stories.indices {
                for r in rebuilt.stories[s].rooms.indices {
                    if let n = storedNames[rebuilt.stories[s].rooms[r].id] { rebuilt.stories[s].rooms[r].name = n }
                }
            }
        }
        let updated = HouseRecord(house: rebuilt, createdAt: record.createdAt)
        if rebuilt != stored || updated.areaM2 != record.areaM2 || updated.schemaVersion != record.schemaVersion {
            try? HousePackage.update(record: updated, house: rebuilt, in: url)
            if let png = PlanRenderer.thumbnailPNG(for: rebuilt) { try? HousePackage.writeThumbnail(png, in: url) }
            if let i = houseRecords.firstIndex(where: { $0.id == record.id }) { houseRecords[i] = updated }
        }
        return rebuilt
    }

    func rename(_ record: HouseRecord, to newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != record.name else { return }
        var house = try house(for: record)
        house.name = trimmed
        var updated = record
        updated.name = trimmed
        try HousePackage.update(record: updated, house: house, in: packageURL(for: record))
        if let i = houseRecords.firstIndex(where: { $0.id == record.id }) { houseRecords[i] = updated }
    }

    /// Renames a room inside a House, retaining raw captures and all survey sidecars.
    func renameRoom(in record: HouseRecord,roomID: UUID,to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,trimmed.count <= 120 else { throw AppError.storageFailed("Enter a room name of 1–120 characters.") }
        var house = try house(for: record)
        guard let si = house.stories.firstIndex(where: { $0.rooms.contains(where: { $0.id == roomID }) }),
              let ri = house.stories[si].rooms.firstIndex(where: { $0.id == roomID }) else { throw AppError.storageFailed("The selected room is no longer in this House.") }
        house.stories[si].rooms[ri].name = trimmed
        let updated = HouseRecord(house: house,createdAt: record.createdAt)
        try HousePackage.update(record: updated,house: house,in: packageURL(for: record))
        if let png = PlanRenderer.thumbnailPNG(for: house) { try? HousePackage.writeThumbnail(png,in: packageURL(for: record)) }
        if let index = houseRecords.firstIndex(where: { $0.id == record.id }) { houseRecords[index] = updated }
    }

    func delete(_ record: HouseRecord) throws {
        try HousePackage.delete(at: packageURL(for: record))
        houseRecords.removeAll { $0.id == record.id }
    }

    func delete(_ item: LibraryItem) throws {
        switch item { case .room(let r): try delete(r); case .house(let h): try delete(h) }
    }
}
