import XCTest
import CoreGraphics
@testable import RoomScanner

final class ProjectReportTests: XCTestCase {
    func testExportedCatalogueOmitsOtherProjectOrganization() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let selected = ProjectReference(kind:.house,itemID:UUID(),library:"local")
        let other = ProjectReference(kind:.technicalRoom,itemID:UUID(),library:"local")
        let project = RenovationProject(name:"A",references:[selected])
        var index = ProjectIndex(projects:[project,.init(name:"B",references:[other])])
        try index.setOrganization(.init(level:0,kind:.house),for:selected)
        try index.setOrganization(.init(level:-1,kind:.technicalRoom),for:other)
        try await ProjectBundleExporter.files(project:project,index:index,entries:[],locale:Locale(identifier:"en"),in:root)
        let exported = try JSONDecoder().decode(ProjectIndex.self,from:Data(contentsOf:root.appendingPathComponent("project-index.json")))
        try exported.validate()
        XCTAssertEqual(exported.projects.map(\.id),[project.id])
        XCTAssertEqual(Set(exported.scanOrganization?.keys.map { $0 } ?? []),[selected.id])
    }
    func testReportContainsCoverPlanAndRoomSchedule() throws {
        let house = try HouseBuilder().build(from:SyntheticRooms.twoRoomApartment(),name:"Survey")
        let report = ProjectReport(name:"Hauptstraße 5",generatedAt:Date(timeIntervalSince1970:0),notes:"Verify opening sizes",scans:[.init(title:"Flat",house:house,detailLines:[])],photos:[],unresolved:["Missing source"])
        let data = try ProjectReportRenderer.pdf(report,locale:Locale(identifier:"de_DE"))
        let provider = try XCTUnwrap(CGDataProvider(data:data as CFData))
        let pdf = try XCTUnwrap(CGPDFDocument(provider))
        XCTAssertEqual(pdf.numberOfPages,5) // cover, notes, plan, rooms, unresolved
    }
}
