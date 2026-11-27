import XCTest
@testable import RoomScanner
final class ProjectDetailsTests:XCTestCase {
    func testCoordinatedDetailsSaveRejectsStaleDraftAndReloadsFromDisk() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let project = RenovationProject(name:"Old")
        try ProjectIndexStore.write(.init(projects:[project]),root:root)
        let first = ProjectDetails(city:"Berlin")
        _ = try ProjectIndexStore.updateDetails(first,projectID:project.id,expected:nil,root:root)
        let latest = try ProjectIndexStore.read(root:root).projects[0].details
        XCTAssertEqual(latest,first)
        XCTAssertThrowsError(try ProjectIndexStore.updateDetails(.init(city:"Hamburg"),projectID:project.id,expected:nil,root:root)) {
            XCTAssertTrue($0 is ProjectIndexStore.DetailsConflict)
        }
        XCTAssertEqual(try ProjectIndexStore.read(root:root).projects[0].details,first)
        // Idempotent retry of the same content is safe, even with the original baseline.
        _ = try ProjectIndexStore.updateDetails(first,projectID:project.id,expected:nil,root:root)
        _ = try ProjectIndexStore.updateDetails(.init(city:"Hamburg"),projectID:project.id,expected:latest,root:root)
        XCTAssertEqual(try ProjectIndexStore.read(root:root).projects[0].details?.city,"Hamburg")
    }
    func testDetailsSaveCannotResurrectDeletedProjectOrWriteInvalidDetails() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let project = RenovationProject(name:"A")
        try ProjectIndexStore.write(.init(projects:[project]),root:root)
        XCTAssertThrowsError(try ProjectIndexStore.updateDetails(.init(city:String(repeating:"x",count:4001)),projectID:project.id,expected:nil,root:root))
        XCTAssertNil(try ProjectIndexStore.read(root:root).projects[0].details)
        _ = try ProjectIndexStore.update(root:root) { $0.projects.removeAll() }
        XCTAssertThrowsError(try ProjectIndexStore.updateDetails(.init(city:"Berlin"),projectID:project.id,expected:nil,root:root))
        XCTAssertTrue(try ProjectIndexStore.read(root:root).projects.isEmpty)
    }
    func testOptionalDetailsKeepOldProjectsReadable() throws {
        let project = RenovationProject(name:"Old")
        let bytes = try JSONEncoder().encode(project)
        XCTAssertNil(try JSONDecoder().decode(RenovationProject.self,from:bytes).details)
        let empty = try JSONDecoder().decode(ProjectDetails.self,from:Data("{}".utf8))
        XCTAssertTrue(empty.valid)
        var edited = project
        edited.details = .init(street:"Straße 5",postcode:"10115",city:"Berlin",parties:[.init(role:"Architect",name:"Anna",email:"a@example.test")])
        XCTAssertEqual(try JSONDecoder().decode(RenovationProject.self,from:JSONEncoder().encode(edited)),edited)
        edited.details?.parties = [ProjectParty(name:String(repeating:"x",count:4001))]
        XCTAssertFalse(edited.details!.valid)
    }
    func testBundleDetailsAreOptIn() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        var project = RenovationProject(name:"Private")
        project.details = .init(street:"Private address",parties:[.init(name:"Private contact")])
        let index = ProjectIndex(projects:[project]),a = root.appendingPathComponent("a"),b = root.appendingPathComponent("b")
        try await ProjectBundleExporter.files(project:project,index:index,entries:[],locale:Locale(identifier:"en"),in:a)
        XCTAssertFalse(FileManager.default.fileExists(atPath:a.appendingPathComponent("project-details.json").path))
        try await ProjectBundleExporter.files(project:project,index:index,entries:[],locale:Locale(identifier:"en"),in:b,includeDetails:true)
        XCTAssertEqual(try JSONDecoder().decode(ProjectDetails.self,from:Data(contentsOf:b.appendingPathComponent("project-details.json"))),project.details)
    }

    func testFlexibleFloorsAndContactsRoundTripWithoutRequiringNewFieldsInOldData() throws {
        var details = ProjectDetails(floorNames:[-1:"Plant room",0:"Entrance",1:"Offices"],parties:[.init(role:"Architect",name:"Anna",company:"Practice",branch:"Berlin",address:"Example street",website:"https://example.test",phone:"123",email:"a@example.test")])
        XCTAssertTrue(details.valid)
        XCTAssertEqual(try JSONDecoder().decode(ProjectDetails.self,from:JSONEncoder().encode(details)),details)
        let old = try JSONDecoder().decode(ProjectParty.self,from:Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"name\":\"Legacy\"}".utf8))
        XCTAssertNil(old.branch); XCTAssertNil(old.address); XCTAssertNil(old.website)
        details.floorNames?[1] = "   "
        XCTAssertFalse(details.valid)
        details.floorNames?[1] = "Offices"
        details.parties?[0].website = String(repeating:"x",count:4001)
        XCTAssertFalse(details.valid)
    }

}
