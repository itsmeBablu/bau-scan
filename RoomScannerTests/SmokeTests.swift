import XCTest
@testable import RoomScanner

/// Test de fumée de la phase 0 : la cible de tests se compile et s'exécute
/// on both platforms with `@testable import RoomScanner`.
final class SmokeTests: XCTestCase {
    func testModuleIsLinked() {
        XCTAssertNotNil(RootView.self)
    }
}
