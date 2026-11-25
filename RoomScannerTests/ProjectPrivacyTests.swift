import XCTest
@testable import RoomScanner

final class ProjectPrivacyTests: XCTestCase {
    func testFailedSecondMoveRestoresFilesAndLeavesCatalogueUnchanged() throws {
        let fm = FileManager.default,root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at:root) }
        let refs = (0..<2).map { _ in ProjectReference(kind:.room,itemID:UUID(),library:"local") }
        let project = RenovationProject(name:"Delete",references:refs),index = ProjectIndex(projects:[])
        var saved = index; saved.projects = [project]; try ProjectIndexStore.write(saved,root:root)
        let urls = refs.map { root.appendingPathComponent("Rooms/\($0.itemID.uuidString).roomscan") }
        for url in urls { try fm.createDirectory(at:url,withIntermediateDirectories:true); try Data("keep".utf8).write(to:url.appendingPathComponent("data")) }
        var calls = 0
        XCTAssertThrowsError(try ProjectPrivacyStore.delete(index:saved,roots:["local":root],catalogueRoot:root,move:{ from,to in
            calls += 1; if calls == 2 { throw CocoaError(.fileWriteNoPermission) }
            try fm.moveItem(at:from,to:to)
        }))
        XCTAssertEqual(try ProjectIndexStore.read(root:root),saved)
        for url in urls { XCTAssertEqual(try Data(contentsOf:url.appendingPathComponent("data")),Data("keep".utf8)) }
    }
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
