import XCTest
@testable import RoomScanner

final class StudioExportPreparationTests: XCTestCase {
    func testCancelledWorkerDoesNotPublishAResult() async {
        let task = Task { () throws -> Int in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await StudioExportPreparation.worker { 42 }
        }
        do { _ = try await task.value; XCTFail("Cancelled work returned a result") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    @MainActor func testAsyncProjectReportsCompletion() async throws {
        let room = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:"Room")
        let document = SceneEditDocument(source:.room,sourceID:room.id,title:"Design",shell:House(room:room),objects:[])
        var progress: [Double] = []
        let data = try await StudioExporter.dataAsync(document,format:.project,progress:{ progress.append($0) })
        XCTAssertFalse(data.isEmpty); XCTAssertEqual(progress,[0,1])
    }
    func testWorkerProjectRoundTripAndUnsupportedFormat() async throws {
        let room = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:"Room")
        let document = SceneEditDocument(source:.room,sourceID:room.id,title:"Design",shell:House(room:room),objects:[])
        let data = try await StudioExportPreparation.worker {
            XCTAssertFalse(Thread.isMainThread)
            return try XCTUnwrap(StudioExportPreparation.data(document,format:"project",story:nil))
        }
        XCTAssertEqual(try JSONDecoder().decode(SceneEditDocument.self,from:data),document)
        XCTAssertNil(try StudioExportPreparation.data(document,format:"usdz",story:nil))
    }
}
