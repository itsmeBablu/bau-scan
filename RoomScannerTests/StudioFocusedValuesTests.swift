import XCTest
import SwiftUI
@testable import RoomScanner

final class StudioFocusedValuesTests: XCTestCase {
    @MainActor func testStudioFocusKeyIsAvailableToBothTargets() {
        var values = FocusedValues()
        XCTAssertNil(values.studioSession)
        values.studioSession = nil
    }
}
