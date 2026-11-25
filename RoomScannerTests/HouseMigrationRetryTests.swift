import XCTest
@testable import RoomScanner

final class HouseMigrationRetryTests: XCTestCase {
    @MainActor func testFailedMigrationRemainsVisibleAndRetriesOnReload() throws {
        let location = StorageLocation.temporary(),fm = FileManager.default
        defer { try? fm.removeItem(at:location.documentsURL) }
        try location.prepare()
        var package = try HousePackage.assemble(structure:SyntheticRooms.twoRoomApartment(),name:"Legacy",capturedStructureData:nil,usdzData:nil)
        package.record.schemaVersion = 1
        let url = location.housePackageURL(for:package.record.id)
        try package.write(to:url)
        let structure = url.appendingPathComponent("structure.json"),original = try Data(contentsOf:structure)
        try Data("invalid".utf8).write(to:structure)
        let store = RoomStore(location:location,allowsCloud:false); store.reload()
        XCTAssertNotNil(store.lastError)
        XCTAssertEqual(store.houseRecords.first?.schemaVersion,1)
        try original.write(to:structure)
        store.reload()
        XCTAssertNil(store.lastError)
        XCTAssertEqual(try HousePackage.readRecord(from:url).schemaVersion,FloorPlan.schemaVersion)
    }
}
