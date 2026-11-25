import XCTest
@testable import RoomScanner

final class HouseImportCopyTests: XCTestCase {
    func testDuplicateCopyKeepsRawEvidenceAndRemapsRoomPhotoLinks() throws {
        let fm = FileManager.default,root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at:root) }
        let scan = SyntheticRooms.rectangularRoom().scan,room = FloorPlanBuilder().build(from:scan,name:"Room")
        let house = House(room:room),raw = Data("opaque captured structure".utf8),asset = Data([0xff,0xd8,0xff,0xd9])
        let photo = SurveyPhoto(id:UUID(),roomID:room.id,number:1,pose:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],timestamp:0)
        var package = HousePackage(record:HouseRecord(house:house),house:house,structure:.init(rooms:[scan]),capturedStructureData:raw,
            rooms:[RoomPackage(record:RoomRecord(plan:room),plan:room,scan:scan)],usdzData:Data("USDZ".utf8),thumbnailPNG:nil)
        package.surveyPhotos = [photo]; package.surveyPhotoAssets = [photo.id:asset]
        let original = root.appendingPathComponent(house.id.uuidString).appendingPathExtension("housescan")
        try package.write(to:original)
        let destination = root.appendingPathComponent(UUID().uuidString).appendingPathExtension("housescan")
        let record = try HouseImportCopy.write(from:original,to:destination,name:"Imported")
        let copy = try HousePackage.readHouse(from:destination),photos = try SurveyPhotoStore.readCoordinated(from:destination)
        XCTAssertNotEqual(record.id,house.id); XCTAssertNotEqual(copy.allRooms[0].id,room.id)
        XCTAssertEqual(try HousePackage.readStructure(from:destination)?.rooms.first?.id,copy.allRooms[0].id)
        XCTAssertEqual(try RoomPackage.readRecord(from:HousePackage.roomPackageURLs(in:destination)[0]).id,copy.allRooms[0].id)
        XCTAssertEqual(photos.photos?.first?.roomID,copy.allRooms[0].id); XCTAssertNotEqual(photos.photos?.first?.id,photo.id)
        XCTAssertEqual(photos.assets.values.first,asset)
        XCTAssertEqual(try Data(contentsOf:destination.appendingPathComponent("structure-apple.json")),raw)
        XCTAssertEqual(try Data(contentsOf:destination.appendingPathComponent("house.usdz")),Data("USDZ".utf8))
    }
}
