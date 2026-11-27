import XCTest
@testable import RoomScanner

final class RecoveryVisibilityTests:XCTestCase {
    func testEmptyAndSmallPartialDraftsAreHiddenAndOwnersAreIsolated() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store = ScanSessionStore(root:root),owner = UUID(),other = UUID()
        let empty = try await store.create(kind:.house,projectID:owner)
        let small = try await store.create(kind:.house,projectID:owner)
        let large = try await store.create(kind:.house,projectID:owner)
        let finished = try await store.create(kind:.house,projectID:owner)
        let foreign = try await store.create(kind:.house,projectID:other)
        let room = SyntheticRooms.rectangularRoom().scan
        let big = SyntheticRooms.rectangularRoom(origin:.zero,width:6,depth:6)
        for (session,scan,partial) in [(small,room,true),(large,big,true),(finished,room,false),(foreign,room,false)] {
            try await store.writeLatest(session.id,key:"room-"+scan.id.uuidString,data:JSONEncoder().encode(PersistedRoom(scan:scan,raw:Data(),partial:partial)))
        }
        let visible = try await store.recoveryCandidates(projectID:owner)
        XCTAssertEqual(Set(visible.map(\.id)),Set([large.id,finished.id]))
        let retained = try await store.read(empty.id)
        XCTAssertEqual(retained.id,empty.id,"Hiding an empty draft never deletes it")
        _ = try await store.write(small.id,key:"voice-recording",data:Data("retained evidence".utf8),media:true)
        let withEvidence = try await store.recoveryCandidates(projectID:owner)
        XCTAssertTrue(withEvidence.contains { $0.id == small.id })
    }
    func testTechnicalFramesAloneDoNotOfferMeshRecovery() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store = ScanSessionStore(root:root),owner = UUID()
        let session = try await store.create(kind:.technical,projectID:owner)
        var delta = TechnicalSessionDelta(timestamp:0,changed:[],removed:[],frames:[],events:[])
        _ = try await store.write(session.id,key:"mesh-delta",data:JSONEncoder().encode(delta))
        let empty = try await store.recoveryCandidates(projectID:owner)
        XCTAssertTrue(empty.isEmpty)
        let id = UUID()
        delta = TechnicalSessionDelta(timestamp:1,changed:[.init(anchorID:id,vertices:[.init(x:0,y:0,z:0),.init(x:1,y:0,z:0),.init(x:0,y:1,z:0)],triangleIndices:[0,1,2])],removed:[],frames:[],events:[])
        _ = try await store.write(session.id,key:"mesh-delta",data:JSONEncoder().encode(delta))
        let mesh = try await store.recoveryCandidates(projectID:owner)
        XCTAssertEqual(mesh.map(\.id),[session.id])
    }
}
