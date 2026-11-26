import XCTest
@testable import RoomScanner

final class ProjectScanRemovalTests:XCTestCase {
    func testSourceWithStudioDependencyIsKept() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let reference = ProjectReference(kind:.room,itemID:UUID(),library:"local")
        let design = ProjectReference(kind:.designRoom,itemID:reference.itemID,library:"local")
        let index = ProjectIndex(projects:[.init(name:"A",references:[reference,design])])
        try ProjectIndexStore.write(index,root:root)
        let url = StorageLocation(kind:.local,documentsURL:root).packageURL(for:reference.itemID)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        let bytes = Data("original".utf8); try bytes.write(to:url.appendingPathComponent("keep.txt"))
        let entry = ProjectLibraryEntry(reference:reference,title:"A",date:Date(),area:nil,roomCount:1,root:root,url:url)
        XCTAssertThrowsError(try ProjectScanRemoval.remove(entry,expected:index,catalogueRoot:root)) {
            XCTAssertTrue($0 is ProjectScanRemoval.Failure)
        }
        XCTAssertEqual(try Data(contentsOf:url.appendingPathComponent("keep.txt")),bytes)
        XCTAssertEqual(try ProjectIndexStore.read(root:root),index)
    }
    func testRemovalMovesOneItemToTrashAndPreservesProjectNotesAndOtherFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let reference = ProjectReference(kind:.house,itemID:UUID(),library:"local")
        var project = RenovationProject(name:"A",references:[reference]); project.notes = "Keep notes"
        var index = ProjectIndex(projects:[project]); try index.setOrganization(.init(level:0,kind:.house),for:reference)
        try ProjectIndexStore.write(index,root:root)
        let location = StorageLocation(kind:.local,documentsURL:root),url = location.housePackageURL(for:reference.itemID)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        try Data("original".utf8).write(to:url.appendingPathComponent("keep.txt"))
        let other = location.housesURL.appendingPathComponent("other.housescan")
        try FileManager.default.createDirectory(at:other,withIntermediateDirectories:true)
        let entry = ProjectLibraryEntry(reference:reference,title:"A",date:Date(),area:nil,roomCount:1,root:root,url:url)
        let removed = try ProjectScanRemoval.remove(entry,expected:index,catalogueRoot:root)
        XCTAssertTrue(removed.projects[0].references.isEmpty); XCTAssertEqual(removed.projects[0].notes,"Keep notes")
        XCTAssertNil(removed.scanOrganization?[reference.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath:url.path)); XCTAssertTrue(FileManager.default.fileExists(atPath:other.path))
        let trash = try FileManager.default.contentsOfDirectory(at:location.housesURL,includingPropertiesForKeys:nil).first { $0.lastPathComponent.hasPrefix(".removed-") }
        XCTAssertEqual(try Data(contentsOf:XCTUnwrap(trash).appendingPathComponent("keep.txt")),Data("original".utf8))
    }
    func testStaleCatalogueAndMismatchedPathCannotRemoveItem() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let reference = ProjectReference(kind:.technicalRoom,itemID:UUID(),library:"local")
        let project = RenovationProject(name:"A",references:[reference]),index = ProjectIndex(projects:[project])
        try ProjectIndexStore.write(index,root:root)
        let url = root.appendingPathComponent("TechnicalRooms/\(reference.itemID.uuidString).technicalroom")
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        _ = try ProjectIndexStore.updateNotes("Changed",projectID:project.id,expected:"",root:root)
        let entry = ProjectLibraryEntry(reference:reference,title:"A",date:Date(),area:nil,roomCount:1,root:root,url:url)
        XCTAssertThrowsError(try ProjectScanRemoval.remove(entry,expected:index,catalogueRoot:root))
        XCTAssertTrue(FileManager.default.fileExists(atPath:url.path))
        let wrong = ProjectLibraryEntry(reference:reference,title:"A",date:Date(),area:nil,roomCount:1,root:root,url:root)
        XCTAssertThrowsError(try ProjectScanRemoval.remove(wrong,expected:index,catalogueRoot:root))
    }
}
