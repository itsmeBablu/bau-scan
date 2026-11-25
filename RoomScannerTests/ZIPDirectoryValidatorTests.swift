import XCTest
@testable import RoomScanner

final class ZIPDirectoryValidatorTests: XCTestCase {
    private func storedZIP(_ names: [String],symlink: Bool = false) -> Data {
        var local = Data(),central = Data()
        func le(_ values: [(UInt64,Int)]) -> Data { Data(values.flatMap { value,count in (0..<count).map { UInt8(truncatingIfNeeded:value >> ($0*8)) } }) }
        for name in names {
            let path = Data(name.utf8),offset = local.count
            local.append(le([(0x04034b50,4),(20,2),(0x800,2),(0,2),(0,4),(0,4),(0,4),(0,4),(UInt64(path.count),2),(0,2)])); local.append(path)
            central.append(le([(0x02014b50,4),(0x314,2),(20,2),(0x800,2),(0,2),(0,4),(0,4),(0,4),(0,4),(UInt64(path.count),2),(0,2),(0,2),(0,2),(0,2),(symlink ? 0xA0000000 : 0,4),(UInt64(offset),4)])); central.append(path)
        }
        let start = local.count; local.append(central)
        local.append(le([(0x06054b50,4),(0,2),(0,2),(UInt64(names.count),2),(UInt64(names.count),2),(UInt64(central.count),4),(UInt64(start),4),(0,2)]))
        return local
    }
    func testRejectsTraversalDuplicateCollisionSymlinkAndTruncation() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:file) }
        try storedZIP(["Room/","Room/Büro.txt"]).write(to:file)
        XCTAssertNoThrow(try ZIPDirectoryValidator.validate(file))
        for names in [["../escape"],["/absolute"],["C:/absolute"],["a\\b"],["room.txt","ROOM.TXT"],["room","room/file"],["a/./b"]] {
            try storedZIP(names).write(to:file); XCTAssertThrowsError(try ZIPDirectoryValidator.validate(file),names.joined())
        }
        try storedZIP(["link"],symlink:true).write(to:file); XCTAssertThrowsError(try ZIPDirectoryValidator.validate(file))
        try storedZIP(["ok"]).dropLast().write(to:file); XCTAssertThrowsError(try ZIPDirectoryValidator.validate(file))
    }
}
