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
    func testDeletionRemovesOnlySelectedIndexedDataAndUsesLatestCatalogue() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let location = StorageLocation(kind:.local,documentsURL:root); try location.prepare()
        let ref = ProjectReference(kind:.room,itemID:UUID(),library:"local")
        let project = RenovationProject(name:"Delete",references:[ref])
        let keep = RenovationProject(name:"Keep")
        let index = ProjectIndex(projects:[project,keep]); try ProjectIndexStore.write(index,root:root)
        let package = location.packageURL(for:ref.itemID)
        try FileManager.default.createDirectory(at:package,withIntermediateDirectories:true)
        let unrelated = root.appendingPathComponent("leave.txt"); try Data("keep".utf8).write(to:unrelated)
        let result = try ProjectPrivacyStore.delete(index:index,roots:["local":root],catalogueRoot:root,projectID:project.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath:package.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath:unrelated.path))
        XCTAssertEqual(result.projects.map(\.id),[keep.id])
        XCTAssertThrowsError(try ProjectPrivacyStore.delete(index:index,roots:["local":root],catalogueRoot:root))
    }
}
