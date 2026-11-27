import XCTest
@testable import RoomScanner

/// Retained review artifacts are not replacement goldens. All sources are
/// synthetic/existing test fixtures; never reads or rewrites a user's library.
final class ContinuationExportEvidenceTests: XCTestCase {
    @MainActor func testRepresentativeOutputsKeepSourceBytesAndRoundTripGeometry() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("RoomScannerConsolidationSamples")
            .appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "house.structure", withExtension: "json"))
        let input = try RoomPackage.decoder.decode(StructureInput.self, from: Data(contentsOf: fixture))
        let house = try HouseBuilder().build(from: input, name: "Review fixture")
        let service = ExportService(locale: Locale(identifier: "en_US"), unit: .meters)
        let record = HouseRecord(house: house, createdAt: Date(timeIntervalSince1970: 1_600_000_000))
        for format in [ExportFormat.pdf, .png, .svg, .dxf, .obj, .stl, .ply, .json] {
            let output = try service.export(ExportSubject(record:record,house:house,packageURL:nil), format:format, to:root)
            XCTAssertGreaterThan(try Data(contentsOf: output).count, 200)
        }
        let json = try service.data(for: house, format: .json, title: house.name)
        XCTAssertEqual(try RoomPackage.decoder.decode(House.self, from: json), house)
        let resolved = try ResolvedGeometryExporter.data(for: house, sourceID: house.id)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: resolved))
        try resolved.write(to: root.appendingPathComponent("resolved-geometry.json"))
        let options = try RevitScanEvidence.options(house: house, structureData: Data(contentsOf: fixture))
        let ifc = try RevitIFCExporter.export(house: house, options: options)
        XCTAssertEqual(ifc, try RevitIFCExporter.export(house: house, options: options))
        try ifc.write(to: root.appendingPathComponent("review.ifc"))

        let plan = try XCTUnwrap(house.allRooms.first)
        let design = SceneEditDocument.seed(house: House(room: plan), source: .room, id: plan.id)
        let syntheticUSDZ = try await StudioExporter.dataAsync(design, format: .usdz)
        let source = root.appendingPathComponent("source.roomscan")
        let package = RoomPackage(record: RoomRecord(plan: plan), plan: plan, scan: nil,
                                  usdzMeshData: syntheticUSDZ)
        try package.write(to: source)
        let sourceBytes = try Data(contentsOf: source.appendingPathComponent("plan.json"))
        let output = try service.export(House(room: plan), record: RoomRecord(plan: plan),
                                        format: .usdzMesh, packageURL: source, to: root)
        XCTAssertEqual(try Data(contentsOf: output), syntheticUSDZ, "Raw-copy export must not retessellate or rewrite source bytes")
        let archive = try await BackgroundWork.run {
            try service.export(House(room: plan), record: RoomRecord(plan: plan), format: .zip, packageURL: source, to: root)
        }
        try ZIPDirectoryValidator.validate(archive)
        XCTAssertEqual(try Data(contentsOf: source.appendingPathComponent("plan.json")), sourceBytes)
        XCTAssertEqual(try RoomPackage.readPlan(from: source), plan)
        let readme = "Synthetic fixture review artifacts. USDZ is a generated test model used to verify raw-copy byte preservation, not a physical LiDAR capture. Revit interoperability and physical-device accuracy remain unverified.\n"
        try readme.write(to: root.appendingPathComponent("REVIEW.txt"), atomically: true, encoding: .utf8)
        print("CONSOLIDATION_EXPORT_SAMPLES=\(root.path)")
    }
}
