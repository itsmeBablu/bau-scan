import Foundation
import Observation

struct PersistedRoom: Codable {
    let scan: ScanInput
    let raw: Data
    let partial: Bool
    var thumbnail: Data? = nil
}

/// Capture UI observes status only; file IO and encoding happen on workers.
@MainActor @Observable final class CapturePersistence {
    let id: UUID
    let kind: ScanSession.Kind
    let projectID: UUID?
    let store: ScanSessionStore?
    private(set) var savedAt: Date?
    private(set) var failure: String?
    private(set) var snapshotBytes = 0
    private(set) var snapshotMilliseconds = 0.0
    private(set) var completedRooms = 0
    init(id:UUID = UUID(),kind:ScanSession.Kind,projectID:UUID?,root:URL? = nil) {
        self.id = id; self.kind = kind; self.projectID = projectID
        do { store = ScanSessionStore(root:try root ?? ScanSessionStore.applicationSupportRoot()) }
        catch { store = nil; failure = error.localizedDescription }
    }
    func prepare() async throws {
        guard let store else { throw CocoaError(.fileWriteUnknown) }
        _ = try await store.create(kind:kind,projectID:projectID,id:id)
    }
    func write<T:Encodable>(_ value:T,key:String,latest:Bool = true,media:Bool = false) async throws {
        let start = Date()
        do {
            try await prepare()
            let data = try await Task.detached(priority:.utility) { try JSONEncoder().encode(value) }.value
            guard let store else { throw CocoaError(.fileWriteUnknown) }
            if latest { try await store.writeLatest(id,key:key,data:data) }
            else { try await store.write(id,key:key,data:data,media:media) }
            savedAt = Date(); failure = nil; snapshotBytes = data.count
            snapshotMilliseconds = Date().timeIntervalSince(start)*1000
        } catch { failure = error.localizedDescription; throw error }
    }
    func room(_ value:PersistedRoom) async throws {
        // Same room key overwrites the previous partial without growing history.
        try await write(value,key:"room-"+value.scan.id.uuidString)
        if !value.partial { completedRooms += 1 }
    }
    func rooms() async throws -> [PersistedRoom] {
        guard let store else { throw CocoaError(.fileReadUnknown) }
        return try await store.latestValues(id,prefix:"room-").map { try JSONDecoder().decode(PersistedRoom.self,from:$0.data) }
    }
    func state(_ value:ScanSession.State) async {
        do { try await prepare(); try await store?.setState(id,value) }
        catch { failure = error.localizedDescription }
    }
    func complete() async { await state(.finalizing); await state(.completed) }
}
