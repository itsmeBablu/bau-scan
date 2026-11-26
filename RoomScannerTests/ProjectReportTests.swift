import XCTest
import CoreGraphics
@testable import RoomScanner

final class ProjectReportTests: XCTestCase {
    func testPDFPhotoPagesCanBeExcludedWithoutChangingTheReportEvidence() throws {
        let report = ProjectReport(name: "Survey", generatedAt: Date(), notes: "", scans: [],
                                   photos: [.init(number: 1, room: "Plant room", jpeg: Data())], unresolved: [])
        func pages(_ include: Bool) throws -> Int {
            let data = try ProjectReportRenderer.pdf(report, locale: Locale(identifier: "en"), includePhotos: include)
            let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
            return try XCTUnwrap(CGPDFDocument(provider)).numberOfPages
        }
        XCTAssertEqual(try pages(true), try pages(false) + 1)
        XCTAssertEqual(report.photos.count, 1)
    }

    func testPDFPhotoOptionChangesReuseIdentityAndLegacyRequestStillDecodes() async throws {
        let project = RenovationProject(name: "Survey"), index: ProjectIndex
        index = ProjectIndex(projects: [project])
        let a = try await ProjectExportRequest.make(project: project, index: index, entries: [], kind: .report,
                                                     locale: Locale(identifier: "en"), unit: .meters, includeDetails: false, wastePercent: 0, includePhotos: true)
        let b = try await ProjectExportRequest.make(project: project, index: index, entries: [], kind: .report,
                                                     locale: Locale(identifier: "en"), unit: .meters, includeDetails: false, wastePercent: 0, includePhotos: false)
        XCTAssertNotEqual(try a.key(), try b.key())
        XCTAssertEqual(a.metadataDigest, b.metadataDigest)
        var legacy = a; legacy.generatorRevision = 1
        let reopened = try JSONDecoder().decode(ProjectExportRequest.self, from: ProjectExportRequest.encode(legacy))
        try reopened.validate()
        XCTAssertEqual(legacy, reopened)
    }
    func testQuantitiesCSVIncludesIndependentRoomHeightRangeInExcelColumns() {
        var room = FloorPlanBuilder().build(from: SyntheticRooms.rectangularRoom().scan, name: "Bath Room")
        room.ceilingHeight = 2.35...2.70
        let report = ProjectReport(name: "Survey", generatedAt: Date(), notes: "",
                                   scans: [.init(title: "Floor", house: House(room: room), detailLines: [])], photos: [], unresolved: [])
        for locale in [Locale(identifier: "en_US"), Locale(identifier: "de_DE")] {
            let text = String(decoding: ProjectQuantitiesCSV.data(report, locale: locale), as: UTF8.self)
            let rows = text.components(separatedBy: "\r\n")
            let header = rows[0].components(separatedBy: ";")
            let values = rows[1].components(separatedBy: ";")
            XCTAssertEqual(header.count, values.count)
            XCTAssertTrue(header[6].contains(AppLanguage.text("Height min (m)", locale: locale)))
            XCTAssertTrue(header[7].contains(AppLanguage.text("Height max (m)", locale: locale)))
            XCTAssertEqual(values[6], "\"" + String(format: "%.3f", locale: locale, 2.35) + "\"")
            XCTAssertEqual(values[7], "\"" + String(format: "%.3f", locale: locale, 2.70) + "\"")
            XCTAssertTrue(text.hasPrefix("\u{FEFF}"), "Keep Excel UTF-8 BOM")
        }
        XCTAssertEqual(RenovationQuantities(room).floorArea, 12, accuracy: 0.001)
    }
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
