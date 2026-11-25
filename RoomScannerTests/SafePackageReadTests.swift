import XCTest
@testable import RoomScanner

final class SafePackageReadTests: XCTestCase {
    func testSizeEntryBudgetAndSymlinkRejection() throws {
        let fm = FileManager.default,root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at:root) }
        try fm.createDirectory(at:root,withIntermediateDirectories:true)
        let file = root.appendingPathComponent("data"); try Data([1,2,3]).write(to:file)
        XCTAssertEqual(try SafePackageRead.data(file,root:root,maximum:3),Data([1,2,3]))
        XCTAssertThrowsError(try SafePackageRead.data(file,root:root,maximum:2))
        XCTAssertThrowsError(try SafePackageRead.validate(root,entries:0))
        XCTAssertThrowsError(try SafePackageRead.validate(root,total:2))
        let link = root.appendingPathComponent("link")
        try fm.createSymbolicLink(at:link,withDestinationURL:file)
        XCTAssertThrowsError(try SafePackageRead.data(link,root:root))
        XCTAssertThrowsError(try SafePackageRead.validate(root))
    }
}
