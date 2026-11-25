import XCTest
@testable import RoomScanner

final class LibraryProblemTests: XCTestCase {
    @MainActor func testUnreadableAndFuturePackagesRemainVisible() throws {
        let location = StorageLocation.temporary(),fm = FileManager.default
        defer { try? fm.removeItem(at:location.documentsURL) }
        try location.prepare()
        let corrupt = location.packageURL(for:UUID())
        try fm.createDirectory(at:corrupt,withIntermediateDirectories:true)
        try Data("broken".utf8).write(to:corrupt.appendingPathComponent("meta.json"))
        let plan = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:"Future")
        var record = RoomRecord(plan:plan); record.schemaVersion = FloorPlan.schemaVersion+1
        try RoomPackage(record:record,plan:plan).write(to:location.packageURL(for:record.id))
        let store = RoomStore(location:location,allowsCloud:false); store.reload()
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertEqual(Set(store.libraryProblems.map(\.reason)),Set([.corrupt,.unsupportedSchema]))
    }
    func testClassification() {
        let decoding = DecodingError.dataCorrupted(.init(codingPath:[],debugDescription:"Corrupt"))
        XCTAssertEqual(LibraryProblem.classify(decoding),.corrupt)
        XCTAssertEqual(LibraryProblem.classify(decoding,downloaded:false),.notDownloaded)
        XCTAssertEqual(LibraryProblem.classify(CocoaError(.fileReadNoPermission)),.ioError)
    }
}
