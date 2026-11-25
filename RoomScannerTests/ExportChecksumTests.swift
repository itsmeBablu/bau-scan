import XCTest
@testable import RoomScanner

final class ExportChecksumTests: XCTestCase {
    func testKnownSHA256Vectors() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:file) }
        for (text,expected) in [("","e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),("abc","ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")] {
            try Data(text.utf8).write(to:file)
            XCTAssertEqual(try ExportChecksum.sha256(file),expected)
        }
    }
}
