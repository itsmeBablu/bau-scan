import XCTest
import CoreGraphics
@testable import RoomScanner

final class PDFPhotoAppendixTests: XCTestCase {
    func testRoomPDFOptionAddsPhotoPageAndPreservesPlanPageSizeAndSourceBytes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = FloorPlanBuilder().build(from: SyntheticRooms.rectangularRoom().scan, name: "Room")
        let photo = SurveyPhoto(id: UUID(), roomID: plan.id, number: 1, pose: SyntheticWorkload.pose, timestamp: 1)
        let bytes = Data([0xff,0xd8,0xff,0xd9]) // invalid JPEG displays explicit unavailable-page label
        let package = root.appendingPathComponent(plan.id.uuidString + ".roomscan")
        try RoomPackage(record: RoomRecord(plan: plan), plan: plan, surveyPhotos: [photo], surveyPhotoAssets: [photo.id:bytes]).write(to: package)
        let subject = ExportSubject(record: RoomRecord(plan: plan), plan: plan, packageURL: package)
        var service = ExportService(); service.includePDFPhotos = false
        let plain = try service.export(subject, format: .pdf, to: root.appendingPathComponent("without"))
        service.includePDFPhotos = true
        let illustrated = try service.export(subject, format: .pdf, to: root.appendingPathComponent("with"))
        func pdf(_ url: URL) throws -> CGPDFDocument {
            let provider = try XCTUnwrap(CGDataProvider(data: Data(contentsOf: url) as CFData))
            return try XCTUnwrap(CGPDFDocument(provider))
        }
        let a = try pdf(plain), b = try pdf(illustrated)
        XCTAssertEqual(b.numberOfPages, a.numberOfPages + 1)
        XCTAssertEqual(a.page(at: 1)?.getBoxRect(.mediaBox), b.page(at: 1)?.getBoxRect(.mediaBox))
        XCTAssertEqual(try Data(contentsOf: package.appendingPathComponent(photo.jpegPath)), bytes)
    }

    func testNoPhotosReturnsOriginalPDFBytes() throws {
        let data = Data("unchanged".utf8)
        XCTAssertEqual(try PDFPhotoAppendix.append(to: data, sources: [], locale: Locale(identifier: "en")), data)
    }
}
