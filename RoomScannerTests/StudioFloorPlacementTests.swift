import XCTest
@testable import RoomScanner

final class StudioFloorPlacementTests: XCTestCase {
    func testConcaveFloorAndDifferentStoreyExtents() throws {
        var lower = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:"L")
        lower.walls = []; lower.objects = []
        lower.floorPolygon = [.init(x:0,y:0),.init(x:4,y:0),.init(x:4,y:1),.init(x:1,y:1),.init(x:1,y:4),.init(x:0,y:4)]
        var upper = lower; upper.id = UUID(); upper.story = 1
        upper.floorPolygon = [.init(x:10,y:10),.init(x:12,y:10),.init(x:12,y:12),.init(x:10,y:12)]
        let shell = House(name:"Floors",stories:[.init(index:0,rooms:[lower]),.init(index:1,rooms:[upper])])
        let document = SceneEditDocument(source:.house,sourceID:shell.id,title:"Design",shell:shell,objects:[])
        var item = SceneEditObject(origin:"Test",name:"Box",family:.box,position:.init(x:0.5,y:0.5,z:-0.5),size:.init(x:0.5,y:1,z:0.5))
        XCTAssertTrue(StudioPlacement.footprintInside(item,in:document))
        item.position = .init(x:1,y:0.5,z:-1); item.size = .init(x:2,y:1,z:2)
        XCTAssertFalse(StudioPlacement.footprintInside(item,in:document))
        var concave = document
        concave.shell.stories[0].rooms[0].floorPolygon = [.init(x:0,y:0),.init(x:4,y:0),.init(x:4,y:4),.init(x:3,y:4),.init(x:3,y:1),.init(x:1,y:1),.init(x:1,y:4),.init(x:0,y:4)]
        item.position = .init(x:2,y:0.5,z:-2); item.size = .init(x:4,y:1,z:4)
        XCTAssertFalse(StudioPlacement.footprintInside(item,in:concave),"Corners inside do not prove a concave floor covers the footprint")
        item.story = 1; item.size = .init(x:0.5,y:1,z:0.5)
        let placed = try StudioPlacement.available(item,in:document,allowOverlap:true)
        XCTAssertTrue(StudioPlacement.footprintInside(placed,in:document)); XCTAssertGreaterThan(placed.position.x,10)
        item.position = .init(x:11,y:0.5,z:-11); item.yaw = .pi/4; item.size = .init(x:2,y:1,z:2)
        XCTAssertFalse(StudioPlacement.footprintInside(item,in:document))
    }
}
