import XCTest
@testable import RoomScanner

@MainActor final class WorkspaceReloadTests:XCTestCase {
    func testProjectRenameUpdatesTheCatalogueAndSurvivesReload() async throws {
        let location = StorageLocation.temporary()
        defer { try? FileManager.default.removeItem(at:location.documentsURL) }
        let project = RenovationProject(name:"Original")
        try ProjectIndexStore.write(.init(projects:[project]),root:location.documentsURL)
        let workspace = RenovationWorkspace(localRoot:location.documentsURL)
        await workspace.reload(location:location)
        XCTAssertTrue(workspace.renameProject(project.id,to:"  Renovation  "))
        XCTAssertEqual(workspace.project(project.id)?.name,"Renovation")
        await workspace.reloadAndWait(location:location)
        XCTAssertEqual(workspace.project(project.id)?.name,"Renovation")
        XCTAssertFalse(workspace.renameProject(project.id,to:"   "))
        XCTAssertEqual(try ProjectIndexStore.read(root:location.documentsURL).projects.first?.name,"Renovation")
    }
    func testSaveRefreshWaitsForAnInFlightCatalogueAndFindsNewScan() async throws {
        let location = StorageLocation.temporary(),gate = Gate()
        defer { gate.release.continuation.finish(); try? FileManager.default.removeItem(at:location.documentsURL) }
        let workspace = RenovationWorkspace(localRoot:location.documentsURL,beforeCataloguePublication:{ await gate.checkpoint() })
        await workspace.reload(location:location)
        gate.armed = true
        let oldRefresh = Task { await workspace.reload(location:location) }
        await fulfillment(of:[gate.reached],timeout:5)
        let plan = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:"New scan")
        try RoomPackage(record:RoomRecord(plan:plan),plan:plan,scan:nil).write(to:location.packageURL(for:plan.id))
        let saveRefresh = Task { await workspace.reloadAndWait(location:location) }
        gate.armed = false; gate.release.continuation.yield(())
        await oldRefresh.value; await saveRefresh.value
        XCTAssertNotNil(workspace.destination(.init(kind:.room,itemID:plan.id,library:"local")))
        XCTAssertFalse(workspace.loading)
    }
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
    func testDuplicatingLocalScanWhileBrowsingCloudPreservesCloudCatalogueAndOwner() async throws {
        let local = StorageLocation.temporary(), cloudRoot = StorageLocation.temporary().documentsURL
        let cloud = StorageLocation(kind:.iCloud,documentsURL:cloudRoot)
        defer {
            try? FileManager.default.removeItem(at:local.documentsURL)
            try? FileManager.default.removeItem(at:cloudRoot)
        }
        func save(_ name:String,_ location:StorageLocation) throws -> ProjectReference {
            let plan = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:name)
            try RoomPackage(record:RoomRecord(plan:plan),plan:plan,scan:nil).write(to:location.packageURL(for:plan.id))
            return .init(kind:.room,itemID:plan.id,library:location.kind == .iCloud ? "icloud" : "local")
        }
        let localRef = try save("Local room",local),cloudRef = try save("Cloud room",cloud)
        let project = RenovationProject(name:"Both libraries",references:[localRef,cloudRef])
        try ProjectIndexStore.write(.init(projects:[project]),root:local.documentsURL)
        let workspace = RenovationWorkspace(localRoot:local.documentsURL)
        await workspace.reload(location:cloud)
        let original = try XCTUnwrap(workspace.entry(localRef))
        let sourceBytes = try Data(contentsOf:original.url.appendingPathComponent("plan.json"))
        XCTAssertNotNil(workspace.entry(cloudRef))
        await workspace.duplicate(original)
        XCTAssertNil(workspace.error)
        XCTAssertNotNil(workspace.entry(cloudRef),"Copy completion must not switch browsing from cloud to local")
        let owner = try XCTUnwrap(ProjectIndexStore.read(root:local.documentsURL).projects.first { $0.id == project.id })
        let copies = owner.references.filter { $0.library == "local" && $0.kind == .room && $0 != localRef }
        XCTAssertEqual(copies.count,1)
        let copy = try XCTUnwrap(copies.first)
        XCTAssertNotNil(workspace.entry(copy))
        XCTAssertEqual(try Data(contentsOf:original.url.appendingPathComponent("plan.json")),sourceBytes)
        XCTAssertEqual(try RoomPackage.readPlan(from:local.packageURL(for:copy.itemID)).name,"Local room "+AppLanguage.text("cloud.importedSuffix"))
    }

    func testDashboardRoomRenameRefreshesSummaryAndKeepsRoomAndPhotoIdentity() async throws {
        let location = StorageLocation.temporary()
        defer { try? FileManager.default.removeItem(at:location.documentsURL) }
        let house = try HouseBuilder().build(from:SyntheticRooms.twoStoryHouse(),name:"House")
        let record = HouseRecord(house:house)
        try HousePackage(record:record,house:house,rooms:[]).write(to:location.housePackageURL(for:house.id))
        let workspace = RenovationWorkspace(localRoot:location.documentsURL)
        await workspace.reload(location:location)
        let reference = ProjectReference(kind:.house,itemID:house.id,library:"local")
        let entry = try XCTUnwrap(workspace.entry(reference)),room = try XCTUnwrap(house.allRooms.first)
        try await workspace.renameRoom(entry,roomID:room.id,to:"Reception")
        let changed = try HousePackage.readHouse(from:entry.url)
        XCTAssertEqual(changed.allRooms.first { $0.id == room.id }?.name,"Reception")
        XCTAssertEqual(changed.allRooms.map(\.id),house.allRooms.map(\.id))
        XCTAssertEqual(changed.allRooms.map(\.walls),house.allRooms.map(\.walls))
        XCTAssertEqual(workspace.scanSummaries[reference.id]?.roomDetails.first { $0.id == room.id }?.name,"Reception")
        let summary = ProjectScanSummary(house:changed)
        XCTAssertEqual(summary.roomDetails.reduce(0) { $0+$1.doors },changed.allRooms.flatMap(\.openings).filter { $0.kind == .door }.count)
    }

}
