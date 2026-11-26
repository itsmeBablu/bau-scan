import Foundation

/// Bounded derived cache. Revision checks happen during catalogue reload, not in
/// dashboard onAppear. Decode only the changed plan/house, never raw capture/media.
actor ProjectScanSummaryCache {
    static let shared = ProjectScanSummaryCache()
    private struct Revision: Equatable {
        let path: String
        let modified: Date?
        let bytes: Int
        let fileID: String
    }
    private struct Cached {
        let revision: Revision
        let summary: ProjectScanSummary
        var accessed: UInt64
    }
    private var values: [String: Cached] = [:]
    private var counter: UInt64 = 0
    private let maximumEntries = 128

    func summaries(for entries: [ProjectLibraryEntry]) throws -> [String: ProjectScanSummary] {
        var result: [String: ProjectScanSummary] = [:]
        for entry in entries where entry.reference.kind == .house || entry.reference.kind == .room {
            try Task.checkCancellation()
            let file = entry.url.appendingPathComponent(entry.reference.kind == .house ? "house.json" : "plan.json")
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular else { throw CocoaError(.fileReadCorruptFile) }
                let revision = Revision(path: file.standardizedFileURL.path, modified: attributes[.modificationDate] as? Date,
                                        bytes: (attributes[.size] as? NSNumber)?.intValue ?? -1,
                                        fileID: String(describing: attributes[.systemFileNumber]))
                counter &+= 1
                if var cached = values[entry.id], cached.revision == revision {
                    cached.accessed = counter; values[entry.id] = cached; result[entry.id] = cached.summary
                    continue
                }
                let house = entry.reference.kind == .house ? try HousePackage.readHouse(from: entry.url) : House(room: try RoomPackage.readPlan(from: entry.url))
                let summary = ProjectScanSummary(house: house)
                values[entry.id] = Cached(revision: revision, summary: summary, accessed: counter)
                result[entry.id] = summary
                if values.count > maximumEntries, let oldest = values.min(by: { $0.value.accessed < $1.value.accessed })?.key {
                    values.removeValue(forKey: oldest)
                }
            } catch is CancellationError { throw CancellationError() }
            catch { values.removeValue(forKey: entry.id) } // unavailable data is never presented as a stale success
        }
        return result
    }
}
