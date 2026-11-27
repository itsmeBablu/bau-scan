import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import RoomScanner

final class TechnicalMEPRecognitionTests: XCTestCase {
    private func cylinder(offset: Double = 0,lo: Double = 0,hi: Double = 1) -> [TechnicalMEPFitter.Sample] {
        (0...24).flatMap { y in
            (0..<24).map { angle in
                let theta = Double(angle)*2 * Double.pi/24
                return TechnicalMEPFitter.Sample(point: .init(x: offset+0.05*cos(theta),y: lo+(hi-lo)*Double(y)/24,z: 0.05*sin(theta)),
                    normal: .init(x: cos(theta),y: 0,z: sin(theta)),color: .init(x: 0.7,y: 0.2,z: 0.1))
            }
        }
    }
    private func keyframe(id: UUID = UUID(),photo: Bool = false,striped: Bool = false) throws -> TechnicalCaptureKeyframe {
        let width = 16,height = 12
        var bytes = [UInt8](repeating: 120,count: width*height*4)
        if striped {
            for y in 0..<height {
                for x in 0..<width {
                    let i = (y*width+x)*4
                    bytes[i] = y < height/2 ? 255 : 0; bytes[i+1] = 0; bytes[i+2] = y < height/2 ? 0 : 255
                }
            }
        }
        let image = try XCTUnwrap(bytes.withUnsafeMutableBytes { buffer -> CGImage? in
            let context = CGContext(data: buffer.baseAddress,width: width,height: height,bitsPerComponent: 8,bytesPerRow: width*4,
                space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            return context?.makeImage()
        })
        let data = NSMutableData()
        let target = try XCTUnwrap(CGImageDestinationCreateWithData(data,UTType.jpeg.identifier as CFString,1,nil))
        CGImageDestinationAddImage(target,image,nil); XCTAssertTrue(CGImageDestinationFinalize(target))
        let depth = TechnicalDepthSnapshot(timestamp: 1,width: width,height: height,imageWidth: width,imageHeight: height,
            cameraTransform: [1,0,0,0,0,1,0,0,0,0,1,0,2,3,4,1],intrinsics: [10,0,0,0,10,0,8,6,1],
            depthMetres: Array(repeating: 1,count: width*height),confidence: Array(repeating: 2,count: width*height),alignmentVerified: false)
        return .init(id: id,jpegData: data as Data,jpegWidth: width,jpegHeight: height,depth: depth,userPhoto: photo)
    }
    func testFindsCylinderWithoutInventingAnEngineeringAccuracy() throws {
        let result = try TechnicalMEPFitter.detect(cylinder())
        let item = try XCTUnwrap(result.first)
        XCTAssertEqual(item.width,0.1,accuracy: 0.005)
        XCTAssertGreaterThan(item.length,0.9)
        XCTAssertEqual(item.status,.proposed)
        XCTAssertNil(item.accuracyMm)
        XCTAssertNil(item.modelScore)
        XCTAssertEqual(try XCTUnwrap(item.color).x,0.7,accuracy: 1e-9)
    }
    func testFitsAnObliqueCylinderAndSeparatesUnsupportedGaps() throws {
        let input = cylinder(lo: 0,hi: 0.6)+cylinder(lo: 1,hi: 1.6)
        let rotated = input.map { sample -> TechnicalMEPFitter.Sample in
            func rotate(_ p: TechnicalPoint3) -> TechnicalPoint3 { .init(x: (p.x-p.y)/sqrt(2),y: (p.x+p.y)/sqrt(2),z: p.z) }
            return .init(point: rotate(sample.point),normal: rotate(sample.normal),color: sample.color)
        }
        let result = try TechnicalMEPFitter.detect(rotated)
        XCTAssertGreaterThanOrEqual(result.count,2)
        XCTAssertTrue(result.allSatisfy { $0.length < 0.8 })
    }
    func testPlaneAndSparseNoiseDoNotBecomePipes() throws {
        let plane = (0..<100).map { i in TechnicalMEPFitter.Sample(point: .init(x: Double(i%10)*0.1,y: 0,z: Double(i/10)*0.1),normal: .init(x: 0,y: 1,z: 0),color: nil) }
        XCTAssertTrue(try TechnicalMEPFitter.detect(plane).isEmpty)
        XCTAssertTrue(try TechnicalMEPFitter.detect(Array(cylinder().prefix(10))).isEmpty)
    }
    func testTwoVisibleDuctFacesProduceAnEstimatedPrism() throws {
        var points: [TechnicalMEPFitter.Sample] = []
        for along in 0...30 {
            for cross in 0...15 {
                let y = Double(along)/15, t = Double(cross)/15
                points.append(.init(point: .init(x: 0.2,y: y,z: -0.1+t*0.2),normal: .init(x: 1,y: 0,z: 0),color: nil))
                points.append(.init(point: .init(x: -0.2+t*0.4,y: y,z: 0.1),normal: .init(x: 0,y: 0,z: 1),color: nil))
            }
        }
        let result = try TechnicalMEPFitter.detect(points,kind: .rectangularDuct,evidenceIDs: [UUID()],modelScore: nil)
        let duct = try XCTUnwrap(result.first)
        XCTAssertEqual(duct.width*duct.height,0.08,accuracy: 0.015)
        XCTAssertGreaterThan(duct.length,1.8)
        XCTAssertEqual(duct.kind,.rectangularDuct)
    }
    func testRejectedObjectsAreNotReintroducedByAnotherRun() throws {
        var item = try XCTUnwrap(TechnicalMEPFitter.detect(cylinder()).first)
        var review = TechnicalMEPReview(); review.merge([item])
        review.suggestions[0].status = .rejected
        item.id = UUID(); review.merge([item])
        XCTAssertEqual(review.suggestions.count,1)
        XCTAssertEqual(review.suggestions[0].status,.rejected)
        try review.validate()
    }
    func testMaskRLERejectsWrongDimensionsOverflowAndWrongLength() throws {
        let valid = TechnicalMEPMaskResponse.Instance(kind: .pipe,score: nil,width: 16,height: 12,runs: [0,192])
        XCTAssertEqual(try valid.pixels(expectedWidth: 16,expectedHeight: 12).filter { $0 }.count,192)
        for runs in [[-1,193],[0,Int.max],[192,1],[10]] {
            var mask = valid; mask.runs = runs
            XCTAssertThrowsError(try mask.pixels(expectedWidth: 16,expectedHeight: 12))
        }
        XCTAssertThrowsError(try valid.pixels(expectedWidth: 12,expectedHeight: 16))
    }
    func testDepthMaskProjectionUsesCameraPoseAndRejectsLowConfidence() throws {
        let frame = try keyframe()
        let mask = Array(repeating: true,count: 192)
        let points = try TechnicalMEPDepthPoints.samples(frame: frame,mask: mask)
        XCTAssertFalse(points.isEmpty)
        XCTAssertTrue(points.allSatisfy { abs($0.point.z-3) < 0.0001 })
        XCTAssertTrue(points.allSatisfy { $0.point.x > 1 && $0.point.y > 2 })
        var low = frame
        let d = frame.depth
        low.depth = .init(timestamp: d.timestamp,width: d.width,height: d.height,imageWidth: d.imageWidth,imageHeight: d.imageHeight,
            cameraTransform: d.cameraTransform,intrinsics: d.intrinsics,depthMetres: d.depthMetres,confidence: Array(repeating: 0,count: 192),alignmentVerified: false)
        XCTAssertTrue(try TechnicalMEPDepthPoints.samples(frame: low,mask: mask).isEmpty)
    }
    func testEvidenceRetentionPinsUserPhotosAndValidatesPrivateLinks() throws {
        var evidence = TechnicalCaptureEvidence()
        let photo = try keyframe(photo: true)
        try evidence.append(photo)
        for _ in 0..<35 { try evidence.append(keyframe()) }
        XCTAssertEqual(evidence.keyframes.count,32)
        XCTAssertTrue(evidence.keyframes.contains { $0.id == photo.id })
        XCTAssertEqual(evidence.droppedKeyframes,4)
        XCTAssertThrowsError(try evidence.setGooglePhotosURL(URL(string: "https://example.com/photo")!,for: photo.id))
        try evidence.setGooglePhotosURL(URL(string: "https://photos.google.com/photo/example")!,for: photo.id)
        try evidence.validate()
        var manifest = evidence.withoutImageBytes()
        XCTAssertTrue(manifest.keyframes.allSatisfy { $0.jpegData.isEmpty })
        try manifest.restoreImages { _ in photo.jpegData }
        try manifest.validate()
    }
    func testGoogleAIConfigurationRequiresOAuthIDsAndRegisteredRedirectScheme() async {
        await MainActor.run {
            XCTAssertFalse(TechnicalGoogleAIAccount.configurationIsValid(client: "",server: "",schemes: []))
            XCTAssertFalse(TechnicalGoogleAIAccount.configurationIsValid(client: "native.apps.googleusercontent.com",server: "server.apps.googleusercontent.com",schemes: []))
            XCTAssertTrue(TechnicalGoogleAIAccount.configurationIsValid(client: "native.apps.googleusercontent.com",server: "server.apps.googleusercontent.com",schemes: ["com.googleusercontent.apps.native"]))
        }
    }
    func testPackageRoundTripRetainsPhotosCalibrationAndRecognitionWithoutRequiringARMap() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mep-package-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let room = TechnicalRoom.capturedShell(id: UUID(),notes: "")
        var package = TechnicalRoomPackage(manifest: .init(id: room.id,name: "MEP fixture"),document: .init(room: room),
            alignment: .init(),journal: .init(),worldMapData: nil,thumbnailPNG: nil)
        let photo = try keyframe(photo: true)
        try package.evidence.append(photo)
        package.recognition.merge(try TechnicalMEPFitter.detect(cylinder()))
        let url = directory.appendingPathComponent("fixture.technicalroom")
        try package.write(to: url)
        let reopened = try TechnicalRoomPackage.read(from: url)
        XCTAssertEqual(reopened.evidence,package.evidence)
        XCTAssertEqual(reopened.recognition,package.recognition)
        XCTAssertNil(reopened.worldMapData)
        let bytes = try Data(contentsOf: url.appendingPathComponent("capture-images/\(photo.id.uuidString).jpg"))
        XCTAssertEqual(bytes,photo.jpegData)
        let metadata = try JSONDecoder().decode(TechnicalCaptureEvidence.self,from: Data(contentsOf: url.appendingPathComponent("evidence.json")))
        XCTAssertTrue(metadata.keyframes[0].jpegData.isEmpty)
        try FileManager.default.removeItem(at: url.appendingPathComponent("evidence.json"))
        try FileManager.default.removeItem(at: url.appendingPathComponent("recognition.json"))
        let legacy = try TechnicalRoomPackage.read(from: url)
        XCTAssertTrue(legacy.evidence.keyframes.isEmpty)
        XCTAssertTrue(legacy.recognition.suggestions.isEmpty)
    }
    func testInvalidCameraCalibrationCannotProduceAKeyframe() throws {
        var frame = try keyframe()
        let d = frame.depth
        frame.depth = .init(timestamp: d.timestamp,width: d.width,height: d.height,imageWidth: d.imageWidth,imageHeight: d.imageHeight,
            cameraTransform: Array(repeating: 0,count: 16),intrinsics: d.intrinsics,depthMetres: d.depthMetres,confidence: d.confidence,alignmentVerified: false)
        XCTAssertThrowsError(try frame.validate())
    }
    func testJPEGColorSamplingKeepsNativeImageRowsAlignedWithDepth() throws {
        let colors = try TechnicalMEPClient.imageColors(keyframe(striped: true))
        XCTAssertGreaterThan(try XCTUnwrap(colors.first!).x,0.8)
        XCTAssertLessThan(try XCTUnwrap(colors.first!).z,0.2)
        XCTAssertGreaterThan(try XCTUnwrap(colors.last!).z,0.8)
    }
    func testOnlyAcceptedMEPObjectsProduceDerivedExportGeometry() throws {
        let item = try XCTUnwrap(TechnicalMEPFitter.detect(cylinder()).first)
        var review = TechnicalMEPReview(suggestions: [item])
        XCTAssertTrue(try TechnicalMEPMeshBuilder.snapshot(review).patches.isEmpty)
        review.suggestions[0].status = .accepted
        let snapshot = try TechnicalMEPMeshBuilder.snapshot(review)
        let mesh = try TechnicalSavedMeshGeometry(snapshot: snapshot,reference: nil)
        XCTAssertEqual(snapshot.patches.count,1)
        XCTAssertGreaterThan(mesh.triangleIndices.count,100)
        XCTAssertEqual(mesh.extent.y,item.length,accuracy: 0.001)
        XCTAssertEqual(mesh.extent.x,item.width,accuracy: 0.001)
        review.suggestions[0].status = .rejected
        XCTAssertTrue(try TechnicalMEPMeshBuilder.snapshot(review).patches.isEmpty)
    }
    func testAIARModeFeatureFlagDefaultsOff() {
        XCTAssertFalse(FeatureFlags.aiARMode)
    }
}
