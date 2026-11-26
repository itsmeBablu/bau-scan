import XCTest
@testable import RoomScanner

/// Establish baselines on a named Mac/simulator. No portable timing budget is
/// invented here; compare the same dataset, toolchain and destination in Xcode.
final class CorePerformanceTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("core-performance-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        if let root { try FileManager.default.removeItem(at: root) }
    }

    private func measured(_ work: () throws -> Void) {
        let options = XCTMeasureOptions(); options.iterationCount = 3
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric(), XCTCPUMetric()], options: options) {
            do { try autoreleasepool(invoking: work) }
            catch { XCTFail("Performance workload failed: \(error)") }
        }
    }

    func testCatalogueMetadataFor200Scans() throws {
        let fixture = try SyntheticWorkload(root: root)
        XCTAssertEqual(fixture.projects.count, 20); XCTAssertEqual(fixture.entries.count, 200)
        measured {
            let catalogue = try PackageCatalogue.rooms(in: fixture.root.appendingPathComponent("Rooms"))
            XCTAssertEqual(catalogue.records.count, 200)
            XCTAssertTrue(catalogue.problems.isEmpty)
        }
    }

    func testDashboardQuantitiesFor200Scans() throws {
        let fixture = try SyntheticWorkload(root: root)
        measured {
            let area = fixture.plans.map { ProjectScanSummary(house: House(room: $0)) }.reduce(0) { $0 + $1.floorArea }
            XCTAssertEqual(area, 2400, accuracy: 0.01)
        }
    }

    func testSelected200PhotoExportWith500PhotoAnd50AudioLibrary() throws {
        let fixture = try SyntheticWorkload(root: root)
        let photos = try fixture.photos(); try fixture.audio()
        let project = RenovationProject(name: "Performance fixture", date: SyntheticWorkload.date,
                                        references: fixture.entries.map(\.reference))
        measured {
            let output = root.appendingPathComponent("photo-output-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: output) }
            try SelectedPhotosExporter.files(project: project, assets: Array(photos.prefix(200)),
                                              organization: [:], summaries: [:], locale: Locale(identifier: "en"), in: output)
            try ExportManifestValidation.validate(in: output)
        }
    }

    func testEightRoomHouseBuild() {
        let input = StructureInput(rooms: (0..<8).map {
            SyntheticRooms.rectangularRoom(origin: .init(x: Double($0 % 4) * 4, y: Double($0 / 4) * 3), width: 4, depth: 3)
        })
        measured { XCTAssertEqual(try HouseBuilder().build(from: input, name: "Fixture").allRooms.count, 8) }
    }

    func testEightRoomPDFRender() throws {
        let input = StructureInput(rooms: (0..<8).map {
            SyntheticRooms.rectangularRoom(origin: .init(x: Double($0) * 4, y: 0), width: 4, depth: 3)
        })
        let house = try HouseBuilder().build(from: input, name: "Fixture")
        measured { XCTAssertGreaterThan(PlanRenderer().pdfData(house).count, 1000) }
    }

    func testLargeMeshPLYWrite() {
        let mesh = SyntheticWorkload.largeMesh()
        XCTAssertEqual(mesh.triangles.count, 100_000)
        measured { XCTAssertGreaterThan(MeshWriters.ply(mesh, name: "Synthetic fixture").count, 1_000_000) }
    }
}
