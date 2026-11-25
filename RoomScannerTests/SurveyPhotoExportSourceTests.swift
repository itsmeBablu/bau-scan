import XCTest
@testable import RoomScanner

final class SurveyPhotoExportSourceTests: XCTestCase {
    func testMetadataCatalogueAndPerFileCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let room = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:"Room"),bytes = Data([0xff,0xd8,0xff,0xd9])
        let photos = (1...200).map { SurveyPhoto(id:UUID(),roomID:room.id,number:$0,pose:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],timestamp:0) }
        try SurveyPhotoStore.write(photos,assets:Dictionary(uniqueKeysWithValues:photos.map { ($0.id,bytes) }),to:root)
        let sources = try SurveyPhotoExportSource.list(from:root,house:House(room:room))
        XCTAssertEqual(sources.count,200); XCTAssertEqual(sources.reduce(0) { $0+$1.byteCount },800)
        let target = root.appendingPathComponent("copy.jpg")
        XCTAssertEqual(try sources[0].copy(to:target),4); XCTAssertEqual(try Data(contentsOf:target),bytes)
    }
}
