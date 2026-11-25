import XCTest
@testable import RoomScanner
final class ProjectDetailsTests:XCTestCase {
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

}
