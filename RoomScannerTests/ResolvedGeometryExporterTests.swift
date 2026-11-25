import XCTest
@testable import RoomScanner

final class ResolvedGeometryExporterTests: XCTestCase {
    private func object(_ data: Data) throws -> [String:Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
    }
    func testDeterministicExportAndExplicitUnknownDatumAndAccuracy() throws {
        let house = try HouseBuilder().build(from:SyntheticRooms.twoStoryHouse(),name:"House")
        let original = try RoomPackage.encoder.encode(house)
        let data = try ResolvedGeometryExporter.data(for:house)
        XCTAssertEqual(data,try ResolvedGeometryExporter.data(for:house))
        XCTAssertEqual(original,try RoomPackage.encoder.encode(house))
        let root = try object(data),stories = try XCTUnwrap(root["storeys"] as? [[String:Any]])
        XCTAssertEqual(root["schemaVersion"] as? Int,1); XCTAssertTrue(root["accuracyMm"] is NSNull)
        XCTAssertEqual(stories.count,2)
        for story in stories {
            XCTAssertTrue(story["elevationM"] is NSNull)
            XCTAssertEqual(story["elevationSource"] as? String,"unavailable")
            let walls = try XCTUnwrap(story["walls"] as? [[String:Any]])
            let wallIDs = Set(walls.compactMap { $0["id"] as? String })
            XCTAssertEqual(wallIDs.count,walls.count)
            for wall in walls { XCTAssertTrue(wall["accuracyMm"] is NSNull) }
            for solid in try XCTUnwrap(story["wallSolids"] as? [[String:Any]]) {
                XCTAssertTrue(wallIDs.contains(try XCTUnwrap(solid["wallID"] as? String)))
                XCTAssertGreaterThan(try XCTUnwrap(solid["topM"] as? Double),try XCTUnwrap(solid["bottomM"] as? Double))
            }
            for opening in try XCTUnwrap(story["openings"] as? [[String:Any]]) {
                let hosts = try XCTUnwrap(opening["hostWallIDs"] as? [String])
                XCTAssertFalse(hosts.isEmpty); XCTAssertTrue(Set(hosts).isSubset(of:wallIDs))
            }
        }
    }
    func testEnteredThicknessPreservesNetMeasurementsAndKnownElevation() throws {
        var room = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:"Büro")
        room.walls[0].thickness = 0.4
        let house = House(room:room),root = try object(ResolvedGeometryExporter.data(for:house,storeyElevations:[room.story:3.25]))
        let story = try XCTUnwrap((root["storeys"] as? [[String:Any]])?.first)
        XCTAssertEqual(story["elevationM"] as? Double,3.25)
        let exported = try XCTUnwrap((story["rooms"] as? [[String:Any]])?.first)
        XCTAssertEqual(exported["netAreaM2"] as? Double,RoomMeasurements(plan:room).floorArea)
        XCTAssertTrue((story["walls"] as? [[String:Any]])?.contains { $0["thicknessSource"] as? String == "storedOverrideUnverified" } == true)
        XCTAssertThrowsError(try ResolvedGeometryExporter.data(for:house,storeyElevations:[0:.nan]))
    }
}
