import XCTest
import SceneKit
@testable import RoomScanner

final class TechnicalRoomPackageTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("technical-package-tests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    private func package() throws -> TechnicalRoomPackage {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "small-boiler-room", withExtension: "json"))
        let room = try JSONDecoder().decode(TechnicalRoom.self, from: Data(contentsOf: url))
        var alignment = TechnicalAlignmentSurvey()
        try alignment.define(origin: .init(x: 0, y: 0, z: 0), xCorner: .init(x: 1, y: 0, z: 0))
        alignment.lockReference()
        var journal = TechnicalCaptureJournal()
        journal.append(.init(timestamp: 1, cameraTransform: Array(repeating: 0, count: 16), intrinsics: Array(repeating: 0, count: 9),
                             imageWidth: 1920, imageHeight: 1080, tracking: "normal", hasSceneDepth: true, hasSmoothedSceneDepth: false, alignmentVerified: false))
        journal.append(.init(timestamp: 2, width: 1, height: 1, imageWidth: 1920, imageHeight: 1080, cameraTransform: Array(repeating: 0, count: 16), intrinsics: Array(repeating: 0, count: 9),
                             depthMetres: [1], confidence: [2], alignmentVerified: false))
        journal.append(.init(timestamp: 3, patches: [], alignmentVerified: false, truncated: true))
        return .init(manifest: .init(id: room.id, name: "Boiler room"), document: .init(room: room), alignment: alignment,
                     journal: journal, worldMapData: Data([1, 2, 3]), thumbnailPNG: Data([137, 80, 78, 71]))
    }
    func testEditableSurveyIncludesCorrectedRoutesAndOriginalObservations() throws {
        var value = try package()
        let run = try XCTUnwrap(value.document.room.pipeRuns.first)
        var position = try XCTUnwrap(run.surfaceHits.first).position
        position.value.x += 1
        value.document.pointOverrides.append(.init(objectID: run.id, pointIndex: 0, position: position))
        let data = try TechnicalRoomJSONExporter.handoff(for: value)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["format"] as? String, "dWalkScan.technicalSurvey")
        let effective = try JSONDecoder().decode(TechnicalRoom.self, from: data)
        XCTAssertEqual(effective.pipeRuns.first?.surfaceHits.first?.position, position)
        let original = try XCTUnwrap(object["originalPipeRuns"])
        let raw = try JSONDecoder().decode([TechnicalPipeRun].self, from: JSONSerialization.data(withJSONObject: original))
        XCTAssertEqual(raw.first, run)
    }
    func testPortableMeshExportsIncludeGeometryAndReopenUSDZ() throws {
        var value = try package()
        let color = TechnicalPoint3(x: 1, y: 0.25, z: 0)
        value.journal.append(TechnicalMeshSnapshot(timestamp: 4, patches: [
            .init(anchorID: UUID(), vertices: [.init(x: 0, y: 0, z: 0), .init(x: 1, y: 0, z: 0), .init(x: 0, y: 1, z: 0)],
                  triangleIndices: [0, 1, 2], colors: [color, color, color])
        ], alignmentVerified: false, truncated: false))
        for format in TechnicalMeshExporter.Format.allCases {
            let url = root.appendingPathComponent("mesh.\(format.rawValue)")
            try TechnicalMeshExporter.write(value, format: format, to: url)
            let data = try Data(contentsOf: url)
            XCTAssertFalse(data.isEmpty)
            switch format {
            case .json:
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                XCTAssertEqual(json["units"] as? String, "m")
                XCTAssertNotNil(json["document"])
                XCTAssertEqual((json["meshes"] as? [Any])?.count, 2)
            case .obj:
                let text = try XCTUnwrap(String(data: data, encoding: .utf8))
                XCTAssertTrue(text.contains("f 1 2 3\n"))
                XCTAssertTrue(text.contains("1.0 0.25 0.0\n"))
            case .dxf:
                let text = try XCTUnwrap(String(data: data, encoding: .utf8))
                XCTAssertTrue(text.contains("$INSUNITS\n70\n6\n"))
                XCTAssertTrue(text.contains("420\n16728064\n"))
                XCTAssertEqual(text.components(separatedBy: "3DFACE").count - 1, 1)
                XCTAssertTrue(text.hasSuffix("0\nEOF\n"))
            case .usdz:
                XCTAssertEqual(Array(data.prefix(2)), [0x50, 0x4b], "USDZ must be a ZIP archive, not renamed text.")
                let scene = try SCNScene(url: url, options: [.convertUnitsToMeters: 1.0])
                XCTAssertFalse(scene.rootNode.childNodes.isEmpty)
                XCTAssertTrue(scene.rootNode.childNodes.contains { $0.geometry != nil || !$0.childNodes.isEmpty })
                let bounds = scene.rootNode.boundingBox
                XCTAssertEqual(Double(bounds.max.x - bounds.min.x), 1, accuracy: 0.001)
            }
        }
        try value.journal.validate()
        let saved = root.appendingPathComponent("coloured.technicalroom")
        try value.write(to: saved)
        XCTAssertEqual(try TechnicalRoomPackage.read(from: saved).journal, value.journal)
    }
    func testIndependentPackageRoundTripIncludesEvidencePhotosAndRecoveryBytes() throws {
        var package = try package()
        let id = UUID(), data = Data([255, 216, 255, 217])
        package.document.photoAssets.append(.init(id: id, jpegData: data))
        package.document.room.photos.append(.init(id: id, reference: .init(value: "photos/\(id.uuidString).jpg", unit: "text", source: .entered, method: "test", accuracyMm: nil)))
        let target = root.appendingPathComponent("\(package.manifest.id).technicalroom")
        try package.write(to: target)
        let reopened = try TechnicalRoomPackage.read(from: target)
        XCTAssertEqual(reopened.manifest, package.manifest)
        XCTAssertEqual(reopened.document, package.document)
        XCTAssertEqual(reopened.alignment, package.alignment)
        XCTAssertEqual(reopened.journal, package.journal)
        XCTAssertEqual(reopened.worldMapData, package.worldMapData)
        XCTAssertEqual(reopened.thumbnailPNG, package.thumbnailPNG)
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("photos/\(id).jpg")), data)
        let annotations = try JSONDecoder().decode(TechnicalAnnotationDocument.self, from: Data(contentsOf: target.appendingPathComponent("annotations.json")))
        XCTAssertTrue(annotations.photoAssets.isEmpty, "Photos are stored as separate files, not duplicated base64 blobs.")
    }
    func testInvalidOverwritePreservesOriginal() throws {
        var package = try package()
        let target = root.appendingPathComponent("survey.technicalroom")
        try package.write(to: target)
        let original = try Data(contentsOf: target.appendingPathComponent("manifest.json"))
        package.document.room.pipeRuns[0].outerDiameterMm.value = -1
        XCTAssertThrowsError(try package.write(to: target))
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("manifest.json")), original)
    }
    func testFailedAtomicSwapRestoresOriginalPackage() throws {
        var package = try package()
        let target = root.appendingPathComponent("survey.technicalroom")
        try package.write(to: target)
        package.manifest.name = "Changed"
        XCTAssertThrowsError(try package.write(to: target, fileManager: FailingSwapFileManager()))
        XCTAssertEqual(try TechnicalRoomPackage.read(from: target).manifest.name, "Boiler room")
    }
    func testOutOfSpacePublicationPreservesSavedSurveyBytes() throws {
        var value = try package()
        let target = root.appendingPathComponent("survey.technicalroom")
        try value.write(to: target)
        let manifest = try Data(contentsOf: target.appendingPathComponent("manifest.json"))
        let room = try Data(contentsOf: target.appendingPathComponent("technical-room.json"))
        value.manifest.name = "Unsaved edit"
        XCTAssertThrowsError(try value.write(to: target, fileManager: OutOfSpacePublicationFileManager()))
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("manifest.json")), manifest)
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("technical-room.json")), room)
        XCTAssertEqual(try TechnicalRoomPackage.read(from: target).manifest.name, "Boiler room")
        try value.write(to: target)
        XCTAssertEqual(try TechnicalRoomPackage.read(from: target).manifest.name, "Unsaved edit")
    }
    func testUnknownVersionsAreRejectedWithoutChangingSource() throws {
        let package = try package(), target = root.appendingPathComponent("survey.technicalroom")
        try package.write(to: target)
        for version in [0, 2, 999] {
            var metadata = package.manifest; metadata.schemaVersion = version
            let data = try JSONEncoder().encode(metadata), file = target.appendingPathComponent("manifest.json")
            try data.write(to: file)
            XCTAssertThrowsError(try TechnicalRoomPackage.read(from: target))
            XCTAssertEqual(try Data(contentsOf: file), data)
        }
    }
    func testExternalSymlinkAndUnsafePhotoReferencesAreRejected() throws {
        var package = try package()
        let target = root.appendingPathComponent("survey.technicalroom")
        try package.write(to: target)
        let external = root.appendingPathComponent("outside.json")
        try Data("private".utf8).write(to: external)
        let annotations = target.appendingPathComponent("annotations.json")
        try FileManager.default.removeItem(at: annotations)
        try FileManager.default.createSymbolicLink(at: annotations, withDestinationURL: external)
        XCTAssertThrowsError(try TechnicalRoomPackage.read(from: target))
        XCTAssertEqual(try Data(contentsOf: external), Data("private".utf8))
        let id = UUID()
        package.document.photoAssets = [.init(id: id, jpegData: Data([255]))]
        package.document.room.photos = [.init(id: id, reference: .init(value: "../outside.json", unit: "text", source: .entered, method: "test", accuracyMm: nil))]
        XCTAssertThrowsError(try package.validate())
    }
    @MainActor func testImportCollisionReopenEditAndRecoverableDelete() async throws {
        let package = try package()
        let source = root.appendingPathComponent("source.technicalroom")
        try package.write(to: source)
        let store = TechnicalRoomLibraryStore(root: root.appendingPathComponent("TechnicalRooms"))
        let first = try await store.importPackage(source)
        let reopened = try await store.importPackage(store.url(for: first))
        XCTAssertEqual(reopened, first)
        XCTAssertEqual(store.records.count, 1, "Opening an already-owned package must not create an import copy.")
        let second = try await store.importPackage(source)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(store.records.count, 2)
        var edited = try await store.read(first)
        edited.manifest.name = "Renamed"
        edited.document.room.pipeRuns[0].outerDiameterMm.value = 28
        try await store.save(edited)
        let read = try await store.read(first)
        XCTAssertEqual(read.manifest.name, "Renamed")
        XCTAssertEqual(read.document.room.pipeRuns[0].outerDiameterMm.value, 28)
        XCTAssertEqual(read.journal, package.journal)
        try store.delete(first)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.root.appendingPathComponent(".Trash").path).count, 1)
    }
    func testMalformedJournalAndReferenceEvidenceCannotBeImported() throws {
        let package = try package(), target = root.appendingPathComponent("survey.technicalroom")
        try package.write(to: target)
        let captureFile = target.appendingPathComponent("capture.json")
        var journal = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: captureFile)) as? [String: Any])
        journal["snapshotOrder"] = []
        let malformed = try JSONSerialization.data(withJSONObject: journal)
        try malformed.write(to: captureFile)
        XCTAssertThrowsError(try TechnicalRoomPackage.read(from: target))
        XCTAssertEqual(try Data(contentsOf: captureFile), malformed)
        try package.write(to: target)
        let surveyFile = target.appendingPathComponent("survey.json")
        var survey = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: surveyFile)) as? [String: Any])
        var frame = try XCTUnwrap(survey["referenceFrame"] as? [String: Any])
        frame["translation"] = ["x": 1, "y": 0, "z": 0]
        survey["referenceFrame"] = frame
        try JSONSerialization.data(withJSONObject: survey).write(to: surveyFile)
        XCTAssertThrowsError(try TechnicalRoomPackage.read(from: target))
    }
    func testSymlinkDestinationCannotRedirectAnOverwrite() throws {
        let package = try package(), outside = root.appendingPathComponent("outside.technicalroom")
        try package.write(to: outside)
        let link = root.appendingPathComponent("redirect.technicalroom")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertThrowsError(try package.write(to: link))
        XCTAssertEqual(try TechnicalRoomPackage.read(from: outside).manifest, package.manifest)
        XCTAssertTrue(try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
    }
    @MainActor func testInterruptedReplacementBackupIsRecoveredOnReload() throws {
        let package = try package()
        let store = TechnicalRoomLibraryStore(root: root.appendingPathComponent("TechnicalRooms"))
        try package.write(to: store.url(for: package.manifest.id))
        let backup = store.root.appendingPathComponent(".technical-backup-\(UUID())")
        try FileManager.default.moveItem(at: store.url(for: package.manifest.id), to: backup)
        try store.reload()
        XCTAssertEqual(store.records.map(\.id), [package.manifest.id])
        XCTAssertEqual(try TechnicalRoomPackage.read(from: store.url(for: package.manifest.id)).document, package.document)
        XCTAssertEqual(store.loadWarnings.count, 1)
    }
}

private final class FailingSwapFileManager: FileManager, @unchecked Sendable {
    private var shouldFail = true
    override func moveItem(at source: URL, to destination: URL) throws {
        if shouldFail, source.lastPathComponent.hasPrefix(".technical-writing-") {
            shouldFail = false; throw CocoaError(.fileWriteUnknown)
        }
        try super.moveItem(at: source, to: destination)
    }
}

private final class OutOfSpacePublicationFileManager: FileManager, @unchecked Sendable {
    override func moveItem(at source: URL, to destination: URL) throws {
        if source.lastPathComponent.hasPrefix(".technical-writing-") { throw CocoaError(.fileWriteOutOfSpace) }
        try super.moveItem(at: source, to: destination)
    }
}
