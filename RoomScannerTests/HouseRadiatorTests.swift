import XCTest
@testable import RoomScanner

final class HouseRadiatorTests: XCTestCase {
    private func geometry() throws -> RadiatorScanGeometry {
        try .init(frontCorners: [.zero,.init(x: 1,y: 0,z: 0),.init(x: 0,y: 0.6,z: 0)],
                  wall: .init(point: .init(x: 0,y: 0,z: -0.15),normal: .init(x: 0,y: 0,z: 1),viewpoint: 0))
    }
    private func samples(rear: Bool = true,views: Bool = true) -> [RadiatorSurfaceSample] {
        (0..<40).map { i in
            .init(point: .init(x: Double(i%10)*0.08+0.1,y: Double(i/10)*0.1+0.1,z: -0.1),
                  normal: .init(x: 0,y: 0,z: rear ? -1 : 1),viewpoint: views ? i%2 : 0)
        }
    }
    func testVisibleRearPlaneProducesWallGap() throws {
        let result = try geometry().result(roomID: UUID(),wallID: nil,samples: samples(),viewpoints: 2,preset: .kermiLongConsole30,photo: nil)
        XCTAssertEqual(try XCTUnwrap(result.depth).metres,0.1,accuracy: 1e-8)
        XCTAssertEqual(try XCTUnwrap(result.wallGap).metres,0.05,accuracy: 1e-8)
        XCTAssertEqual(result.wallGap?.source,.scanEstimate)
        XCTAssertNil(result.wallGap?.accuracyMm)
    }
    func testFrontFinsAndSingleViewCannotInventBack() throws {
        for input in [samples(rear: false),samples(views: false)] {
            let result = try geometry().result(roomID: UUID(),wallID: nil,samples: input,viewpoints: 2,preset: .none,photo: nil)
            XCTAssertNil(result.depth)
            XCTAssertNil(result.wallGap)
        }
        XCTAssertFalse(try geometry().contains(.init(x: 0.5,y: 0.3,z: -0.15)))
    }
    func testExplicitMountingAssumptionKeepsProvenance() throws {
        let result = try geometry().result(roomID: UUID(),wallID: nil,samples: [],viewpoints: 2,preset: .kermiLongConsole30,photo: nil)
        XCTAssertEqual(result.wallGap?.source,.mountingAssumption)
        XCTAssertEqual(try XCTUnwrap(result.depth).metres,0.12,accuracy: 1e-8)
        XCTAssertFalse(try XCTUnwrap(result.wallGap?.reference).isEmpty)
        XCTAssertNil(RadiatorMountingPreset.none.gap)
    }
    func testHouseSidecarSurvivesRenameAndValidatesAssociation() throws {
        let package = HousePackage.assemble(structure: SyntheticRooms.twoRoomApartment(),name: "House",capturedStructureData: nil,usdzData: nil)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("housescan")
        defer { try? FileManager.default.removeItem(at: root) }
        try package.write(to: root)
        XCTAssertNil(try HousePackage.readRadiators(from: root))
        var item = try geometry().result(roomID: XCTUnwrap(package.house.allRooms.first).id,wallID: nil,samples: samples(),viewpoints: 2,preset: .none,photo: nil)
        item.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let survey = HouseRadiatorSurvey(houseID: package.house.id,radiators: [item])
        try HousePackage.writeRadiators(survey,house: package.house,in: root)
        var renamed = package.house; renamed.name = "Renamed"
        try HousePackage.update(record: package.record,house: renamed,in: root)
        XCTAssertEqual(try HousePackage.readRadiators(from: root),survey)
        var invalid = survey; invalid.houseID = UUID()
        XCTAssertThrowsError(try HousePackage.writeRadiators(invalid,house: package.house,in: root))
    }
}
