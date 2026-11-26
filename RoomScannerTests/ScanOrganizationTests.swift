import XCTest
@testable import RoomScanner

final class ScanOrganizationTests: XCTestCase {
    private let english = Locale(identifier: "en")
    private let german = Locale(identifier: "de")

    func testLegacyCatalogueHasNoAssumedGroundFloor() throws {
        var original = ProjectIndex()
        original.reconcile([.init(kind: .house, itemID: UUID(), library: "local")])
        let bytes = try JSONEncoder().encode(original)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        json.removeValue(forKey: "scanOrganization")
        let decoded = try JSONDecoder().decode(ProjectIndex.self, from: JSONSerialization.data(withJSONObject: json))
        try decoded.validate()
        XCTAssertNil(decoded.scanOrganization)
        XCTAssertEqual(decoded, original)
        let unknown = ScanOrganization(kind: .house)
        XCTAssertNil(unknown.level)
        XCTAssertEqual(unknown.levelName(locale: english), "Unassigned level")
    }

    func testExplicitLocaleAndNumericLevels() {
        XCTAssertEqual(StoryNaming.localizedName(for: -2, locale: german), "UG 2")
        XCTAssertEqual(StoryNaming.localizedName(for: 0, locale: german), "EG")
        XCTAssertEqual(StoryNaming.localizedName(for: 3, locale: german), "3. OG")
        XCTAssertEqual(StoryNaming.localizedName(for: -2, locale: english), "Basement 2")
        XCTAssertEqual([10, -2, 1, 0].sorted(), [-2, 0, 1, 10])
        XCTAssertEqual(ScanOrganization.offeredLevels, Array(-3...20))
        let value = ScanOrganization(level: 0, buildingName: "Building A", zoneName: "Reception", kind: .house)
        XCTAssertEqual(value.displayName(locale: english), "Ground floor · Building A · Reception")
    }

    func testNumberScopeAndCollisionNeverOverwrite() throws {
        let a = ProjectReference(kind: .house, itemID: UUID(), library: "local")
        let b = ProjectReference(kind: .house, itemID: UUID(), library: "icloud")
        let other = ProjectReference(kind: .house, itemID: UUID(), library: "local")
        let project = RenovationProject(name: "A", references: [a, b])
        var index = ProjectIndex(projects: [project, .init(name: "B", references: [other])])
        let value = ScanOrganization(level: -1, buildingName: "A", zoneName: "Bath Room", number: 1, kind: .house)
        try index.setOrganization(value, for: a)
        try index.setOrganization(value, for: other)
        XCTAssertEqual(index.numberCollisions(for: value, projectID: project.id), [a])
        XCTAssertEqual(index.suggestedNumber(for: value, projectID: project.id), 2)
        XCTAssertEqual(index.suggestedNumber(for: value, projectID: project.id, excluding: a), 1)
        var caseVariant = value; caseVariant.zoneName = " bath room "
        XCTAssertEqual(index.suggestedNumber(for: caseVariant, projectID: project.id), 2)
        var otherFloor = value; otherFloor.level = 1
        XCTAssertEqual(index.suggestedNumber(for: otherFloor, projectID: project.id), 1)
        var otherKind = value; otherKind.kind = .technicalRoom
        XCTAssertEqual(index.suggestedNumber(for: otherKind, projectID: project.id), 1)
        // Explicit keep-both remains legal and preserves both stable identities.
        try index.setOrganization(value, for: b)
        try index.validate()
        XCTAssertEqual(index.numberCollisions(for: value, projectID: project.id).count, 2)
        XCTAssertEqual(index.projects[0].references, [a, b])
    }

    func testMetadataValidationAndStoryMappingRoundTrip() throws {
        let reference = ProjectReference(kind: .house, itemID: UUID(), library: "local")
        var index = ProjectIndex(); index.reconcile([reference])
        let value = ScanOrganization(level: -1, number: 2, kind: .house, storyLevels: [0: -1, 1: 0, 2: 1])
        try index.setOrganization(value, for: reference)
        let restored = try JSONDecoder().decode(ProjectIndex.self, from: JSONEncoder().encode(index))
        XCTAssertEqual(restored, index); try restored.validate()
        var invalid = value; invalid.otherLevelName = "Roof"
        XCTAssertThrowsError(try index.setOrganization(invalid, for: reference))
        invalid = value; invalid.number = 0
        XCTAssertThrowsError(try invalid.validate())
        invalid = value; invalid.zoneName = String(repeating: "x", count: 121)
        XCTAssertThrowsError(try invalid.validate())
        invalid = value; invalid.buildingName = "A\nB"
        XCTAssertThrowsError(try invalid.validate())
        invalid = value; invalid.kind = .room
        XCTAssertThrowsError(try index.setOrganization(invalid, for: reference))
        index.scanOrganization?["missing"] = value
        XCTAssertThrowsError(try index.validate())
    }

    func testMovingReferenceKeepsMetadataAndStableIdentity() throws {
        let reference = ProjectReference(kind: .technicalRoom, itemID: UUID(), library: "local")
        var index = ProjectIndex(); index.reconcile([reference])
        let value = ScanOrganization(otherLevelName: "Mezzanine", kind: .technicalRoom)
        try index.setOrganization(value, for: reference)
        let target = RenovationProject(name: "Building B"); index.projects.append(target)
        try index.assign(reference, to: target.id); try index.validate()
        XCTAssertEqual(index.scanOrganization?[reference.id], value)
        XCTAssertEqual(index.projects.last?.references, [reference])
    }

    func testDurableDraftRetainsOrganizationWithoutChangingIdentity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScanSessionStore(root: root)
        let value = ScanOrganization(level: -2, buildingName: "A", zoneName: "Heizung", number: 1, kind: .technicalRoom)
        let session = try await store.create(kind: .technical, projectID: UUID(), organization: value)
        let reopened = ScanSessionStore(root: root)
        let recovered = try await reopened.read(session.id)
        XCTAssertEqual(recovered.organization, value)
        XCTAssertEqual(recovered, session)
        let repeated = try await reopened.create(kind: .technical, projectID: session.projectID, id: session.id)
        XCTAssertEqual(repeated.organization, value)
        var changed = value; changed.level = 0
        do {
            _ = try await reopened.create(kind: .technical, projectID: session.projectID, id: session.id, organization: changed)
            XCTFail("Existing draft metadata must not be silently overwritten")
        } catch {}
        let latest = try await reopened.read(session.id)
        XCTAssertEqual(latest, session)
    }

    func testLegacyDraftDecodesWithAbsentOrganization() throws {
        let id = UUID(), date = Date(timeIntervalSince1970: 100)
        let session = ScanSession(id: id, kind: .house, projectID: nil, created: date, updated: date)
        let data = try JSONEncoder().encode(session)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("organization"))
        XCTAssertNil(try JSONDecoder().decode(ScanSession.self, from: data).organization)
    }

    #if os(iOS)
    @MainActor func testPrepareAndRegisterLabelsBeforeCompletingCapture() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let documents = root.appendingPathComponent("Documents")
        defer { try? FileManager.default.removeItem(at: root) }
        let project = RenovationProject(name: "A")
        try ProjectIndexStore.write(.init(projects: [project]), root: documents)
        let value = ScanOrganization(level: -1, number: 1, kind: .house)
        let persistence = CapturePersistence(kind: .house, projectID: project.id, root: root.appendingPathComponent("Drafts"), organization: value)
        try await persistence.prepare()
        let store = try XCTUnwrap(persistence.store)
        let prepared = try await store.read(persistence.id)
        XCTAssertEqual(prepared.organization, value)
        let reference = ProjectReference(kind: .house, itemID: persistence.id, library: "icloud")
        try await persistence.registerOrganization(for: reference, catalogueRoot: documents)
        let catalogue = try ProjectIndexStore.read(root: documents)
        XCTAssertEqual(catalogue.projects.first?.references, [reference])
        XCTAssertEqual(catalogue.scanOrganization?[reference.id], value)
        XCTAssertFalse(FileManager.default.fileExists(atPath: documents.appendingPathComponent("Houses").path))
    }
    #endif
}
