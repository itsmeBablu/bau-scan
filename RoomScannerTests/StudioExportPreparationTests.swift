import XCTest
@testable import RoomScanner

final class StudioExportPreparationTests: XCTestCase {
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
