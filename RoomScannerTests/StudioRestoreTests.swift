import XCTest
@testable import RoomScanner

@MainActor final class StudioRestoreTests:XCTestCase {
    func testRestoreIsUndoableAndSavingReplacesTheSameDesignWithoutChangingScan() throws {
        let location = StorageLocation.temporary()
        defer { try? FileManager.default.removeItem(at:location.documentsURL) }
        let scan = SyntheticRooms.rectangularRoom().scan
        let plan = FloorPlanBuilder().build(from:scan,name:"Original room")
        let source = location.packageURL(for:plan.id)
        try RoomPackage(record:RoomRecord(plan:plan),plan:plan,scan:scan).write(to:source)
        let sourceBytes = try Data(contentsOf:source.appendingPathComponent("plan.json"))
        let seed = try StudioScanSeed.load(source:.room,id:plan.id,root:location.documentsURL)
        let file = SceneEditStore.url(root:location.documentsURL,source:.room,id:plan.id)
        let first = try SceneEditStore.write(seed,to:file)
        var changed = first; changed.floorColor = .init(x:0.1,y:0.2,z:0.3)
        let saved = try SceneEditStore.write(changed,to:file)
        let session = SceneEditSession(saved)
        let edited = session.document
        try session.restoreFromScan(seed)
        XCTAssertTrue(session.dirty)
        XCTAssertEqual(session.document.floorColor,seed.floorColor)
        XCTAssertEqual(session.document.revision,saved.revision)
        session.undo(); XCTAssertEqual(session.document,edited)
        session.redo(); XCTAssertEqual(session.document.floorColor,seed.floorColor)
        let committed = try SceneEditStore.write(session.document,to:file)
        XCTAssertEqual(committed.revision,3)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:file.deletingLastPathComponent().path),[file.lastPathComponent])
        XCTAssertEqual(try Data(contentsOf:source.appendingPathComponent("plan.json")),sourceBytes)
    }

    func testWrongOrMissingSourceCannotReplaceTheCurrentDesign() throws {
        let location = StorageLocation.temporary()
        defer { try? FileManager.default.removeItem(at:location.documentsURL) }
        let plan = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:"Room")
        let seed = SceneEditDocument.seed(house:House(room:plan),source:.room,id:plan.id)
        let session = SceneEditSession(seed)
        var wrong = seed; wrong.sourceID = UUID()
        XCTAssertThrowsError(try session.restoreFromScan(wrong))
        XCTAssertEqual(session.document,seed)
        XCTAssertTrue(session.undoStack.isEmpty)
        XCTAssertThrowsError(try StudioScanSeed.load(source:.room,id:plan.id,root:location.documentsURL))
        XCTAssertEqual(session.document,seed)
    }

    func testDesignCardMatchingPreservesSourceTypeLibraryAndID() {
        let id = UUID()
        let local = ProjectReference(kind:.house,itemID:id,library:"local")
        let cloud = ProjectReference(kind:.house,itemID:id,library:"icloud")
        let room = ProjectReference(kind:.room,itemID:id,library:"local")
        XCTAssertEqual(local.designReference,.init(kind:.designHouse,itemID:id,library:"local"))
        XCTAssertNotEqual(local.designReference,cloud.designReference)
        XCTAssertNotEqual(local.designReference,room.designReference)
        XCTAssertEqual(local.designReference.designReference,local.designReference)
    }
}
