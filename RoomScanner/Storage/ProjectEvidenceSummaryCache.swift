import Foundation

/// Small metadata-only dashboard cache. No JPEG/audio/mesh/world-map bytes retained.
actor ProjectEvidenceSummaryCache {
    static let shared = ProjectEvidenceSummaryCache()
    struct Summary {
        var photos:[ProjectPhotoAsset] = []
        var voices:[ARNote] = []
        var photoCount = 0
        var voiceCount = 0
        var writtenCount = 0
        var warnings:[String] = []
    }
    private struct Revision:Equatable {
        let path:String
        let date:Date?
        let bytes:Int?
        let label:String
    }
    private struct Cached { let revision:[Revision]; let summary:Summary }
    private var values:[String:Cached] = [:]
    private var order:[String] = []
    func summary(projectID:UUID,entries:[ProjectLibraryEntry],notesRoot:URL,summaries:[String:ProjectScanSummary]) throws -> Summary {
        let entries = entries.filter { !$0.isDesign }.sorted { $0.id < $1.id }
        let notes = ARNoteStore.url(root:notesRoot,projectID:projectID)
        func revision(_ file:URL,label:String) -> Revision {
            let info = try? file.resourceValues(forKeys:[.contentModificationDateKey,.fileSizeKey])
            return Revision(path:file.path,date:info?.contentModificationDate,bytes:info?.fileSize,label:label)
        }
        let revisions = entries.map { entry in
            revision(entry.url.appendingPathComponent(entry.reference.kind == .technicalRoom ? "evidence.json" : "survey-photos.json"),
                     label:entry.title+(summaries[entry.id]?.roomDetails.map { $0.id.uuidString+$0.name }.joined(separator:"|") ?? ""))
        } + [revision(notes.appendingPathComponent("index-v1.json"),label:""),
             revision(notes.deletingLastPathComponent().appendingPathComponent(".ARNotes-backup/index-v1.json"),label:"")]
        let key = notesRoot.path+"|"+projectID.uuidString
        if let cached = values[key],cached.revision == revisions { return cached.summary }
        var result = Summary(),ids = Set<UUID>()
        for entry in entries {
            try Task.checkCancellation()
            do {
                for asset in try ProjectPhotoAsset.list(entry:entry,summary:summaries[entry.id]) where ids.insert(asset.photo.id).inserted {
                    result.photoCount += 1
                    result.photos.append(asset)
                    result.photos.sort {
                        let a = $0.photo.capturedAt ?? .distantPast,b = $1.photo.capturedAt ?? .distantPast
                        return a == b ? $0.id < $1.id : a > b
                    }
                    if result.photos.count > 6 { result.photos.removeLast() }
                }
            } catch { result.warnings.append(entry.title+": "+error.localizedDescription) }
        }
        do {
            let allowed = Set(entries.map(\.reference))
            let index = try ARNoteStore.index(root:notesRoot,projectID:projectID)
            let notes = index.notes.filter { allowed.contains($0.reference) }
            let voices = notes.filter { $0.audioFileName != nil }.sorted {
                let a = $0.audioModifiedAt ?? $0.createdAt,b = $1.audioModifiedAt ?? $1.createdAt
                return a == b ? $0.id.uuidString < $1.id.uuidString : a > b
            }
            result.voices = Array(voices.prefix(3)); result.voiceCount = voices.count
            result.writtenCount = notes.filter { !$0.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }.count
        } catch { result.warnings.append(error.localizedDescription) }
        values[key] = Cached(revision:revisions,summary:result)
        order.removeAll { $0 == key }; order.append(key)
        if order.count > 16 { values.removeValue(forKey:order.removeFirst()) }
        return result
    }
}
