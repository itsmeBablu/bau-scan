import XCTest
@testable import RoomScanner

final class ScanSessionStoreTests: XCTestCase {
    func testOrphanCleanupRetainsUnknownHiddenFilesAndRecoveryBackups() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store = ScanSessionStore(root:root), session = try await store.create(kind:.technical,projectID:nil)
        _ = try await store.write(session.id,key:"committed",data:Data("saved".utf8))
        let folder = root.appendingPathComponent(session.id.uuidString+"/segments")
        let backup = folder.appendingPathComponent(".payload.package-backup"), unknown = folder.appendingPathComponent(".manual-recovery")
        let orphan = folder.appendingPathComponent(UUID().uuidString+".data")
        try Data("recovery".utf8).write(to:backup)
        try Data("manual".utf8).write(to:unknown)
        try Data("uncommitted".utf8).write(to:orphan)
        try await store.removeOrphans(session.id)
        XCTAssertEqual(try Data(contentsOf:backup),Data("recovery".utf8))
        XCTAssertEqual(try Data(contentsOf:unknown),Data("manual".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath:orphan.path))
        let saved = try await store.latest(session.id,key:"committed")
        XCTAssertEqual(saved,Data("saved".utf8))
    }
    func testIndependentStoresCannotOverwriteEachOthersCommittedIndex() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = ScanSessionStore(root: root), second = ScanSessionStore(root: root)
        let session = try await first.create(kind: .technical, projectID: nil)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<24 {
                group.addTask {
                    let store = index.isMultiple(of: 2) ? first : second
                    _ = try await store.write(session.id, key: "sample-\(index)", data: Data("payload-\(index)".utf8))
                }
            }
            try await group.waitForAll()
        }
        let reopened = ScanSessionStore(root: root)
        let entries = try await reopened.entries(session.id)
        XCTAssertEqual(entries.count, 24)
        XCTAssertEqual(entries.map(\.sequence), Array(1...24))
        XCTAssertEqual(Set(entries.map(\.key)), Set((0..<24).map { "sample-\($0)" }))
        for entry in entries {
            let data = try await reopened.payload(session.id, entry: entry)
            XCTAssertEqual(String(decoding: data, as: UTF8.self), entry.key.replacingOccurrences(of: "sample-", with: "payload-"))
        }
    }

    func testConcurrentCreationPreservesOneSessionIdentity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), project = UUID()
        let stores = [ScanSessionStore(root: root), ScanSessionStore(root: root)]
        let created = try await withThrowingTaskGroup(of: ScanSession.self) { group in
            for store in stores { group.addTask { try await store.create(kind: .house, projectID: project, id: id) } }
            var results: [ScanSession] = []
            for try await value in group { results.append(value) }
            return results
        }
        XCTAssertEqual(created.count, 2)
        XCTAssertEqual(created[0], created[1])
        let loaded = try await stores[0].read(id)
        XCTAssertEqual(loaded, created[0])
    }

    enum Injected: Error { case crash }
    func testCrashPointsPreserveCommittedPayloadAndAllowRetry() async throws {
        for point in ScanSessionStore.CrashPoint.allCases {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at:root) }
            let normal = ScanSessionStore(root:root)
            let session = try await normal.create(kind:.house,projectID:UUID())
            try await normal.write(session.id,key:"room",data:Data("first".utf8))
            let failing = ScanSessionStore(root:root,fault:{ if $0 == point { throw Injected.crash } })
            do { try await failing.write(session.id,key:"room",data:Data("second".utf8)); XCTFail("Expected injected failure") } catch Injected.crash {} catch { throw error }
            let reopened = ScanSessionStore(root:root)
            let recovered = try await reopened.latest(session.id,key:"room")
            XCTAssertEqual(recovered,Data((point == .afterPayload ? "first" : "second").utf8))
            try await reopened.removeOrphans(session.id)
            let committed = try await reopened.entries(session.id)
            let files = try FileManager.default.contentsOfDirectory(at:root.appendingPathComponent(session.id.uuidString+"/segments"),includingPropertiesForKeys:nil)
            XCTAssertEqual(files.count,committed.count)
            try await reopened.write(session.id,key:"room",data:Data("retry".utf8))
            let final = try await reopened.latest(session.id,key:"room")
            XCTAssertEqual(final,Data("retry".utf8))
        }
    }
    func testSessionStatesMediaAndDiscardRemainIsolated() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store = ScanSessionStore(root:root),project = UUID()
        let a = try await store.create(kind:.technical,projectID:project)
        let b = try await store.create(kind:.room,projectID:nil)
        try await store.write(a.id,key:"photo",data:Data([1,2]),media:true,metadata:["room":UUID().uuidString,"level":"0","pose":"scan-derived"])
        try await store.setState(a.id,.paused)
        let restored = try await store.read(a.id)
        XCTAssertEqual(restored.projectID,project); XCTAssertEqual(restored.state,.paused)
        try await store.setState(a.id,.scanning)
        try await store.setState(a.id,.finalizing)
        try await store.setState(a.id,.failed)
        let failed = try await store.unfinished(); XCTAssertEqual(failed.count,2)
        try await store.setState(a.id,.finalizing)
        try await store.setState(a.id,.completed)
        try await store.setState(a.id,.completed)
        let unfinished = try await store.unfinished(); XCTAssertEqual(unfinished.map(\.id),[b.id])
        do { try await store.write(a.id,key:"late",data:Data()); XCTFail("Completed sessions are immutable") } catch {}
        try await store.discard(b.id)
        let kept = try await store.read(a.id); XCTAssertEqual(kept.state,.completed)
    }
    func testInterruptedManifestReplacementAndRepeatedCreation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store = ScanSessionStore(root:root),id = UUID(),project = UUID()
        let original = try await store.create(kind:.house,projectID:project,id:id)
        let repeated = try await store.create(kind:.house,projectID:project,id:id)
        XCTAssertEqual(original,repeated)
        do { _ = try await store.create(kind:.room,projectID:project,id:id); XCTFail("Identity cannot change kind") } catch {}
        let target = root.appendingPathComponent(id.uuidString+"/session.json")
        try FileManager.default.moveItem(at:target,to:PackageReplacement.backup(for:target))
        let recovered = try await ScanSessionStore(root:root).read(id)
        XCTAssertEqual(recovered,original)
        XCTAssertTrue(FileManager.default.fileExists(atPath:target.path))
    }
    func testFailedRerecordKeepsPreviousMediaAndRejectsSymlinks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store = ScanSessionStore(root:root)
        let session = try await store.create(kind:.house,projectID:nil)
        try await store.write(session.id,key:"voice",data:Data([1]),media:true)
        let failing = ScanSessionStore(root:root,fault:{ if $0 == .afterPayload { throw Injected.crash } })
        do { try await failing.write(session.id,key:"voice",data:Data([2]),media:true); XCTFail() } catch {}
        let clip = try await store.latest(session.id,key:"voice"); XCTAssertEqual(clip,Data([1]))
        let link = root.appendingPathComponent(session.id.uuidString+"/media")
        try FileManager.default.removeItem(at:link)
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:FileManager.default.temporaryDirectory)
        do { try await store.write(session.id,key:"escape",data:Data([3]),media:true); XCTFail("Must reject symlink") } catch {}
    }
}
