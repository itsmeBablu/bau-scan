import XCTest
@testable import RoomScanner

final class MacOrganisedExportTests: XCTestCase {
    private var tmp: URL!
    private let plan = FloorPlanBuilder().build(from: SyntheticRooms.rectangularRoom().scan, name: "Living Room")

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("MacOrganisedExportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - 1. Folder Layout and Manifest

    func testOrganisedExportGeneratesExpectedLayoutAndManifest() async throws {
        let record = RoomRecord(plan: plan)
        let subject = ExportSubject(record: record, plan: plan, packageURL: nil)
        var options = OrganisedExportService.Options()
        options.includePlans = true
        options.includeModels = true
        options.includePhotos = false
        options.includeStudio = false
        options.includeTechnicalRoom = false

        let zipURL = tmp.appendingPathComponent("test_export.zip")
        try await OrganisedExportService.export(
            subject: subject,
            options: options,
            storageRoot: tmp,
            to: zipURL
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: zipURL.path))
        let zipData = try Data(contentsOf: zipURL)
        XCTAssertEqual(Array(zipData.prefix(4)), [0x50, 0x4B, 0x03, 0x04], "ZIP archive must begin with PK signature")

        let entries = try ZipInspector.listEntries(in: zipURL)
        XCTAssertTrue(entries.contains { $0.hasSuffix("README.txt") }, "Must include README.txt")
        XCTAssertTrue(entries.contains { $0.hasSuffix("manifest.json") }, "Must include manifest.json")
        XCTAssertTrue(entries.contains { $0.contains("plans/plan.pdf") }, "Must include plans/plan.pdf")
        XCTAssertTrue(entries.contains { $0.contains("plans/plan.svg") }, "Must include plans/plan.svg")
        XCTAssertTrue(entries.contains { $0.contains("plans/plan.dxf") }, "Must include plans/plan.dxf")
        XCTAssertTrue(entries.contains { $0.contains("models/model.obj") }, "Must include models/model.obj")
        XCTAssertTrue(entries.contains { $0.contains("models/model.stl") }, "Must include models/model.stl")
        XCTAssertTrue(entries.contains { $0.contains("models/model.ply") }, "Must include models/model.ply")
    }

    // MARK: - 2. Photo Numbering and Name Sanitisation

    func testPhotoNumberingAndSanitisation() throws {
        // Test ArchivePath sanitisation logic
        XCTAssertEqual(ArchivePath.component("Living/Room"), "Living-Room")
        XCTAssertEqual(ArchivePath.component("Bad:Room*Name?"), "Bad-Room-Name-")
        XCTAssertEqual(ArchivePath.component("CON"), "_CON")
        XCTAssertEqual(ArchivePath.component("PRN.txt"), "_PRN.txt")
        XCTAssertEqual(ArchivePath.component("   "), "Room")

        var used = Set<String>()
        let name1 = ArchivePath.unique("Bedroom", used: &used)
        let name2 = ArchivePath.unique("Bedroom", used: &used)
        let name3 = ArchivePath.unique("BEDROOM", used: &used)
        XCTAssertEqual(name1, "Bedroom")
        XCTAssertEqual(name2, "Bedroom-2")
        XCTAssertEqual(name3, "BEDROOM-3")
    }

    // MARK: - 3. Studio Dirty-State Logic

    @MainActor
    func testStudioDirtyStateTransitions() throws {
        let doc = SceneEditDocument.seed(
            house: House(room: plan),
            source: .room,
            id: UUID(),
            scans: []
        )
        let session = SceneEditSession(doc)
        XCTAssertFalse(session.dirty, "Initial session must not be dirty")
        XCTAssertFalse(session.canUndo, "Initial session has no undo history")
        XCTAssertFalse(session.canRedo, "Initial session has no redo history")

        // Add object
        let item = SceneEditObject(
            origin: "test",
            name: "Office Chair",
            family: .chair,
            position: TechnicalPoint3(x: 1.0, y: 0.45, z: 1.0),
            size: TechnicalPoint3(x: 0.6, y: 0.9, z: 0.6),
            yaw: 0,
            story: 0
        )
        try session.addDesignObject(item, allowOverlap: true)
        XCTAssertTrue(session.dirty, "Session must be dirty after edit")
        XCTAssertTrue(session.canUndo, "Undo must be available after edit")
        XCTAssertFalse(session.canRedo)

        // Undo
        session.undo()
        XCTAssertFalse(session.dirty, "Session must not be dirty after undoing back to clean state")
        XCTAssertFalse(session.canUndo)
        XCTAssertTrue(session.canRedo, "Redo must be available after undo")

        // Redo
        session.redo()
        XCTAssertTrue(session.dirty, "Session must be dirty after redo")
        XCTAssertTrue(session.canUndo)

        // Mark saved
        session.markSaved()
        XCTAssertFalse(session.dirty, "Session must not be dirty after markSaved()")
    }

    // MARK: - 4. Regression Tests for Existing Exports

    func testExistingExportServiceOutputsRemainIntact() throws {
        let record = RoomRecord(plan: plan)
        let service = ExportService(locale: Locale(identifier: "en_US"), unit: .meters)

        // PDF
        let pdf = try service.data(for: House(room: plan), format: .pdf, title: "Test")
        XCTAssertTrue(pdf.starts(with: [0x25, 0x50, 0x44, 0x46]), "PDF must start with %PDF header")

        // SVG
        let svg = try service.data(for: House(room: plan), format: .svg, title: "Test")
        let svgStr = String(decoding: svg, as: UTF8.self)
        XCTAssertTrue(svgStr.contains("<svg"), "SVG output must contain <svg element")

        // DXF
        let dxf = try service.data(for: House(room: plan), format: .dxf, title: "Test")
        let dxfStr = String(decoding: dxf, as: UTF8.self)
        XCTAssertTrue(dxfStr.contains("SECTION"), "DXF output must contain SECTION")
    }
}

/// Dependency-free ZIP entry listing using pure Swift.
enum ZipInspector {
    static func listEntries(in zipURL: URL) throws -> [String] {
        let data = try Data(contentsOf: zipURL)
        var entries: [String] = []

        // Read the central directory: streaming ZIP local headers deliberately
        // omit sizes and are followed by data descriptors.
        var offset = 0
        while offset+46 <= data.count {
            guard data[offset..<offset+4] == Data([0x50,0x4b,0x01,0x02]) else { offset += 1; continue }
            func word(_ at:Int) -> Int { Int(data[at]) | Int(data[at+1]) << 8 }
            let length = word(offset+28),extra = word(offset+30),comment = word(offset+32)
            let end = offset+46+length
            guard end+extra+comment <= data.count else { throw CocoaError(.fileReadCorruptFile) }
            entries.append(String(decoding:data[offset+46..<end],as:UTF8.self))
            offset = end+extra+comment
        }

        return entries
    }
}
