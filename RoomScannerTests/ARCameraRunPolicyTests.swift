#if os(iOS)
import XCTest
import ARKit
@testable import RoomScanner

final class ARCameraRunPolicyTests:XCTestCase {
    @MainActor func testTechnicalCameraUsesTheRenderersSessionBeforeCaptureStarts() {
        let scanner = TechnicalRoomScanCoordinator(),native = ARSession()
        XCTAssertTrue(scanner.bindCameraSession(native))
        XCTAssertTrue(scanner.session === native)
        XCTAssertTrue(scanner.bindCameraSession(native),"A view reappearing with the same session is idempotent")
        XCTAssertFalse(scanner.hasLiveFrames)
    }
    func testVisibleForegroundWindowRunsWithoutDependingOnSwiftUITabScenePhase() {
        XCTAssertTrue(ARCameraRunPolicy.shouldRun(visible:true,attached:true,width:390,height:700,applicationActive:true))
        XCTAssertFalse(ARCameraRunPolicy.shouldRun(visible:false,attached:true,width:390,height:700,applicationActive:true))
        XCTAssertFalse(ARCameraRunPolicy.shouldRun(visible:true,attached:false,width:390,height:700,applicationActive:true))
        XCTAssertFalse(ARCameraRunPolicy.shouldRun(visible:true,attached:true,width:0,height:700,applicationActive:true))
        XCTAssertFalse(ARCameraRunPolicy.shouldRun(visible:true,attached:true,width:390,height:700,applicationActive:false))
    }
}
#endif
