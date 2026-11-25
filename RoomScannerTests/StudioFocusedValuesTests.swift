import XCTest
import SwiftUI
@testable import RoomScanner

final class StudioFocusedValuesTests: XCTestCase {
    @MainActor func testStudioFocusKeyIsAvailableToBothTargets() {
        // SwiftUI constructs FocusedValues; its initializer is not public.
        let scene: WritableKeyPath<FocusedValues,SceneEditSession?> = \.studioSession
        let viewport: WritableKeyPath<FocusedValues,SceneEditSession?> = \.studioViewportSession
        XCTAssertNotEqual(scene,viewport)
    }
}
