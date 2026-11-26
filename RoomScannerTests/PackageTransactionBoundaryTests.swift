import XCTest
@testable import RoomScanner

final class PackageTransactionBoundaryTests:XCTestCase {
    func testRoomStagingFailurePreservesEverySavedByteAndIndependentRecoveryCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let scan = SyntheticRooms.rectangularRoom().scan
        let plan = FloorPlanBuilder().build(from:scan,name:"Original")
        var package = RoomPackage(record:RoomRecord(plan:plan),plan:plan,scan:scan,capturedRoomData:Data("raw evidence".utf8))
        let url = root.appendingPathComponent(plan.id.uuidString+".roomscan")
        try package.write(to:url)
        let recovery = root.appendingPathComponent(".independent-recovery")
        try Data("retained recovery".utf8).write(to:recovery)
        let original = try PackageTestSnapshot.files(url)
        XCTAssertFalse(original.isEmpty)
        package.record.name = "Unsaved"; package.plan.name = "Unsaved"
        XCTAssertThrowsError(try package.write(to:url,fileManager:StageCreationOutOfSpaceFileManager())) { error in
            XCTAssertEqual((error as? CocoaError)?.code,.fileWriteOutOfSpace)
        }
        XCTAssertEqual(try PackageTestSnapshot.files(url),original)
        XCTAssertEqual(try Data(contentsOf:recovery),Data("retained recovery".utf8))
        try package.write(to:url)
        XCTAssertEqual(try RoomPackage.readRecord(from:url).name,"Unsaved")
        XCTAssertEqual(try RoomPackage.readScan(from:url),scan)
    }

    func testHouseStagingFailurePreservesNestedRoomsRawStructureAndRetry() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let structure = SyntheticRooms.twoRoomApartment()
        let house = try HouseBuilder().build(from:structure,name:"Original")
        let rooms = house.allRooms.map { room in RoomPackage(record:RoomRecord(plan:room),plan:room,scan:structure.rooms.first { $0.id == room.id }) }
        var package = HousePackage(record:HouseRecord(house:house),house:house,structure:structure,
                                   capturedStructureData:Data("raw structure".utf8),rooms:rooms)
        let url = root.appendingPathComponent(house.id.uuidString+".housescan")
        try package.write(to:url)
        let original = try PackageTestSnapshot.files(url)
        XCTAssertFalse(original.isEmpty)
        package.record.name = "Unsaved"; package.house.name = "Unsaved"
        XCTAssertThrowsError(try package.write(to:url,fileManager:StageCreationOutOfSpaceFileManager())) { error in
            XCTAssertEqual((error as? CocoaError)?.code,.fileWriteOutOfSpace)
        }
        XCTAssertEqual(try PackageTestSnapshot.files(url),original)
        try package.write(to:url)
        XCTAssertEqual(try HousePackage.readRecord(from:url).name,"Unsaved")
        XCTAssertEqual(try HousePackage.readStructure(from:url),structure)
    }
}
