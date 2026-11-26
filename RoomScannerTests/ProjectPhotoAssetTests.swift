import XCTest
@testable import RoomScanner

final class ProjectPhotoAssetTests: XCTestCase {
    private let pose:[Double] = [1,0,0,0,0,1,0,0,0,0,1,0,1,2,3,1]
    func testRoomMetadataAndSingleAssetReadNeedNoRawScanOrOtherPhotoBytes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let plan = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:"Kitchen")
        let photo = SurveyPhoto(id:UUID(),roomID:plan.id,number:1,pose:pose,timestamp:10)
        let other = SurveyPhoto(id:UUID(),roomID:plan.id,number:2,pose:pose,timestamp:20)
        let bytes = Data([0xff,0xd8,0xff,0xd9])
        var package = RoomPackage(record:RoomRecord(plan:plan),plan:plan,scan:nil,capturedRoomData:nil,usdzData:nil,usdzMeshData:nil,thumbnailPNG:nil)
        package.surveyPhotos = [photo,other]; package.surveyPhotoAssets = [photo.id:bytes,other.id:bytes]
        let url = root.appendingPathComponent("room.roomscan"); try package.write(to:url)
        let entry = ProjectLibraryEntry(reference:.init(kind:.room,itemID:plan.id,library:"local"),title:"Kitchen",date:Date(),area:nil,roomCount:1,root:root,url:url)
        let summary = ProjectScanSummary(house:House(room:plan))
        // Source listing uses photo metadata and supplied cached room names only.
        try Data("unreadable plan".utf8).write(to:url.appendingPathComponent("plan.json"),options:.atomic)
        try Data("bad image".utf8).write(to:url.appendingPathComponent(other.jpegPath),options:.atomic)
        let assets = try ProjectPhotoAsset.list(entry:entry,summary:summary)
        XCTAssertEqual(assets.count,2)
        XCTAssertEqual(assets.first?.roomName,"Kitchen")
        XCTAssertEqual(try assets[0].image().jpegData,bytes)
        XCTAssertThrowsError(try assets[1].image())
        XCTAssertFalse(FileManager.default.fileExists(atPath:url.appendingPathComponent("scan.json").path))
    }
    func testTechnicalPhotoProjectionRetainsPoseTimestampAndCapturedDate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        try FileManager.default.createDirectory(at:root.appendingPathComponent("capture-images"),withIntermediateDirectories:true)
        let id = UUID(),source = UUID(),date = Date(timeIntervalSinceReferenceDate:100)
        let json:[String:Any] = ["keyframes":[["id":id.uuidString,"userPhoto":true,"capturedAt":100,
            "depth":["cameraTransform":pose,"timestamp":42,"depthMetres":[0,0,0]]]]]
        try JSONSerialization.data(withJSONObject:json).write(to:root.appendingPathComponent("evidence.json"))
        try Data([0xff,0xd8,0xff,0xd9]).write(to:root.appendingPathComponent("capture-images/"+id.uuidString+".jpg"))
        let entry = ProjectLibraryEntry(reference:.init(kind:.technicalRoom,itemID:source,library:"local"),title:"Technik",date:Date(),area:nil,roomCount:1,root:root,url:root)
        let asset = try XCTUnwrap(ProjectPhotoAsset.list(entry:entry,summary:nil).first)
        XCTAssertEqual(asset.photo.pose,pose); XCTAssertEqual(asset.photo.timestamp,42)
        XCTAssertEqual(asset.photo.capturedAt,date); XCTAssertEqual(asset.photo.number,1)
        XCTAssertEqual(asset.photo.roomID,source)
        XCTAssertTrue(asset.photo.deviceValidationPending)
        XCTAssertEqual(try asset.image().jpegData,Data([0xff,0xd8,0xff,0xd9]))
        // The metadata reader does not require a mesh, annotation document or world map.
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("capture.json").path))
    }
}
