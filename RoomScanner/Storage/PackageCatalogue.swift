import Foundation

/// Shared metadata enumeration; no scan geometry/media is decoded here. Stores
/// retain their presentation, migration and recovery policies and library roots.
enum PackageCatalogue {
    struct Snapshot<Record> {
        var records: [Record] = []
        var problems: [LibraryProblem] = []
        var urls: [UUID: URL] = [:]
    }
    static func rooms(in directory: URL, includeHidden: Bool = false) throws -> Snapshot<RoomRecord> {
        try scan(directory, suffix: "roomscan", maximumVersion: FloorPlan.schemaVersion, includeHidden: includeHidden,
                 read: RoomPackage.readRecord, id: { $0.id }, version: { $0.schemaVersion })
    }
    static func houses(in directory: URL, includeHidden: Bool = false) throws -> Snapshot<HouseRecord> {
        try scan(directory, suffix: "housescan", maximumVersion: FloorPlan.schemaVersion, includeHidden: includeHidden,
                 read: HousePackage.readRecord, id: { $0.id }, version: { $0.schemaVersion })
    }
    static func technicalRooms(in directory: URL) throws -> Snapshot<TechnicalRoomManifest> {
        try scan(directory, suffix: "technicalroom", maximumVersion: 1, includeHidden: false,
                 read: TechnicalRoomPackage.readManifest, id: { $0.id }, version: { $0.schemaVersion })
    }

    private static func scan<Record>(_ directory: URL, suffix: String, maximumVersion: Int, includeHidden: Bool,
                                     read: (URL) throws -> Record, id: (Record) -> UUID,
                                     version: (Record) -> Int) throws -> Snapshot<Record> {
        guard FileManager.default.fileExists(atPath: directory.path) else { return Snapshot() }
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                              options: includeHidden ? [] : .skipsHiddenFiles)
            .filter { $0.pathExtension == suffix }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var result = Snapshot<Record>()
        for url in urls {
            try Task.checkCancellation()
            do {
                let record = try read(url)
                guard url.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(id(record).uuidString) == .orderedSame
                else { throw CocoaError(.fileReadCorruptFile) }
                guard version(record) <= maximumVersion else {
                    result.problems.append(.init(url: url, reason: .unsupportedSchema, detail: String(version(record))))
                    continue
                }
                guard result.urls[id(record)] == nil else { throw CocoaError(.fileReadCorruptFile) }
                result.urls[id(record)] = url
                result.records.append(record)
            } catch is CancellationError { throw CancellationError() }
            catch {
                let info = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
                let downloaded = info?.isUbiquitousItem != true || info?.ubiquitousItemDownloadingStatus == .current
                result.problems.append(.init(url: url, reason: LibraryProblem.classify(error, downloaded: downloaded), detail: error.localizedDescription))
            }
        }
        return result
    }
}
