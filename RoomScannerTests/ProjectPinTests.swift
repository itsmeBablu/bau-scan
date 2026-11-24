import XCTest
@testable import RoomScanner

final class ProjectPinTests: XCTestCase {
    func testPinsAreAdditiveAndRetainSourceCoordinates() throws {
        let reference = ProjectReference(kind:.house,itemID:UUID(),library:"local")
        let project = RenovationProject(name:"Flat",references:[reference])
        let pin = ProjectPin(projectID:project.id,reference:reference,story:2,position:.init(x:2.4,y:-1.2),text:"Replace window")
        var index = ProjectIndex(projects:[project]); index.pins = [pin]
        try index.validate()
        XCTAssertEqual(try JSONDecoder().decode(ProjectIndex.self,from:JSONEncoder().encode(index)).pins,[pin])
        index.projects = []
        XCTAssertThrowsError(try index.validate())
    }
}
