import Foundation
import Observation

/// Capture UI observes status only; file IO and encoding happen on workers.
@MainActor @Observable final class CapturePersistence {
    let id: UUID
    let kind: ScanSession.Kind
    let projectID: UUID?
    let organization: ScanOrganization?
    let store: ScanSessionStore?
    private(set) var savedAt: Date?
    private(set) var failure: String?
    private(set) var snapshotBytes = 0
    private(set) var snapshotMilliseconds = 0.0
    private(set) var completedRooms = 0
    init(id:UUID = UUID(),kind:ScanSession.Kind,projectID:UUID?,root:URL? = nil,organization:ScanOrganization? = nil) {
        self.id = id; self.kind = kind; self.projectID = projectID
        self.organization = organization
        do { if let root { store = ScanSessionStore(root:root) } else { store = try ScanSessionStore.local() } }
        catch { store = nil; failure = error.localizedDescription }
    }
    func prepare() async throws {
        guard let store else { throw CocoaError(.fileWriteUnknown) }
        _ = try await store.create(kind:kind,projectID:projectID,id:id,organization:organization)
    }
    /// Commit catalogue metadata before marking a newly saved package complete.
    /// The catalogue owns labels; no native package format is changed.
    func registerOrganization(for reference:ProjectReference,catalogueRoot:URL) async throws {
        guard let organization else { return }
        let projectID = projectID
        try await Task.detached(priority:.utility) {
            _ = try ProjectIndexStore.update(root:catalogueRoot) { index in
                if let projectID, index.projects.contains(where:{ $0.id == projectID }) {
                    try index.assign(reference,to:projectID)
                } else { index.reconcile([reference]) }
                if index.scanOrganization?[reference.id] == nil { try index.setOrganization(organization,for:reference) }
            }
        }.value
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
    func recordFailure(_ error:Error) { failure = error.localizedDescription }
    func recordSaved(bytes:Int,milliseconds:Double) { savedAt = Date(); failure = nil; snapshotBytes = bytes; snapshotMilliseconds = milliseconds }
    func complete() async {
        let interval = PerformanceTrace.begin("ScanCompletionStateWrite")
        defer { interval.end() }
        do {
            try await prepare()
            guard let store else { throw CocoaError(.fileWriteUnknown) }
            // Repeated finalization is idempotent. Do not attempt to reopen a
            // completed session, or advance after a failed finalizing write.
            if try await store.read(id).state != .completed {
                try await store.setState(id,.finalizing)
                try await store.setState(id,.completed)
            }
            failure = nil
        } catch { failure = error.localizedDescription }
    }
}
