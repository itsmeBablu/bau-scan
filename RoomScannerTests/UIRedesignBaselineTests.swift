import XCTest
@testable import RoomScanner

final class UIRedesignBaselineTests: XCTestCase {
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        return root
    }
    private func note(project: UUID,reference: ProjectReference) -> ARNote {
        .init(projectID:project,reference:reference,number:1,level:nil,roomID:reference.itemID,position:nil,planPosition:nil,language:"de")
    }
    func testStaleTextWriteThrowsAndKeepsNewerDiskText() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at:root) }
        var old = note(project:UUID(),reference:.init(kind:.room,itemID:UUID(),library:"local"))
        old.createdAt = Date(timeIntervalSince1970:100); old.modifiedAt = old.createdAt; old.text = "Old"
        _ = try ARNoteStore.upsertText(old,root:root)
        var newer = old; newer.modifiedAt = Date(timeIntervalSince1970:200); newer.text = "Newer"
        _ = try ARNoteStore.upsertText(newer,root:root)
        old.text = "Stale draft must not report success"
        XCTAssertThrowsError(try ARNoteStore.upsertText(old,root:root))
        XCTAssertEqual(try ARNoteStore.index(root:root,projectID:old.projectID).notes.first?.text,"Newer")
    }
    func testEqualTimestampWithDifferentTextIsAConflictButIdenticalRetryWorks() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at:root) }
        var original = note(project:UUID(),reference:.init(kind:.house,itemID:UUID(),library:"local"))
        original.text = "Original"
        _ = try ARNoteStore.upsertText(original,root:root)
        XCTAssertEqual(try ARNoteStore.upsertText(original,root:root).text,"Original")
        var conflicting = original; conflicting.text = "Different same-date draft"
        XCTAssertThrowsError(try ARNoteStore.upsertText(conflicting,root:root))
        XCTAssertEqual(try ARNoteStore.index(root:root,projectID:original.projectID).notes.first?.text,"Original")
    }
    func testLocalAndCloudSourceTwinsStayDistinctAfterReload() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at:root) }
        let project = UUID(),source = UUID()
        let local = note(project:project,reference:.init(kind:.room,itemID:source,library:"local"))
        let cloud = note(project:project,reference:.init(kind:.room,itemID:source,library:"icloud"))
        _ = try ARNoteStore.upsertText(local,root:root); _ = try ARNoteStore.upsertText(cloud,root:root)
        let restored = try ARNoteStore.index(root:root,projectID:project)
        XCTAssertEqual(Set(restored.notes.map { $0.reference.library }),["local","icloud"])
        var wrongSource = local; wrongSource.reference = cloud.reference
        XCTAssertThrowsError(try ARNoteStore.upsertText(wrongSource,root:root))
    }
    func testNewTimestampDoesNotAllowAnOutdatedEditorToOverwriteText() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at:root) }
        var original = note(project:UUID(),reference:.init(kind:.room,itemID:UUID(),library:"local"))
        original.createdAt = Date(timeIntervalSince1970:100); original.text = "Original"
        _ = try ARNoteStore.upsertText(original,root:root)
        var other = original; other.text = "Other editor"; other.modifiedAt = Date(timeIntervalSince1970:200)
        _ = try ARNoteStore.upsertText(other,root:root,expected:original)
        var draft = original; draft.text = "Stale editor"; draft.modifiedAt = Date(timeIntervalSince1970:300)
        XCTAssertThrowsError(try ARNoteStore.upsertText(draft,root:root,expected:original))
        XCTAssertEqual(try ARNoteStore.index(root:root,projectID:original.projectID).notes.first?.text,other.text)
    }
    func testProjectNotesReloadAndRejectStaleDraftOrDeletedProject() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at:root) }
        let project = RenovationProject(name:"Renovierung")
        try ProjectIndexStore.write(.init(projects:[project]),root:root)
        _ = try ProjectIndexStore.updateNotes("First",projectID:project.id,expected:"",root:root)
        XCTAssertEqual(try ProjectIndexStore.read(root:root).projects.first?.notes,"First")
        XCTAssertThrowsError(try ProjectIndexStore.updateNotes("Stale draft",projectID:project.id,expected:"",root:root))
        XCTAssertEqual(try ProjectIndexStore.read(root:root).projects.first?.notes,"First")
        _ = try ProjectIndexStore.update(root:root) { $0.projects.removeAll() }
        XCTAssertThrowsError(try ProjectIndexStore.updateNotes("Cannot resurrect",projectID:project.id,expected:"First",root:root))
        XCTAssertTrue(try ProjectIndexStore.read(root:root).projects.isEmpty)
    }
    // Characterization only: Phase 5 will change the contract. Do not implement
    // artifact reuse in Phase 0 or remove existing UUID-named user exports.
    func testDocumentsCurrentExportDuplicationForPhaseFive() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at:root) }
        let project = UUID(),bytes = Data("synthetic report".utf8)
        let first = try ProjectArtifacts.save(bytes,extension:"csv",root:root,projectID:project)
        let second = try ProjectArtifacts.save(bytes,extension:"csv",root:root,projectID:project)
        XCTAssertNotEqual(first,second,"Known baseline: identical requests generate separate artifacts")
        XCTAssertEqual(try ProjectArtifacts.files(root:root,projectID:project).count,2)
        XCTAssertEqual(try Data(contentsOf:first),try Data(contentsOf:second))
    }
}
