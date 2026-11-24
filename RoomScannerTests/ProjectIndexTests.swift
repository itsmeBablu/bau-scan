import XCTest
@testable import RoomScanner

final class ProjectIndexTests: XCTestCase {
    func testLegacyDiscoveryIsIdempotentAndDoesNotDropOfflineReferences() throws {
        let reference = ProjectReference(kind: .house, itemID: UUID(), library: "local")
        var index = ProjectIndex(); index.reconcile([reference, reference], now: Date(timeIntervalSince1970: 1))
        let once = index
        index.reconcile([reference], now: Date(timeIntervalSince1970: 2)); index.reconcile([])
        XCTAssertEqual(index, once)
        XCTAssertEqual(index.projects[0].id, ProjectIndex.unsortedID)
        XCTAssertEqual(try JSONDecoder().decode(ProjectIndex.self, from: JSONEncoder().encode(index)), index)
    }
    func testAssignmentRetainsStableReferenceAndRejectsMissingProject() throws {
        let reference = ProjectReference(kind: .technicalRoom, itemID: UUID(), library: "local")
        var index = ProjectIndex(); index.reconcile([reference])
        let project = RenovationProject(name: "Hauptstraße 5"); index.projects.append(project)
        try index.assign(reference, to: project.id); try index.validate()
        XCTAssertEqual(index.projects[1].references, [reference]); XCTAssertTrue(index.projects[0].references.isEmpty)
        XCTAssertThrowsError(try index.assign(reference, to: UUID()))
    }
    func testSeparateStorePreservesExistingLibraryBytes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let legacy = root.appendingPathComponent("existing.roomscan"); let bytes = Data("unchanged".utf8)
        try bytes.write(to: legacy)
        XCTAssertEqual(try ProjectIndexStore.read(root: root), ProjectIndex())
        var index = ProjectIndex(); index.reconcile([.init(kind: .room, itemID: UUID(), library: "local")])
        try ProjectIndexStore.write(index, root: root)
        XCTAssertEqual(try ProjectIndexStore.read(root: root), index)
        XCTAssertEqual(try Data(contentsOf: legacy), bytes)
    }
    func testCoordinatedUpdatesReadLatestIndexInsteadOfOverwritingNewerProjects() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let first = RenovationProject(name:"First"), second = RenovationProject(name:"Second")
        _ = try ProjectIndexStore.update(root:root) { $0.projects.append(first) }
        _ = try ProjectIndexStore.update(root:root) { $0.projects.append(second) }
        XCTAssertEqual(try ProjectIndexStore.read(root:root).projects.map(\.id),[first.id,second.id])
    }
}
