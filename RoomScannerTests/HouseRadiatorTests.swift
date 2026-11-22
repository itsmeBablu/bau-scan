import XCTest
@testable import RoomScanner

final class HouseRadiatorTests: XCTestCase {
    func testAutomaticIdentificationRemainsExplicitAndLegacyJSONReadable() throws {
        var radiator = try geometry().result(roomID: UUID(),wallID: nil,samples: samples(),viewpoints: 2,preset: .none,photo: nil)
        let legacy = try JSONDecoder().decode(HouseRadiator.self,from: JSONEncoder().encode(radiator))
        XCTAssertNil(legacy.identification)
        radiator.identification = .automaticCandidate; radiator.name = "Possible radiator"
        let decoded = try JSONDecoder().decode(HouseRadiator.self,from: JSONEncoder().encode(radiator))
        XCTAssertEqual(decoded.identification,.automaticCandidate)
        XCTAssertEqual(decoded.width.source,.scanEstimate)
        XCTAssertNil(decoded.width.accuracyMm)
    }
    private func automaticGrid(clipped: Bool = false,wall: Bool = true) -> [RadiatorSurfaceSample?] {
        (0..<(60*48)).map { index in
            let x = index%60,y = index/60
            let front = x >= (clipped ? 0 : 12) && x <= 47 && y >= 12 && y <= 31
            guard front || wall else { return nil }
            return RadiatorSurfaceSample(point: .init(x: Double(x)*0.025-0.75,y: Double(y)*0.025,z: front ? 0 : -0.15),normal: .init(x: 0,y: 0,z: 1),viewpoint: 0)
        }
    }
    func testAutomaticCandidateDerivesBodyAndWallWithoutMarkedCorners() throws {
        let candidate = try XCTUnwrap(RadiatorAutomaticDetector.detect(grid: automaticGrid(),width: 60,height: 48,camera: .init(x: 0,y: 0.5,z: 1.2)))
        XCTAssertEqual(candidate.geometry.width,0.875,accuracy: 0.0001)
        XCTAssertEqual(candidate.geometry.height,0.475,accuracy: 0.0001)
        XCTAssertEqual(candidate.geometry.wallToFront,0.15,accuracy: 0.0001)
        let result = try candidate.geometry.result(roomID: UUID(),wallID: nil,samples: [],viewpoints: 2,preset: .none,photo: nil,automatic: true)
        XCTAssertEqual(result.width.method,"automaticVisibleFrontEnvelopeWidth")
        XCTAssertNil(result.depth)
        XCTAssertNil(result.wallGap,"A detected front and wall cannot establish hidden rear clearance")
    }
    func testAutomaticCandidateRejectsClippedFrontAndMissingWallEvidence() {
        for grid in [automaticGrid(clipped: true),automaticGrid(wall: false)] {
            XCTAssertNil(RadiatorAutomaticDetector.detect(grid: grid,width: 60,height: 48,camera: .init(x: 0,y: 0.5,z: 1.2)))
        }
    }
    func testAutomaticCandidateRespectsExclusionsAndTrackedTarget() throws {
        let grid = automaticGrid(),camera = RadiatorPoint(x: 0,y: 0.5,z: 1.2)
        let candidate = try XCTUnwrap(RadiatorAutomaticDetector.detect(grid: grid,width: 60,height: 48,camera: camera))
        XCTAssertNil(RadiatorAutomaticDetector.detect(grid: grid,width: 60,height: 48,camera: camera,excluded: [candidate.center]))
        XCTAssertNil(RadiatorAutomaticDetector.detect(grid: grid,width: 60,height: 48,camera: camera,target: .init(x: 5,y: 1,z: 0)))
        XCTAssertNotNil(RadiatorAutomaticDetector.detect(grid: grid,width: 60,height: 48,camera: camera,target: candidate.center))
    }
    func testAutomaticCandidateRejectsInvalidGridAndHorizontalSurfaces() {
        XCTAssertNil(RadiatorAutomaticDetector.detect(grid: [],width: 60,height: 48,camera: .zero))
        let grid = automaticGrid().map { sample -> RadiatorSurfaceSample? in
            guard var sample else { return nil }; sample.normal = .init(x: 0,y: 1,z: 0); return sample
        }
        XCTAssertNil(RadiatorAutomaticDetector.detect(grid: grid,width: 60,height: 48,camera: .init(x: 0,y: 0.5,z: 1.2)))
    }
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

    func testHouseRegistrationRejectsIndependentCameraCoordinates() throws {
        let structure = SyntheticRooms.twoRoomApartment()
        let house = HouseBuilder().build(from: structure,name: "House")
        var item = try geometry().result(roomID: UUID(),wallID: nil,samples: samples(),viewpoints: 2,preset: .none,photo: nil)
        XCTAssertThrowsError(try HouseRadiatorRegistration.associate([item],house: house,structure: structure))
        item.capturedInHouseCoordinates = true
        let result = try HouseRadiatorRegistration.associate([item],house: house,structure: structure)
        let registered = try XCTUnwrap(result.radiators.first)
        XCTAssertTrue(house.allRooms.contains { $0.id == registered.roomID && $0.walls.contains { $0.id == registered.wallID } })
        XCTAssertNotNil(registered.houseFloorElevation)
        XCTAssertEqual(registered.frontCorners,item.frontCorners)
        XCTAssertEqual(registered.samples,item.samples)
    }

    @MainActor func testOnlyRegisteredRadiatorsRenderInHouseAndRespectObjectsToggle() throws {
        let structure = SyntheticRooms.twoRoomApartment()
        let house = HouseBuilder().build(from: structure,name: "House")
        var item = try geometry().result(roomID: XCTUnwrap(house.allRooms.first).id,wallID: nil,samples: samples(),viewpoints: 2,preset: .none,photo: nil)
        var builder = PlanSceneBuilder()
        builder.radiators = [item]
        let name = "radiator:"+item.id.uuidString
        XCTAssertNil(builder.makeScene(for: house).findEntity(named: name))
        item.capturedInHouseCoordinates = true; item.houseFloorElevation = -1
        builder.radiators = [item]
        let entity = try XCTUnwrap(builder.makeScene(for: house).findEntity(named: name))
        XCTAssertEqual(entity.position.y,1.3,accuracy: 0.001)
        builder.options.showObjects = false
        XCTAssertNil(builder.makeScene(for: house).findEntity(named: name))
    }
}
