import Foundation
import CryptoKit

struct TechnicalSessionDelta: Codable {
    var schemaVersion = 1
    let timestamp: Double
    let changed: [TechnicalMeshSnapshot.Patch]
    let removed: [UUID]
    let frames: [TechnicalFrameRecord]
    let events: [TechnicalCaptureJournal.Event]
}
struct TechnicalSessionState: Codable {
    let document: TechnicalAnnotationDocument
    let alignment: TechnicalAlignmentSurvey
}

/// Hashes and serializes only changed anchor geometry. One commit record covers
/// a whole flush, so an interruption cannot publish half of a mesh delta.
actor TechnicalSessionDeltaWriter {
    private var hashes: [UUID:Data] = [:]
    private var lastFrame = -Double.infinity
    private var eventKeys: Set<String> = []
    func append(snapshot:TechnicalMeshSnapshot,active:Set<UUID>,journal:TechnicalCaptureJournal,
                store:ScanSessionStore,id:UUID) async throws -> Int {
        var next = hashes,changed:[TechnicalMeshSnapshot.Patch] = []
        for patch in snapshot.patches {
            let bytes = try JSONEncoder().encode(patch),hash = Data(SHA256.hash(data:bytes))
            if hashes[patch.anchorID] != hash { changed.append(patch); next[patch.anchorID] = hash }
        }
        let removed = hashes.keys.filter { !active.contains($0) }
        for key in removed { next.removeValue(forKey:key) }
        let frames = journal.frames.filter { $0.timestamp > lastFrame }
        func key(_ event:TechnicalCaptureJournal.Event) -> String { "\(event.timestamp)-\(event.kind.rawValue)-\(event.message)" }
        let events = journal.events.filter { !eventKeys.contains(key($0)) }
        guard !changed.isEmpty || !removed.isEmpty || !frames.isEmpty || !events.isEmpty else { return 0 }
        let value = TechnicalSessionDelta(timestamp:snapshot.timestamp,changed:changed,removed:removed,frames:frames,events:events)
        let bytes = try JSONEncoder().encode(value)
        try await store.write(id,key:"mesh-delta",data:bytes)
        hashes = next; lastFrame = frames.last?.timestamp ?? lastFrame
        eventKeys.formUnion(events.map(key))
        return bytes.count
    }
    static func recover(store:ScanSessionStore,id:UUID) async throws -> TechnicalCaptureJournal {
        var patches:[UUID:TechnicalMeshSnapshot.Patch] = [:],journal = TechnicalCaptureJournal(),time = 0.0
        let entries = try await store.entries(id).filter { $0.key == "mesh-delta" }
        for entry in entries {
            let delta = try JSONDecoder().decode(TechnicalSessionDelta.self,from:await store.payload(id,entry:entry))
            guard delta.schemaVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
            for removed in delta.removed { patches.removeValue(forKey:removed) }
            for patch in delta.changed { patches[patch.anchorID] = patch }
            for frame in delta.frames { journal.append(frame) }
            for event in delta.events { journal.append(event) }
            time = delta.timestamp
        }
        if !patches.isEmpty {
            guard journal.append(.init(timestamp:time,patches:patches.values.sorted { $0.anchorID.uuidString < $1.anchorID.uuidString },alignmentVerified:false,truncated:false)) else { throw CocoaError(.fileReadTooLarge) }
        }
        try journal.validate(); return journal
    }
}
