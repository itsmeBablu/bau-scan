import XCTest
@testable import RoomScanner

final class ArtifactPublicationBoundaryTests:XCTestCase {
    private func request(project:UUID,revision:String) -> ProjectExportRequest {
        .init(projectID:project,kind:.quantities,metadataDigest:String(repeating:"a",count:64),
              sourceRevision:String(repeating:revision,count:64),locale:"en",unit:.meters,includeDetails:false,wastePercent:10)
    }

    func testEveryPublicationFailurePreservesExistingExportIndexAndSourceThenAllowsRetry() throws {
        for stage in ProjectArtifactIndex.PublicationStage.allCases {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at:root) }
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            let source = root.appendingPathComponent("source.csv"),project = UUID()
            let first = request(project:project,revision:"b"),next = request(project:project,revision:"c")
            try Data("old durable output".utf8).write(to:source)
            let existing = try ProjectArtifactIndex.publish(source,request:first,projectName:"Survey",root:root)
            let folder = ProjectArtifacts.directory(root:root,projectID:project)
            let priorIndex = try Data(contentsOf:folder.appendingPathComponent(".artifact-index-v1.json"))
            let changed = Data("new attempted output".utf8)
            try changed.write(to:source,options:.atomic)
            XCTAssertThrowsError(try ProjectArtifactIndex.publishResult(source,request:next,projectName:"Survey",sourceNames:[],root:root,fault:{ point in
                if point == stage { throw CocoaError(.fileWriteOutOfSpace) }
            }))
            XCTAssertEqual(try Data(contentsOf:existing),Data("old durable output".utf8))
            XCTAssertEqual(try Data(contentsOf:source),changed)
            XCTAssertEqual(try Data(contentsOf:folder.appendingPathComponent(".artifact-index-v1.json")),priorIndex)
            XCTAssertEqual(try ProjectArtifacts.files(root:root,projectID:project),[existing])
            XCTAssertNil(try ProjectArtifactIndex.lookup(next,root:root))
            let retry = try ProjectArtifactIndex.publish(source,request:next,projectName:"Survey",root:root)
            XCTAssertNotEqual(retry,existing)
            XCTAssertEqual(try Data(contentsOf:retry),changed)
            XCTAssertEqual(try ProjectArtifactIndex.lookup(first,root:root),existing)
        }
    }

    func testIndexFailureWhileReusingBytesNeverDeletesTheExistingFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let source = root.appendingPathComponent("source.csv"),project = UUID(),bytes = Data("same content".utf8)
        try bytes.write(to:source)
        let first = request(project:project,revision:"b"),next = request(project:project,revision:"c")
        let saved = try ProjectArtifactIndex.publish(source,request:first,projectName:"Survey",root:root)
        let records = try ProjectArtifactIndex.records(root:root,projectID:project)
        XCTAssertThrowsError(try ProjectArtifactIndex.publishResult(source,request:next,projectName:"Other name",sourceNames:[],root:root,fault:{ point in
            if point == .beforeIndexWrite { throw CocoaError(.fileWriteNoPermission) }
        }))
        XCTAssertEqual(try Data(contentsOf:saved),bytes)
        XCTAssertEqual(try ProjectArtifactIndex.records(root:root,projectID:project),records)
        XCTAssertEqual(try ProjectArtifactIndex.lookup(first,root:root),saved)
        XCTAssertNil(try ProjectArtifactIndex.lookup(next,root:root))
    }

    func testCancellationAfterFilePublicationDoesNotLeaveAnIndexedOrVisibleNewExport() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let source = root.appendingPathComponent("source.csv"),project = UUID()
        try Data("attempted output".utf8).write(to:source)
        let value = request(project:project,revision:"b")
        XCTAssertThrowsError(try ProjectArtifactIndex.publishResult(source,request:value,projectName:"Survey",sourceNames:[],root:root,fault:{ point in
            if point == .afterPublication { throw CancellationError() }
        })) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertTrue(try ProjectArtifacts.files(root:root,projectID:project).isEmpty)
        XCTAssertTrue(try ProjectArtifactIndex.records(root:root,projectID:project).isEmpty)
        XCTAssertEqual(try Data(contentsOf:source),Data("attempted output".utf8))
    }

    func testModifiedSourceDuringCopyCannotPublishBytesUnderTheEarlierChecksum() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let source = root.appendingPathComponent("source.csv"),project = UUID()
        try Data("original candidate".utf8).write(to:source)
        let value = request(project:project,revision:"b")
        XCTAssertThrowsError(try ProjectArtifactIndex.publishResult(source,request:value,projectName:"Survey",sourceNames:[],root:root,fault:{ point in
            if point == .beforeCopy { try Data("changed candidate".utf8).write(to:source,options:.atomic) }
        }))
        XCTAssertTrue(try ProjectArtifactIndex.records(root:root,projectID:project).isEmpty)
        XCTAssertTrue(try ProjectArtifacts.files(root:root,projectID:project).isEmpty)
        XCTAssertEqual(try Data(contentsOf:source),Data("changed candidate".utf8))
    }
}
