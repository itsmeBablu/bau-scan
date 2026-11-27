import XCTest
@testable import RoomScanner

final class PlanOpeningPlacementTests: XCTestCase {
    func testWindowStaysInResolvedExteriorWallAfterRoomRotationWithoutEditingScan() throws {
        var room = FloorPlanBuilder().build(from: SyntheticRooms.rectangularRoom().scan, name: "Room")
        room.transform = .init(translation: .init(x: 7, y: -3), rotation: .pi / 5)
        let opening = try XCTUnwrap(room.openings.first { $0.kind == .window })
        let original = room
        let graph = HouseWallGraph(house: House(room: room))
        let display = PlanOpeningPlacement.window(opening, in: room, graph: graph)
        let host = try XCTUnwrap(graph.openingHosts.first { $0.openingID == opening.id })
        let wall = try XCTUnwrap(graph.walls.first { host.wallIDs.contains($0.id) })
        XCTAssertEqual(wall.segment.distance(to: room.transform.apply(display.center)), 0, accuracy: 1e-8)
        XCTAssertEqual(display.center.distance(to: opening.center),wall.thickness/2,accuracy:0.000001)
        XCTAssertEqual(display.width, opening.width)
        XCTAssertEqual(display.sillHeight, opening.sillHeight)
        XCTAssertEqual(room, original)
        let door = try XCTUnwrap(room.openings.first { $0.kind == .door })
        XCTAssertEqual(PlanOpeningPlacement.window(door, in: room, graph: graph), door)
    }

    func testUnhostedWindowIsKeptAtItsObservedPosition() throws {
        let room = FloorPlanBuilder().build(from: SyntheticRooms.rectangularRoom().scan, name: "Room")
        var opening = try XCTUnwrap(room.openings.first { $0.kind == .window })
        opening.id = UUID(); opening.wallID = nil
        XCTAssertEqual(PlanOpeningPlacement.window(opening, in: room, graph: HouseWallGraph(house: House(room: room))), opening)
    }
}
