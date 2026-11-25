import XCTest
@testable import RoomScanner

final class TechnicalExportLinkTests: XCTestCase {
    func testSameNameSurveysRequireExplicitIdentity() {
        let root = FileManager.default.temporaryDirectory
        let a = TechnicalRoomManifest(id:UUID(),name:"Utility"),b = TechnicalRoomManifest(id:UUID(),name:"Utility")
        var options = OrganisedExportService.Options()
        XCTAssertNil(OrganisedExportService.technicalRoomURL(options:options,storageRoot:root))
        options.technicalRoomID = b.id
        let url = OrganisedExportService.technicalRoomURL(options:options,storageRoot:root)
        XCTAssertEqual(url?.deletingPathExtension().lastPathComponent,b.id.uuidString)
        XCTAssertNotEqual(url?.deletingPathExtension().lastPathComponent,a.id.uuidString)
        options.includeTechnicalRoom = false
        XCTAssertNil(OrganisedExportService.technicalRoomURL(options:options,storageRoot:root))
        options.includeTechnicalRoom = true; options.additionalTechnicalRoomIDs = [a.id,b.id]
        XCTAssertEqual(Set(OrganisedExportService.selectedTechnicalRoomIDs(options:options)),Set([a.id,b.id]))
        options.photosOnly = true
        XCTAssertTrue(OrganisedExportService.selectedTechnicalRoomIDs(options:options).isEmpty)
    }
}
