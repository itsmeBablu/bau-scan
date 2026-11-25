import Foundation

/// iCloud conflicts on `.roomscan` packages (simultaneous edit on iPhone / Mac):
/// **most recent version wins**, other version is preserved as
/// '(conflict)' with a fresh UUID — scans are never lost.
enum ConflictResolver {
    /// Preserve all losing house/design versions before marking any version resolved.
    static func resolveAdditional(at url: URL,suffix: String) throws {
        guard let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at:url),!versions.isEmpty else { return }
        for version in versions {
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension)
            defer { try? FileManager.default.removeItem(at:temporary) }
            try version.replaceItem(at:temporary)
            let folder = url.deletingLastPathComponent()
            if url.pathExtension == "housescan" {
                let record = try HousePackage.readRecord(from:temporary)
                let destination = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension("housescan")
                _ = try HouseImportCopy.write(from:temporary,to:destination,name:record.name+" "+suffix)
            } else {
                var document = try JSONDecoder().decode(SceneEditDocument.self,from:Data(contentsOf:temporary))
                document.sourceID = UUID(); document.title = String(document.title.prefix(200))+" "+suffix
                document.revision = nil; document.modifiedAt = nil
                _ = try SceneEditStore.write(document,to:SceneEditStore.url(root:folder.deletingLastPathComponent(),source:document.source,id:document.sourceID))
            }
        }
        for version in versions { version.isResolved = true }
        try NSFileVersion.removeOtherVersionsOfItem(at:url)
    }
    struct Version { var date: Date; var isCurrent: Bool }

    /// Index of winning version (most recent; on tie, current version).
    static func winnerIndex(_ versions: [Version]) -> Int? {
        guard !versions.isEmpty else { return nil }
        return versions.indices.max { a, b in
            let (va, vb) = (versions[a], versions[b])
            if va.date != vb.date { return va.date < vb.date }
            return !va.isCurrent && vb.isCurrent
        }
    }

    /// Copies a package with a new ID, suffixed name, into `directory` (by default
    /// package folder). Returns copy record; URL is `directory/<id>.roomscan`.
    @discardableResult
    static func duplicateAsConflictCopy(packageAt url: URL, suffix: String, into directory: URL? = nil, fileManager fm: FileManager = .default) throws -> RoomRecord {
        let record = try RoomPackage.readRecord(from: url)
        let plan = try RoomPackage.readPlan(from: url)
        var copyRecord = record; var copyPlan = plan
        let newID = UUID()
        copyRecord.id = newID; copyPlan.id = newID
        copyRecord.name = "\(record.name) \(suffix)"; copyPlan.name = copyRecord.name
        let dir = directory ?? url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(newID.uuidString).appendingPathExtension(FileLayout.packageExtension)
        // Coordinated source read and target write: iCloud may be
        // downloading source, and target must appear atomically.
        var coordError: NSError?; var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], writingItemAt: dest, options: .forReplacing, error: &coordError) { src, dst in
            do { try fm.copyItem(at: src, to: dst) } catch { copyError = error }
        }
        if let coordError { throw coordError }
        if let copyError { throw copyError }
        try RoomPackage.update(record: copyRecord, plan: copyPlan, in: dest)
        let photos = try SurveyPhotoStore.readCoordinated(from:dest)
        if let records = photos.photos {
            let remapped = records.map { original in
                var photo = original
                if photo.roomID == record.id { photo.roomID = newID }
                return photo
            }
            try RoomPackage.coordinatedWrite(at:dest,options:.forMerging) { target in
                try SurveyPhotoStore.write(remapped,assets:photos.assets,to:target)
            }
        }
        return copyRecord
    }

    /// Resolves conflicting versions of a package: winner becomes current version,
    /// each losing version is preserved as '(conflict)' package.
    /// can produce multiple versions). Returns created copies.
    @discardableResult
    static func resolve(packageAt url: URL, suffix: String) throws -> [RoomRecord] {
        guard let others = NSFileVersion.unresolvedConflictVersionsOfItem(at: url), !others.isEmpty else { return [] }
        let current = NSFileVersion.currentVersionOfItem(at: url)
        var versions = [Version(date: current?.modificationDate ?? .distantPast, isCurrent: true)]
        versions += others.map { Version(date: $0.modificationDate ?? .distantPast, isCurrent: false) }
        let winner = winnerIndex(versions) ?? 0
        var copies: [RoomRecord] = []
        // 1. Losing remote versions → '(conflict)' copies.
        for (i, v) in others.enumerated() where i + 1 != winner {
            copies.append(try keepAsConflictCopy(version: v, of: url, suffix: suffix))
        }
        // 2. If remote version wins: current becomes a copy, then replaced.
        if winner > 0 {
            copies.append(try duplicateAsConflictCopy(packageAt: url, suffix: suffix))
            let winning = others[winner - 1]
            try RoomPackage.coordinatedWrite(at: url, options: .forReplacing) { target in _ = try winning.replaceItem(at: target) }
        }
        for v in others { v.isResolved = true }
        try NSFileVersion.removeOtherVersionsOfItem(at: url)
        return copies
    }

    /// Materializes a `NSFileVersion` as '(conflict)' package beside original.
    private static func keepAsConflictCopy(version: NSFileVersion, of url: URL, suffix: String) throws -> RoomRecord {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("conflict-\(UUID().uuidString).roomscan")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try version.replaceItem(at: tmp)
        return try duplicateAsConflictCopy(packageAt: tmp, suffix: suffix, into: url.deletingLastPathComponent())
    }
}
