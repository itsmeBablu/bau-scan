import XCTest
@testable import RoomScanner

final class ReportedGeometryRegressionTests:XCTestCase {
    func testObservedStraightWindowWallKeepsItsDirectionThroughResolution() throws {
        for rotation in [0.0,Double.pi/5] {
            var room = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:"Room")
            room.transform = .init(translation:.init(x:3,y:-2),rotation:rotation)
            let window = try XCTUnwrap(room.openings.first { $0.kind == .window })
            let source = try XCTUnwrap(room.walls.first { $0.id == window.wallID })
            let observed = Segment2D(start:room.transform.apply(source.start),end:room.transform.apply(source.end))
            let house = House(room:room),original = room
            let graph = HouseWallGraph(house:house)
            let resolved = graph.walls.filter { $0.sourceWallIds.contains(source.id) }
            XCTAssertFalse(resolved.isEmpty)
            for wall in resolved {
                let a = observed.direction,b = wall.segment.direction
                XCTAssertEqual(abs(a.x*b.y-a.y*b.x),0,accuracy:0.000001)
            }
            XCTAssertEqual(house.allRooms.first,original)
        }
    }
    func testUnclassifiedCapturedRoomsRetainNamesAreasAndIdentity() throws {
        var structure = SyntheticRooms.twoRoomApartment()
        for i in structure.rooms.indices { structure.rooms[i].sectionLabels = []; structure.rooms[i].sections = [] }
        var builder = HouseBuilder(); builder.naming = RoomNaming(localizedBaseName:{ _ in "Room" })
        let house = try builder.build(from:structure,name:"Unknown rooms")
        XCTAssertEqual(Set(house.allRooms.map(\.id)),Set(structure.rooms.map(\.id)))
        XCTAssertEqual(house.allRooms.map(\.name),["Room","Room 2"])
        XCTAssertTrue(house.allRooms.allSatisfy { RoomMeasurements(plan:$0).floorArea > 0 })
    }
}
