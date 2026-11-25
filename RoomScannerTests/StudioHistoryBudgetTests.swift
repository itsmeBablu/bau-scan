import XCTest
@testable import RoomScanner

final class StudioHistoryBudgetTests: XCTestCase {
    @MainActor func testMemoryBudgetAndUndoRedoBranching() throws {
        let room = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:"Room")
        let document = SceneEditDocument(source:.room,sourceID:room.id,title:"A",shell:House(room:room),objects:[])
        let limit = SceneEditSession.historyCost(document)*6
        let session = SceneEditSession(document,historyByteLimit:limit)
        for i in 0..<20 { try session.change { $0.title = "Edit \(i)" } }
        XCTAssertLessThan(session.undoStack.count,20)
        XCTAssertLessThanOrEqual(session.estimatedHistoryBytes,limit)
        let title = session.document.title
        session.undo(); XCTAssertNotEqual(session.document.title,title)
        session.redo(); XCTAssertEqual(session.document.title,title)
        session.undo(); try session.change { $0.title = "Branch" }
        XCTAssertFalse(session.canRedo); XCTAssertLessThanOrEqual(session.estimatedHistoryBytes,limit)
    }
    @MainActor func testStepCountStillCapsSmallEdits() throws {
        let room = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:"Room")
        let session = SceneEditSession(.init(source:.room,sourceID:room.id,title:"A",shell:House(room:room),objects:[]))
        for i in 0..<45 { try session.change { $0.title = "Edit \(i)" } }
        XCTAssertEqual(session.undoStack.count,40)
    }
}
