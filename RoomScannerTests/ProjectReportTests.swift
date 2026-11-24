import XCTest
import CoreGraphics
@testable import RoomScanner

final class ProjectReportTests: XCTestCase {
    func testReportContainsCoverPlanAndRoomSchedule() throws {
        let house = HouseBuilder().build(from:SyntheticRooms.twoRoomApartment(),name:"Survey")
        let report = ProjectReport(name:"Hauptstraße 5",generatedAt:Date(timeIntervalSince1970:0),notes:"Verify opening sizes",scans:[.init(title:"Flat",house:house,detailLines:[])],photos:[],unresolved:["Missing source"])
        let data = try ProjectReportRenderer.pdf(report,locale:Locale(identifier:"de_DE"))
        let provider = try XCTUnwrap(CGDataProvider(data:data as CFData))
        let pdf = try XCTUnwrap(CGPDFDocument(provider))
        XCTAssertEqual(pdf.numberOfPages,5) // cover, notes, plan, rooms, unresolved
    }
}
