import XCTest
@testable import RoomScanner

final class StudioOverlayTests: XCTestCase {
    func testStoryOverlaysHaveStableUniqueIDsIncludingBasement() throws {
        let rooms = [-1,0,1].map { level -> FloorPlan in
            var room = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:"Room"); room.story = level; return room
        }
        let house = House(name:"House",stories:rooms.map { Story(index:$0.story,rooms:[$0]) })
        let document = SceneEditDocument(source:.house,sourceID:house.id,title:"Design",shell:house,objects:[])
        let overlays = document.plan.stories.compactMap { $0.rooms.last?.id }
        XCTAssertEqual(Set(overlays).count,3)
        let decoded = try JSONDecoder().decode(SceneEditDocument.self,from:JSONEncoder().encode(document))
        XCTAssertEqual(overlays,decoded.plan.stories.compactMap { $0.rooms.last?.id })
        XCTAssertFalse(overlays.contains(house.id))
    }
}
