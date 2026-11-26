import XCTest
@testable import RoomScanner

final class LibraryItemOperationTests:XCTestCase {
    @MainActor func testNativeRenameAndExportAdaptersKeepRoomAndHouseIdentityAndSourceURLs() throws {
        let location = StorageLocation.temporary()
        defer { try? FileManager.default.removeItem(at:location.documentsURL) }
        let store = RoomStore(location:location,allowsCloud:false)
        store.reload()
        let scan = SyntheticRooms.rectangularRoom().scan
        let plan = FloorPlanBuilder().build(from:scan,name:"Room")
        let room = try store.save(RoomPackage(record:RoomRecord(plan:plan),plan:plan,scan:scan))
        let structure = SyntheticRooms.twoRoomApartment()
        let house = try HouseBuilder().build(from:structure,name:"House")
        let rooms = house.allRooms.map { plan in RoomPackage(record:RoomRecord(plan:plan),plan:plan,scan:structure.rooms.first { $0.id == plan.id }) }
        let savedHouse = try store.saveHouse(HousePackage(record:HouseRecord(house:house),house:house,structure:structure,rooms:rooms))
        try store.rename(.room(room),to:"Room updated")
        try store.rename(.house(savedHouse),to:"House updated")
        let currentRoom = try XCTUnwrap(store.records.first { $0.id == room.id })
        let currentHouse = try XCTUnwrap(store.houseRecords.first { $0.id == savedHouse.id })
        let roomSubject = try store.exportSubject(for:.room(currentRoom))
        let houseSubject = try store.exportSubject(for:.house(currentHouse))
        XCTAssertEqual(roomSubject.id,room.id); XCTAssertEqual(roomSubject.kind,.room)
        XCTAssertEqual(houseSubject.id,savedHouse.id); XCTAssertEqual(houseSubject.kind,.house)
        XCTAssertEqual(roomSubject.name,"Room updated"); XCTAssertEqual(houseSubject.name,"House updated")
        XCTAssertEqual(roomSubject.sourcePackageURL,store.packageURL(for:room))
        XCTAssertEqual(houseSubject.sourcePackageURL,store.packageURL(for:savedHouse))
        XCTAssertEqual(try RoomPackage.readScan(from:store.packageURL(for:room)),scan)
        XCTAssertEqual(try HousePackage.readStructure(from:store.packageURL(for:savedHouse)),structure)
    }
}
