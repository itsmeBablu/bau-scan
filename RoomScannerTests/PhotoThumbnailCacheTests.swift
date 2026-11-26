import XCTest
@testable import RoomScanner

final class PhotoThumbnailCacheTests: XCTestCase {
    func testCachedThumbnailDoesNotBypassAChangedPackageRootOrPathEscape() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:parent) }
        let root = parent.appendingPathComponent("source.roomscan"), moved = parent.appendingPathComponent("retained.roomscan")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let photo = SurveyPhoto(id:UUID(),number:1,pose:SyntheticWorkload.pose,timestamp:1)
        let target = root.appendingPathComponent(photo.jpegPath)
        try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
        try SyntheticWorkload.jpeg().write(to:target)
        let asset = ProjectPhotoAsset(reference:.init(kind:.room,itemID:UUID(),library:"local"),photo:photo,roomName:"Room",root:root,relativePath:photo.jpegPath)
        let cache = PhotoThumbnailCache()
        _ = try await cache.image(asset)
        try FileManager.default.moveItem(at:root,to:moved)
        try FileManager.default.createSymbolicLink(at:root,withDestinationURL:moved)
        do { _ = try await cache.image(asset); XCTFail("Cached data bypassed root validation") }
        catch let error as CocoaError { XCTAssertEqual(error.code,.fileReadNoPermission) }
        let outside = ProjectPhotoAsset(reference:asset.reference,photo:photo,roomName:"Room",root:moved,
                                       relativePath:"../retained.roomscan/"+photo.jpegPath)
        // A normalized path that stays inside the root is safe; an actual escape
        // outside it must fail even if the same image is already cached.
        let escape = moved.appendingPathComponent("../outside.jpg")
        XCTAssertThrowsError(try SafePackageRead.fileURL(escape,root:moved))
        XCTAssertEqual(try outside.image().jpegData,try Data(contentsOf:moved.appendingPathComponent(photo.jpegPath)))
    }
    func testDifferentPreviewSizesStaySeparateAndSourceBytesStayUntouched() async throws {
        let bytes = try SyntheticWorkload.jpeg(), original = bytes
        let cache = PhotoThumbnailCache()
        let small = try await cache.image(data:bytes,maximumPixelSize:128)
        let large = try await cache.image(data:bytes,maximumPixelSize:512)
        let repeated = try await cache.image(data:bytes,maximumPixelSize:128)
        XCTAssertEqual(max(small.width,small.height),128)
        XCTAssertEqual(max(large.width,large.height),512)
        XCTAssertEqual(small.width,repeated.width)
        XCTAssertEqual(bytes,original)
    }

    func testInvalidBytesAndUnsafeRequestedSizesAreRejected() async throws {
        let cache = PhotoThumbnailCache()
        do { _ = try await cache.image(data:Data("bad".utf8)); XCTFail("Invalid image accepted") }
        catch let error as CocoaError { XCTAssertEqual(error.code,.fileReadCorruptFile) }
        for size in [0,-1,2401] {
            do { _ = try await cache.image(data:Data([1]),maximumPixelSize:size); XCTFail("Invalid size accepted") }
            catch let error as CocoaError { XCTAssertEqual(error.code,.fileReadTooLarge) }
        }
    }

    func testLazyHouseListUsesMetadataAndOpeningDeletedJPEGFailsExplicitly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let plan = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:"Room")
        let photo = SurveyPhoto(id:UUID(),roomID:plan.id,number:1,pose:SyntheticWorkload.pose,timestamp:1)
        // Listing validates metadata and file size, not image decoding.
        let file = root.appendingPathComponent(photo.jpegPath)
        try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data([0xff,0xd8]).write(to:file)
        try RoomPackage.encoder.encode([photo]).write(to:root.appendingPathComponent("survey-photos.json"))
        let reference = ProjectReference(kind:.room,itemID:plan.id,library:"local")
        let assets = try ProjectPhotoAsset.list(from:root,house:House(room:plan),reference:reference)
        XCTAssertEqual(assets.map(\.photo.id),[photo.id])
        XCTAssertEqual(assets.first?.roomName,"Room")
        try FileManager.default.removeItem(at:file)
        XCTAssertThrowsError(try assets[0].image())
    }
}
