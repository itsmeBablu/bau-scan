import XCTest
@testable import RoomScanner

final class PhaseOneExportSafetyTests: XCTestCase {
    func testDXFUnicodeEscapesAndDeclaredCodepage() {
        let bytes = DXFTextEncoding.data("Heizkörper 中文 😀")
        let text = String(data:bytes,encoding:.windowsCP1252) ?? ""
        XCTAssertTrue(text.contains("Heizkörper")); XCTAssertTrue(text.contains("\\U+4E2D\\U+6587"))
        XCTAssertTrue(text.contains("\\U+D83D\\U+DE00")); XCTAssertFalse(bytes.isEmpty)
        let room = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:"Büro 中文")
        let data = DXFExporter().data(for:House(room:room))
        XCTAssertTrue(String(data:data,encoding:.windowsCP1252)?.contains("ANSI_1252") == true)
    }
    func testFailedReplacementAndCancellationKeepOldZIP() async throws {
        let fm = FileManager.default,root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at:root) }
        let source = root.appendingPathComponent("Quelle ü"),destination = root.appendingPathComponent("Alt.zip")
        try fm.createDirectory(at:source,withIntermediateDirectories:true)
        try Data("new".utf8).write(to:source.appendingPathComponent("datei.txt"))
        let old = Data("previous".utf8); try old.write(to:destination)
        XCTAssertThrowsError(try ArchiveExporter.zip(directory:source,to:destination,move:{ from,to in
            if from.lastPathComponent.hasPrefix(".package-writing-") { throw CocoaError(.fileWriteUnknown) }
            try fm.moveItem(at:from,to:to)
        }))
        XCTAssertEqual(try Data(contentsOf:destination),old)
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; try ArchiveExporter.zip(directory:source,to:destination) }
        do { try await task.value; XCTFail("Cancellation ignored") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf:destination),old)
        try ArchiveExporter.zip(directory:source,to:destination); try ZIPDirectoryValidator.validate(destination)
        #if os(macOS)
        let process = Process(); process.executableURL = URL(fileURLWithPath:"/usr/bin/unzip"); process.arguments = ["-tq",destination.path]
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus,0)
        #endif
    }
    func testManifestRejectsMissingOrIncorrectBytesAndHashes() throws {
        let fm = FileManager.default,root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at:root) }; try fm.createDirectory(at:root,withIntermediateDirectories:true)
        let file = root.appendingPathComponent("test.txt"); try Data("abc".utf8).write(to:file)
        for (path,size,hash,valid) in [("test.txt",3,try ExportChecksum.sha256(file),true),("../escape",3,"",false),("missing",3,"",false),("test.txt",4,"",false),("test.txt",3,"wrong",false)] {
            try JSONSerialization.data(withJSONObject:["items":[["path":path,"bytes":size,"sha256":hash]]]).write(to:root.appendingPathComponent("manifest.json"))
            if valid { XCTAssertNoThrow(try ExportManifestValidation.validate(in:root)) }
            else { XCTAssertThrowsError(try ExportManifestValidation.validate(in:root)) }
        }
    }
    func testManifestRejectsMalformedInventoryAndNonIntegerSizes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        try Data("x".utf8).write(to:root.appendingPathComponent("a"))
        let bad: [[String:Any]] = [
            ["items":"invalid"],
            ["items":[["path":"a","bytes":true]]],
            ["items":[["path":"a","bytes":1.5]]],
            ["items":[["path":"a//b","bytes":1]]],
            ["items":[["path":"a","bytes":1,"sha256":42]]],
            ["items":[["path":"a","bytes":1],["path":"a","bytes":1]]]
        ]
        for manifest in bad {
            try JSONSerialization.data(withJSONObject:manifest).write(to:root.appendingPathComponent("manifest.json"))
            XCTAssertThrowsError(try ExportManifestValidation.validate(in:root))
        }
    }
}
