import XCTest
@testable import RoomScanner

final class ProjectArtifactReuseTests:XCTestCase {
    func testUnchangedRequestReusesAndSourceChangeCreatesRevisionPreservingLegacy() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let plan = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:"A")
        var package = RoomPackage(record:RoomRecord(plan:plan),plan:plan,scan:nil,capturedRoomData:nil,usdzData:nil,usdzMeshData:nil,thumbnailPNG:nil)
        let source = root.appendingPathComponent("source.roomscan"); try package.write(to:source)
        let reference = ProjectReference(kind:.room,itemID:plan.id,library:"local")
        let project = RenovationProject(name:"Renovation",references:[reference]),index = ProjectIndex(projects:[project])
        try ProjectIndexStore.write(index,root:root)
        let entry = ProjectLibraryEntry(reference:reference,title:"A",date:Date(),area:nil,roomCount:1,root:root,url:source)
        let legacy = try ProjectArtifacts.save(Data("legacy".utf8),extension:"csv",root:root,projectID:project.id)
        func generate() async throws -> ProjectArtifactGenerator.Result {
            try await ProjectArtifactGenerator.generate(kind:.quantities,project:project,index:index,entries:[entry],locale:Locale(identifier:"en"),unit:.meters,includeDetails:false,wastePercent:10,root:root)
        }
        let first = try await generate(),second = try await generate()
        XCTAssertFalse(first.reused); XCTAssertTrue(second.reused); XCTAssertEqual(first.url.resolvingSymlinksInPath(),second.url.resolvingSymlinksInPath())
        XCTAssertEqual(first.url.lastPathComponent,"Renovation - A - Quantities.csv")
        package.plan.name = "Changed room"; try package.write(to:source)
        let changed = try await generate()
        XCTAssertFalse(changed.reused); XCTAssertNotEqual(changed.url,first.url)
        XCTAssertTrue(FileManager.default.fileExists(atPath:first.url.path))
        XCTAssertEqual(try Data(contentsOf:legacy),Data("legacy".utf8))
        XCTAssertEqual(try ProjectArtifactIndex.records(root:root,projectID:project.id).count,2)
    }

    func testRenameDeleteAndTamperKeepIndexAndReuseConsistent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let request = request(),source = root.appendingPathComponent("source.csv")
        try Data("first".utf8).write(to:source)
        let first = try ProjectArtifactIndex.publish(source,request:request,projectName:"A",root:root)
        let renamed = try ProjectArtifacts.rename(first,to:"Schedule",root:root,projectID:request.projectID)
        XCTAssertEqual(try ProjectArtifactIndex.lookup(request,root:root),renamed)
        try Data("tamper".utf8).write(to:renamed,options:.atomic)
        XCTAssertNil(try ProjectArtifactIndex.lookup(request,root:root))
        let rebuilt = try ProjectArtifactIndex.publish(source,request:request,projectName:"A",root:root)
        XCTAssertNotEqual(rebuilt,renamed)
        XCTAssertEqual(try Data(contentsOf:renamed),Data("tamper".utf8))
        try ProjectArtifacts.remove(rebuilt,root:root,projectID:request.projectID)
        XCTAssertNil(try ProjectArtifactIndex.lookup(request,root:root))
        XCTAssertTrue(try ProjectArtifactIndex.records(root:root,projectID:request.projectID).isEmpty)
    }

    func testRequestKeysAreDeterministicAndSeparateOptions() throws {
        let first = request()
        XCTAssertEqual(try first.key(),try JSONDecoder().decode(ProjectExportRequest.self,from:ProjectExportRequest.encode(first)).key())
        let alternate = ProjectExportRequest(projectID:first.projectID,kind:first.kind,metadataDigest:first.metadataDigest,sourceRevision:first.sourceRevision,locale:"de_DE",unit:.millimeters,includeDetails:true,wastePercent:5)
        XCTAssertNotEqual(try first.key(),try alternate.key())
        var invalid = first; invalid.schemaVersion = 42
        XCTAssertThrowsError(try invalid.validate())
    }
    func testIdenticalContentUnderDifferentRequestAndNamesReusesOneFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let source = root.appendingPathComponent("source.csv"),firstRequest = request()
        try Data("identical schedule".utf8).write(to:source)
        let first = try ProjectArtifactIndex.publishResult(source,request:firstRequest,projectName:"Musterstraße 5",sourceNames:["EG · Building A · Reception"],root:root)
        let otherRequest = ProjectExportRequest(projectID:firstRequest.projectID,kind:firstRequest.kind,metadataDigest:String(repeating:"c",count:64),sourceRevision:firstRequest.sourceRevision,locale:"de",unit:.meters,includeDetails:false,wastePercent:10)
        let second = try ProjectArtifactIndex.publishResult(source,request:otherRequest,projectName:"Changed label",sourceNames:["Other name"],root:root)
        XCTAssertTrue(second.reused); XCTAssertEqual(first.url.resolvingSymlinksInPath(),second.url.resolvingSymlinksInPath())
        XCTAssertEqual(first.url.lastPathComponent,"Musterstraße 5 - EG · Building A · Reception - Quantities.csv")
        XCTAssertEqual(try ProjectArtifacts.files(root:root,projectID:firstRequest.projectID).count,1)
        let renamed = try ProjectArtifacts.rename(first.url,to:"Reception schedule",root:root,projectID:firstRequest.projectID)
        XCTAssertEqual(try ProjectArtifactIndex.lookup(firstRequest,root:root),renamed)
        XCTAssertEqual(try ProjectArtifactIndex.lookup(otherRequest,root:root),renamed)
    }
    func testConcurrentPublishDeduplicatesUnderCoordinatedTransaction() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let source = root.appendingPathComponent("source.csv"),request = request()
        try Data("same output".utf8).write(to:source)
        _ = try ProjectArtifacts.prepareDirectory(root:root,projectID:request.projectID)
        let urls = try await withThrowingTaskGroup(of:URL.self) { group in
            for _ in 0..<4 { group.addTask { try ProjectArtifactIndex.publish(source,request:request,projectName:"A",root:root) } }
            var values:[URL] = []
            for try await url in group { values.append(url) }
            return values
        }
        XCTAssertEqual(Set(urls).count,1)
        XCTAssertEqual(try ProjectArtifactIndex.records(root:root,projectID:request.projectID).count,1)
        XCTAssertEqual(try ProjectArtifacts.files(root:root,projectID:request.projectID).count,1)
    }

    func testStaleProjectMetadataCannotPublishNewArtifact() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let project = RenovationProject(name:"A"),index = ProjectIndex(projects:[project])
        try ProjectIndexStore.write(index,root:root)
        _ = try ProjectIndexStore.updateNotes("Changed",projectID:project.id,expected:"",root:root)
        do {
            _ = try await ProjectArtifactGenerator.generate(kind:.quantities,project:project,index:index,entries:[],locale:Locale(identifier:"en"),unit:.meters,includeDetails:false,wastePercent:10,root:root)
            XCTFail("Stale metadata must not publish")
        } catch { XCTAssertTrue(error is ProjectArtifactGenerator.SourceChanged) }
        XCTAssertTrue(try ProjectArtifacts.files(root:root,projectID:project.id).isEmpty)
    }
    private func request() -> ProjectExportRequest {
        .init(projectID:UUID(),kind:.quantities,metadataDigest:String(repeating:"a",count:64),sourceRevision:String(repeating:"b",count:64),locale:"en",unit:.meters,includeDetails:false,wastePercent:10)
    }
}
