import XCTest
@testable import RoomScanner

final class ProjectPrivacyTests: XCTestCase {
    func testDeletePreflightProtectsSourcesUsedByAnotherProjectAndRejectsOfflineCloud() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let scan = ProjectReference(kind:.house,itemID:UUID(),library:"local")
        let design = ProjectReference(kind:.designHouse,itemID:scan.itemID,library:"local")
        let a = RenovationProject(name:"A",references:[scan]), b = RenovationProject(name:"B",references:[design])
        var index = ProjectIndex(projects:[a,b])
        let targets = try ProjectPrivacyStore.deletionTargets(index:index,roots:["local":root],catalogueRoot:root,projectID:a.id)
        XCTAssertFalse(targets.contains { $0.pathExtension == "housescan" })
        index.projects[0].references[0].library = "icloud"
        XCTAssertThrowsError(try ProjectPrivacyStore.deletionTargets(index:index,roots:["local":root],catalogueRoot:root))
    }
}
