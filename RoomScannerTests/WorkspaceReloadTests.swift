import XCTest
@testable import RoomScanner

@MainActor final class WorkspaceReloadTests:XCTestCase {
    private final class Gate {
        var armed = false
        let reached = XCTestExpectation(description:"Catalogue reached publication boundary")
        let release = AsyncStream<Void>.makeStream()
        func checkpoint() async {
            guard armed else { return }
            reached.fulfill()
            for await _ in release.stream { break }
        }
    }

    func testNoteEditDuringRefreshRemainsCurrentInMemoryAndOnDisk() async throws {
        let location = StorageLocation.temporary(),gate = Gate()
        defer { gate.release.continuation.finish(); try? FileManager.default.removeItem(at:location.documentsURL) }
        let project = RenovationProject(name:"Renovation")
        try ProjectIndexStore.write(.init(projects:[project]),root:location.documentsURL)
        let workspace = RenovationWorkspace(localRoot:location.documentsURL,beforeCataloguePublication:{ await gate.checkpoint() })
        await workspace.reload(location:location)
        XCTAssertNil(workspace.error)
        gate.armed = true
        let job = Task { await workspace.reload(location:location) }
        await fulfillment(of:[gate.reached],timeout:5)
        XCTAssertTrue(workspace.note("Updated during refresh",projectID:project.id,expected:project.notes))
        gate.release.continuation.yield(())
        await job.value
        XCTAssertEqual(workspace.project(project.id)?.notes,"Updated during refresh")
        XCTAssertEqual(try ProjectIndexStore.read(root:location.documentsURL).projects.first { $0.id == project.id }?.notes,"Updated during refresh")
        XCTAssertFalse(workspace.loading)
    }

    func testCancelledRefreshCannotReconcileOrPublishANewRoot() async throws {
        let location = StorageLocation.temporary(),gate = Gate()
        defer { gate.release.continuation.finish(); try? FileManager.default.removeItem(at:location.documentsURL) }
        let project = RenovationProject(name:"Existing")
        try ProjectIndexStore.write(.init(projects:[project]),root:location.documentsURL)
        let original = try Data(contentsOf:ProjectIndexStore.url(root:location.documentsURL))
        let workspace = RenovationWorkspace(localRoot:location.documentsURL,beforeCataloguePublication:{ await gate.checkpoint() })
        let priorRoot = workspace.notesRoot
        gate.armed = true
        let job = Task { await workspace.reload(location:location) }
        await fulfillment(of:[gate.reached],timeout:5)
        job.cancel(); gate.release.continuation.yield(())
        await job.value
        XCTAssertEqual(workspace.notesRoot,priorRoot)
        XCTAssertEqual(workspace.catalogueRevision,0)
        XCTAssertNil(workspace.project(project.id))
        XCTAssertNil(workspace.error)
        XCTAssertFalse(workspace.loading)
        XCTAssertEqual(try Data(contentsOf:ProjectIndexStore.url(root:location.documentsURL)),original)
    }

    func testRemovalCompletionPreservesAnInterveningProjectNoteEdit() async throws {
        let location = StorageLocation.temporary()
        defer { try? FileManager.default.removeItem(at:location.documentsURL) }
        let plan = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:"Room")
        let url = location.packageURL(for:plan.id)
        try RoomPackage(record:RoomRecord(plan:plan),plan:plan,scan:nil).write(to:url)
        let reference = ProjectReference(kind:.room,itemID:plan.id,library:"local")
        let project = RenovationProject(name:"Renovation",references:[reference])
        try ProjectIndexStore.write(.init(projects:[project]),root:location.documentsURL)
        let workspace = RenovationWorkspace(localRoot:location.documentsURL)
        await workspace.reload(location:location)
        let entry = try XCTUnwrap(workspace.entry(reference))
        await workspace.remove(entry,beforePublication:{
            XCTAssertTrue(workspace.note("Keep the new note",projectID:project.id,expected:project.notes))
        })
        XCTAssertNil(workspace.error)
        XCTAssertNil(workspace.entry(reference))
        XCTAssertFalse(FileManager.default.fileExists(atPath:url.path))
        XCTAssertEqual(workspace.project(project.id)?.notes,"Keep the new note")
        let persisted = try XCTUnwrap(ProjectIndexStore.read(root:location.documentsURL).projects.first { $0.id == project.id })
        XCTAssertEqual(persisted.notes,"Keep the new note")
        XCTAssertFalse(persisted.references.contains(reference))
        XCTAssertFalse(workspace.project(project.id)?.references.contains(reference) ?? true)
    }
}
