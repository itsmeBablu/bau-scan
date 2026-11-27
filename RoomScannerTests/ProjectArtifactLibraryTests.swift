import XCTest
@testable import RoomScanner

final class ProjectArtifactLibraryTests:XCTestCase {
    func testRenameAndDeleteRollBackWhenTheirIndexCannotBeRead() throws {
        for rename in [true,false] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at:root) }
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            let project = UUID(),source = root.appendingPathComponent("source.csv"),bytes = Data("survey quantities".utf8)
            try bytes.write(to:source)
            let request = ProjectExportRequest(projectID:project,kind:.quantities,metadataDigest:String(repeating:"a",count:64),sourceRevision:String(repeating:"b",count:64),locale:"en",unit:.meters,includeDetails:false,wastePercent:10)
            let saved = try ProjectArtifactIndex.publish(source,request:request,projectName:"Survey",root:root)
            let folder = ProjectArtifacts.directory(root:root,projectID:project)
            let index = folder.appendingPathComponent(".artifact-index-v1.json")
            let valid = try Data(contentsOf:index),corrupt = Data("interrupted or unavailable index".utf8)
            try corrupt.write(to:index,options:.atomic)
            if rename {
                XCTAssertThrowsError(try ProjectArtifacts.rename(saved,to:"Updated schedule",root:root,projectID:project))
            } else {
                XCTAssertThrowsError(try ProjectArtifacts.remove(saved,root:root,projectID:project))
            }
            XCTAssertEqual(try Data(contentsOf:saved),bytes)
            XCTAssertEqual(try Data(contentsOf:source),bytes)
            XCTAssertEqual(try Data(contentsOf:index),corrupt)
            XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath:folder.path)),Set([saved.lastPathComponent,index.lastPathComponent]))
            // Restoring only this disposable fixture's index permits a normal retry.
            try valid.write(to:index,options:.atomic)
            if rename {
                let revised = try ProjectArtifacts.rename(saved,to:"Updated schedule",root:root,projectID:project)
                XCTAssertEqual(try ProjectArtifactIndex.lookup(request,root:root),revised)
                XCTAssertEqual(try Data(contentsOf:revised),bytes)
            } else {
                try ProjectArtifacts.remove(saved,root:root,projectID:project)
                XCTAssertFalse(FileManager.default.fileExists(atPath:saved.path))
                XCTAssertNil(try ProjectArtifactIndex.lookup(request,root:root))
            }
        }
    }

    func testCategoriesAndSupportedFilesPreserveLegacyExports() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let project = UUID()
        let legacy = try ProjectArtifacts.save(Data("report".utf8),extension:"pdf",root:root,projectID:project)
        let cad = try ProjectArtifacts.save(Data("ifc".utf8),extension:"ifc",root:root,projectID:project)
        _ = try ProjectArtifacts.save(Data("mesh".utf8),extension:"glb",root:root,projectID:project)
        let files = try ProjectArtifacts.inspect(root:root,projectID:project)
        XCTAssertEqual(files.count,3)
        XCTAssertEqual(files.first { $0.url.resolvingSymlinksInPath() == legacy.resolvingSymlinksInPath() }?.category,.reports)
        XCTAssertEqual(files.first { $0.url.resolvingSymlinksInPath() == cad.resolvingSymlinksInPath() }?.category,.cad)
        XCTAssertTrue(try XCTUnwrap(files.first { $0.url.resolvingSymlinksInPath() == legacy.resolvingSymlinksInPath() }).legacy)
        XCTAssertEqual(try Data(contentsOf:legacy),Data("report".utf8))
        XCTAssertEqual(ProjectArtifactCategory.category(URL(fileURLWithPath:"A-Photos.zip")),.photos)
        XCTAssertEqual(ProjectArtifactCategory.category(URL(fileURLWithPath:"A-Complete.zip")),.archives)
    }
    func testRenamePreservesExtensionRejectsOverwriteAndDeleteCannotReachSourceScan() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let project = UUID(),bytes = Data("report".utf8)
        let first = try ProjectArtifacts.save(bytes,extension:"pdf",root:root,projectID:project)
        let second = try ProjectArtifacts.save(Data("keep".utf8),extension:"pdf",root:root,projectID:project)
        let renamed = try ProjectArtifacts.rename(first,to:"Room schedule",root:root,projectID:project)
        XCTAssertEqual(renamed.lastPathComponent,"Room schedule.pdf")
        XCTAssertEqual(try Data(contentsOf:renamed),bytes)
        XCTAssertThrowsError(try ProjectArtifacts.rename(second,to:"room schedule",root:root,projectID:project))
        let source = root.appendingPathComponent("source.roomscan")
        try bytes.write(to:source)
        XCTAssertThrowsError(try ProjectArtifacts.remove(source,root:root,projectID:project))
        try ProjectArtifacts.remove(renamed,root:root,projectID:project)
        XCTAssertFalse(FileManager.default.fileExists(atPath:renamed.path))
        XCTAssertEqual(try Data(contentsOf:source),bytes)
        XCTAssertEqual(try Data(contentsOf:second),Data("keep".utf8))
    }
    func testSymlinkArtifactCannotBeRenamedOrDeleted() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let project = UUID(),outside = root.appendingPathComponent("source.pdf")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        try Data("source".utf8).write(to:outside)
        let directory = ProjectArtifacts.directory(root:root,projectID:project)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let link = directory.appendingPathComponent("linked.pdf")
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:outside)
        XCTAssertTrue(try ProjectArtifacts.inspect(root:root,projectID:project).isEmpty)
        XCTAssertThrowsError(try ProjectArtifacts.rename(link,to:"Moved",root:root,projectID:project))
        XCTAssertThrowsError(try ProjectArtifacts.remove(link,root:root,projectID:project))
        XCTAssertEqual(try Data(contentsOf:outside),Data("source".utf8))
    }
}
