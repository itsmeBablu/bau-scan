import XCTest
@testable import RoomScanner

final class OrganisedPhotoIndexTests: XCTestCase {
    private let pose: [Double] = [1,0,0,0,0,1,0,0,0,0,1,0,2,3,4,1]

    func testIndexPreservesIdentityPoseAndUnknownAccuracy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let bytes = Data([0xff,0xd8,0xff,0xd9])
        try bytes.write(to:root.appendingPathComponent("photo-01.jpg"))
        let source = UUID(),room = UUID()
        let photo = SurveyPhoto(id:UUID(),roomID:room,number:7,pose:pose,timestamp:42)
        let records = try OrganisedPhotoIndex.records([.init(photo:photo,room:"Bath Room 2",story:1,number:1,path:"photo-01.jpg")],sourceID:source,root:root)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record["photoID"] as? String,photo.id.uuidString)
        XCTAssertEqual(record["sourceID"] as? String,source.uuidString)
        XCTAssertEqual(record["roomID"] as? String,room.uuidString)
        XCTAssertEqual(record["number"] as? Int,1)
        XCTAssertEqual(record["originalNumber"] as? Int,7)
        XCTAssertEqual(record["rawCameraPose"] as? [Double],pose)
        XCTAssertEqual(record["pos_y"] as? Double,3)
        XCTAssertTrue(record["accuracyMm"] is NSNull)
        XCTAssertTrue(record["capturedAt"] is NSNull)
        XCTAssertEqual(record["sha256"] as? String,try ExportChecksum.sha256(root.appendingPathComponent("photo-01.jpg")))
    }

    func testInvalidPoseAndEscapingPathThrowInsteadOfIndexingOutsideArrayOrRoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        var photo = SurveyPhoto(id:UUID(),number:1,pose:[],timestamp:0)
        XCTAssertThrowsError(try OrganisedPhotoIndex.records([.init(photo:photo,room:"Room",story:nil,number:1,path:"photo.jpg")],sourceID:UUID(),root:root))
        photo.pose = pose
        for path in ["../outside.jpg","/outside.jpg","room\\outside.jpg","C:/outside.jpg"] {
            XCTAssertThrowsError(try OrganisedPhotoIndex.records([.init(photo:photo,room:"Room",story:nil,number:1,path:path)],sourceID:UUID(),root:root))
        }
    }

    func testCSVRetainsLeadingColumnsEscapesTextAndDoesNotAlterNegativeCoordinates() throws {
        let data = OrganisedPhotoIndex.csv([["room":"=SUM(1,2)\"","pos_x": -2.5,"number":1]])
        let csv = try XCTUnwrap(String(data:data,encoding:.utf8))
        XCTAssertTrue(csv.hasPrefix("\"number\",\"level\",\"room\",\"file\",\"timestamp\",\"pos_x\""))
        XCTAssertTrue(csv.contains("\"'=SUM(1,2)\"\"\""))
        XCTAssertTrue(csv.contains("\"-2.5\""))
    }
}
