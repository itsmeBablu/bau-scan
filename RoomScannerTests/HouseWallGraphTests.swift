import XCTest
@testable import RoomScanner

final class HouseWallGraphTests: XCTestCase {
    func testPartialSharedWallKeepsExteriorRemainder() throws {
        let structure = StructureInput(rooms: [
            SyntheticRooms.rectangularRoom(origin: .zero, width: 4, depth: 6),
            SyntheticRooms.rectangularRoom(origin: Point2D(x: 4.12, y: 1), width: 3, depth: 3)
        ])
        let graph = HouseWallGraph(house: try HouseBuilder().build(from: structure, name: "Partial"))
        let shared = graph.walls.filter { $0.wallType == .interior }
        XCTAssertEqual(shared.count, 1)
        XCTAssertEqual(try XCTUnwrap(shared.first).segment.length, 3, accuracy: 0.4)
        XCTAssertTrue(graph.walls.contains {
            $0.wallType == .exterior && $0.segment.start.x > 3.5 && $0.segment.start.x < 4.5
        })
        assertDisjoint(graph)
    }

    func testFourRoomsAtXJunctionHaveDisjointFootprints() throws {
        let rooms = [Point2D(x: 0, y: 0), Point2D(x: 4.12, y: 0),
                     Point2D(x: 0, y: 3.12), Point2D(x: 4.12, y: 3.12)].map {
            SyntheticRooms.rectangularRoom(origin: $0, width: 4, depth: 3)
        }
        let graph = HouseWallGraph(house: try HouseBuilder().build(from: StructureInput(rooms: rooms), name: "X"))
        XCTAssertEqual(graph.walls.filter { $0.wallType == .interior }.count, 4)
        assertDisjoint(graph)
    }

    func testOpeningOnMergedWallRetainsHost() throws {
        var house = try HouseBuilder().build(from: SyntheticRooms.twoRoomApartment(), name: "Hosts")
        let room = house.stories[0].rooms[0]
        let wall = try XCTUnwrap(room.walls.first {
            abs($0.start.x - 4) < 0.001 && abs($0.end.x - 4) < 0.001
        })
        let opening = Opening(id: UUID(), kind: .door, wallID: wall.id,
                              center: wall.segment.midpoint, width: 0.9, height: 2.1,
                              sillHeight: 0, angle: wall.segment.angle, confidence: .high)
        house.stories[0].rooms[0].openings = [opening]
        let graph = HouseWallGraph(house: house)
        let host = try XCTUnwrap(graph.openingHosts.first { $0.openingID == opening.id })
        XCTAssertEqual(host.wallIDs.count, 1)
        let resolved = try XCTUnwrap(graph.walls.first { host.wallIDs.contains($0.id) })
        XCTAssertEqual(resolved.wallType, .interior)
        XCTAssertTrue(resolved.sourceWallIds.contains(wall.id))
    }

    func testSeparatedRoomsDoNotMerge() throws {
        let rooms = [
            SyntheticRooms.rectangularRoom(origin: .zero, width: 4, depth: 3),
            SyntheticRooms.rectangularRoom(origin: Point2D(x: 4.6, y: 0), width: 4, depth: 3)
        ]
        let graph = HouseWallGraph(house: try HouseBuilder().build(from: StructureInput(rooms: rooms), name: "Separated"))
        XCTAssertTrue(graph.walls.allSatisfy { $0.wallType == .exterior })
    }
    private func assertDisjoint(_ graph: HouseWallGraph, file: StaticString = #filePath, line: UInt = #line) {
        for i in graph.walls.indices {
            for j in graph.walls.indices where j > i {
                for first in graph.walls[i].footprints {
                    for second in graph.walls[j].footprints {
                        XCTAssertLessThanOrEqual(Polygon2D.intersectionArea([first, second]), 0.000001, file: file, line: line)
                    }
                }
            }
        }
    }

    func testThreeRoomTJunctionHasDisjointFootprints() throws {
        let structure = StructureInput(rooms: [
            SyntheticRooms.rectangularRoom(origin: .zero, width: 4, depth: 6),
            SyntheticRooms.rectangularRoom(origin: Point2D(x: 4.12, y: 0), width: 3, depth: 2.94),
            SyntheticRooms.rectangularRoom(origin: Point2D(x: 4.12, y: 3.06), width: 3, depth: 2.94)
        ])
        let house = try HouseBuilder().build(from: structure, name: "T")
        let graph = HouseWallGraph(house: house)
        XCTAssertGreaterThanOrEqual(graph.walls.filter { $0.wallType == .interior }.count, 3)
        assertDisjoint(graph)
    }

    func testSingleRoomLCornersHaveDisjointFootprints() throws {
        let house = House(room: FloorPlanBuilder().build(from: SyntheticRooms.rectangularRoom(origin: .zero, width: 4, depth: 3), name: "Room"))
        let graph = HouseWallGraph(house: house)
        XCTAssertEqual(graph.walls.count, 4)
        assertDisjoint(graph)
        XCTAssertTrue(graph.walls.allSatisfy { !$0.footprints.isEmpty })
    }

    func testRealHouseGraphDiagnosticsAndFootprints() throws {
        let url = try XCTUnwrap(Bundle(for: RealHouseTests.self).url(forResource: "house.structure", withExtension: "json"))
        let structure = try RoomPackage.decoder.decode(StructureInput.self, from: Data(contentsOf: url))
        let graph = HouseWallGraph(house: try HouseBuilder().build(from: structure, name: "Real"))
        print("Resolved wall count: \(graph.walls.count); Apple merged walls: \(structure.mergedWalls.count)")
        XCTAssertFalse(graph.walls.isEmpty)
        assertDisjoint(graph)
    }
    func testCoincidentSharedWallResolvesOnce() throws {
        let house = try HouseBuilder().build(from: SyntheticRooms.twoRoomApartment(), name: "Apartment")
        let graph = HouseWallGraph(house: house)
        let shared = graph.walls.filter { $0.wallType == .interior }
        XCTAssertEqual(shared.count, 1)
        XCTAssertEqual(shared.first?.thicknessSource, .defaultValue)
        XCTAssertEqual(shared.first?.thickness ?? 0, 0.115, accuracy: 0.000001)
        XCTAssertEqual(shared.first?.roomIdsOnSideA.count, 1)
        XCTAssertEqual(shared.first?.roomIdsOnSideB.count, 1)
    }

    func testMeasuredGapAndNetRoomGeometryArePreserved() throws {
        var house = try HouseBuilder().build(from: SyntheticRooms.twoRoomApartment(), name: "Apartment")
        house.stories[0].rooms[1].transform.translation.x = 0.12
        let original = house
        let graph = HouseWallGraph(house: house)
        let shared = try XCTUnwrap(graph.walls.first { $0.wallType == .interior })
        XCTAssertEqual(shared.thickness, 0.12, accuracy: 0.00001)
        XCTAssertEqual(shared.thicknessSource, .measured)
        XCTAssertEqual(house, original)
        for room in house.allRooms {
            XCTAssertEqual(RoomMeasurements(plan: room), RoomMeasurements(plan: try XCTUnwrap(original.allRooms.first { $0.id == room.id })))
        }
    }
}
