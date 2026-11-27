import XCTest
@testable import RoomScanner

final class ExportChecksumTests: XCTestCase {
    func testStreamingAcrossChunkBoundariesMatchesIndependentVector() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:file) }
        let block = Data((0...255).map { UInt8($0) })
        var bytes = Data()
        for _ in 0..<12_288 { bytes.append(block) }
        bytes.append(Data("boundary-tail-017".utf8))
        try bytes.write(to:file)
        // Python hashlib reference: bytes(range(256))*12288+b'boundary-tail-017'.
        XCTAssertEqual(try ExportChecksum.sha256(file),"fc0f840d6113a269ebf494ab3fa654a8317d7da1c36cc4e2e0bfff334515de7b")
        for count in [1_048_575,1_048_576,1_048_577] {
            let boundary = Data(bytes.prefix(count))
            try boundary.write(to:file,options:.atomic)
            XCTAssertEqual(try ExportChecksum.sha256(file),ExportChecksum.digest(boundary))
        }
        XCTAssertEqual(try Data(contentsOf:file),Data(bytes.prefix(1_048_577)))
    }

    func testCancelledChecksumDoesNotOpenAFileOrReturnADigest() async {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let job = Task<Void,Never> {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try ExportChecksum.sha256(missing)
                XCTFail("Cancelled checksum must not produce a digest")
            } catch { XCTAssertTrue(error is CancellationError) }
        }
        await job.value
        XCTAssertFalse(FileManager.default.fileExists(atPath:missing.path))
    }

    func testReadFailureIsNotConvertedToAnEmptyChecksumAndRetryWorks() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:file) }
        XCTAssertThrowsError(try ExportChecksum.sha256(file)) { XCTAssertFalse($0 is CancellationError) }
        try Data("abc".utf8).write(to:file)
        XCTAssertEqual(try ExportChecksum.sha256(file),"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        try FileManager.default.removeItem(at:file)
        XCTAssertThrowsError(try ExportChecksum.sha256(file))
    }

    func testKnownSHA256Vectors() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:file) }
        for (text,expected) in [("","e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),("abc","ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")] {
            try Data(text.utf8).write(to:file)
            XCTAssertEqual(try ExportChecksum.sha256(file),expected)
        }
    }
}
