import XCTest
@testable import RoomScanner

final class StudioNudgeTests: XCTestCase {
    @MainActor func testGroupNudgeIsOneUndoAndPreservesSpacing() throws {
        let room = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:"Room")
        let objects = [0.0,1.0].map { x in SceneEditObject(origin:"Test",name:"Box",family:.box,position:.init(x:x,y:0.5,z:0),size:.init(x:0.2,y:1,z:0.2)) }
        let document = SceneEditDocument(source:.room,sourceID:room.id,title:"Test",shell:House(room:room),objects:objects)
        for step in [0.01,0.10] {
            let session = SceneEditSession(document); session.selectedIDs = Set(objects.map(\.id))
            try session.nudgeSelection(dx:step,dz:-step,allowOverlap:true)
            XCTAssertEqual(session.undoStack.count,1)
            for i in objects.indices {
                XCTAssertEqual(session.document.objects[i].position.x,objects[i].position.x+step,accuracy:1e-9)
                XCTAssertEqual(session.document.objects[i].position.z,-step,accuracy:1e-9)
            }
            session.undo(); XCTAssertEqual(session.document,document)
        }
    }
}
