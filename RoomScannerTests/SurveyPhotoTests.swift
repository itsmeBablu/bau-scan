import XCTest
@testable import RoomScanner

final class SurveyPhotoTests: XCTestCase {
    private let identity: [Double] = [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
    private func photo(room: UUID? = nil) -> SurveyPhoto {
        .init(id:UUID(),roomID:room,number:99,pose:identity,timestamp:2,capturedAt:Date(timeIntervalSince1970:100))
    }
    func testNumberingRestartsInEachRoomEvenWhenRevisited() {
        let a = UUID(),b = UUID()
        let photos = SurveyPhoto.numbered([photo(room:a),photo(room:b),photo(room:a),photo(room:b),photo(room:a)])
        XCTAssertEqual(photos.map(\.number),[1,1,2,2,3])
        XCTAssertEqual(photos.map(\.roomID),[a,b,a,b,a])
    }
    func testPhotoRoundTripRetainsPosePathAndPendingStatus() throws {
        let original = photo(room:UUID())
        let data = try RoomPackage.encoder.encode(original)
        let decoded = try RoomPackage.decoder.decode(SurveyPhoto.self,from:data)
        XCTAssertEqual(original,decoded)
        XCTAssertTrue(decoded.deviceValidationPending)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        XCTAssertEqual(json["jpegPath"] as? String,original.jpegPath)
    }
    func testTransformsTranslatePositionAndRotateAllCameraAxes() throws {
        var pose = identity
        pose[12] = 2; pose[13] = 3; pose[14] = 5
        let t = TechnicalTransform(translation:.init(x:10,y:-1,z:4),xAxis:.init(x:0,y:0,z:-1),
                                   yAxis:.init(x:0,y:1,z:0),zAxis:.init(x:1,y:0,z:0))
        let transformed = SurveyPhoto.transformedPose(pose,by:t)
        XCTAssertEqual(Array(transformed[12...14]),[15,2,2])
        XCTAssertEqual(Array(transformed[0...2]),[0,0,-1])
        XCTAssertEqual(Array(transformed[8...10]),[1,0,0])
        var record = photo()
        record.displayPose = transformed
        XCTAssertNoThrow(try record.validate())
    }
    func testSettingsGatesCameraButtonAndPerformanceCaps() {
        XCTAssertTrue(ScanPhotoPolicy.buttonVisible(enabled:true,cameraRunning:true))
        XCTAssertFalse(ScanPhotoPolicy.buttonVisible(enabled:false,cameraRunning:true))
        XCTAssertFalse(ScanPhotoPolicy.buttonVisible(enabled:true,cameraRunning:false))
        XCTAssertFalse(ScanPhotoPolicy.buttonVisible(enabled:false,cameraRunning:false))
        XCTAssertLessThan(ScanPerformance.performance.previewVertices,ScanPerformance.balanced.previewVertices)
        XCTAssertLessThan(ScanPerformance.balanced.previewTriangles,ScanPerformance.quality.previewTriangles)
    }
    func testOptionalPhotoSidecarLegacyReadRoundTripAndUnsafePath() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        XCTAssertNil(try SurveyPhotoStore.read(from:root).photos)
        let record = photo()
        let bytes = Data([0xff,0xd8,0xff,0xd9])
        try SurveyPhotoStore.write([record],assets:[record.id:bytes],to:root)
        let read = try SurveyPhotoStore.read(from:root)
        XCTAssertEqual(read.photos,[record])
        XCTAssertEqual(read.assets[record.id],bytes)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with:RoomPackage.encoder.encode(record)) as? [String:Any])
        json["jpegPath"] = "../private.jpg"
        XCTAssertThrowsError(try RoomPackage.decoder.decode(SurveyPhoto.self,from:JSONSerialization.data(withJSONObject:json)))
    }
    func testRejectsInvalidCameraFrame() {
        var record = photo()
        record.pose[0] = -1
        XCTAssertThrowsError(try record.validate())
        record = photo()
        record.pose[12] = .nan
        XCTAssertThrowsError(try record.validate())
    }
}
