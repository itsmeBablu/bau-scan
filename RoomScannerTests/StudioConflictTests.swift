import XCTest
@testable import RoomScanner

final class StudioConflictTests: XCTestCase {
    func testLegacyReadsAndStaleWriterPreservesBothVersions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let room = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:"Room")
        let legacy = SceneEditDocument(source:.room,sourceID:room.id,title:"Legacy",shell:House(room:room),objects:[])
        let file = SceneEditStore.url(root:root,source:.room,id:room.id)
        let first = try SceneEditStore.write(legacy,to:file)
        XCTAssertEqual(first.revision,1)
        var mine = first,other = first; mine.title = "Mine"; other.title = "Other"
        _ = try SceneEditStore.write(other,to:file)
        do { try SceneEditStore.write(mine,to:file); XCTFail("Stale writer overwrote newer data") }
        catch let conflict as SceneEditStore.Conflict {
            let copy = try JSONDecoder().decode(SceneEditDocument.self,from:Data(contentsOf:conflict.copy))
            XCTAssertTrue(copy.title.hasPrefix("Mine")); XCTAssertNotEqual(copy.sourceID,mine.sourceID)
        }
        XCTAssertEqual(try SceneEditStore.read(file,source:.room,id:room.id)?.title,"Other")
        XCTAssertNil(try JSONDecoder().decode(SceneEditDocument.self,from:JSONEncoder().encode(legacy)).revision)
    }
}
