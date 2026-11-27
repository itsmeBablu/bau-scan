import XCTest
@testable import RoomScanner

final class SettingsAboutTests: XCTestCase {
    @MainActor func testSourceRepositoryRequiresExactPassword() {
        XCTAssertTrue(SettingsView.canOpenSourceRepository(password: "7416"))
        XCTAssertTrue(SettingsView.canOpenSourceRepository(password: " 7416\n"))
        XCTAssertFalse(SettingsView.canOpenSourceRepository(password: ""))
        XCTAssertFalse(SettingsView.canOpenSourceRepository(password: "7415"))
        XCTAssertFalse(SettingsView.canOpenSourceRepository(password: "0000"))
    }

    func testWorkspaceNameUsesGoogleNameWhenCustomNameEmpty() {
        XCTAssertNil(SettingsView.workspaceDisplayName(saved: "   ", googleName: nil))
        XCTAssertEqual(SettingsView.workspaceDisplayName(saved: "", googleName: "Babu Reddy Kanala"), "Babu Reddy Kanala")
        XCTAssertEqual(SettingsView.workspaceDisplayName(saved: "Custom Name", googleName: "Babu Reddy Kanala"), "Custom Name")
    }

    @MainActor func testGoogleAccountProfilePopulatesAndClearsAvatarURL() {
        let account = TechnicalGoogleAIAccount()
        let url = URL(string: "https://example.com/avatar.png")
        account.applyProfile(email: "test@example.com", displayName: "Babu Reddy Kanala", avatarURL: url)
        XCTAssertEqual(account.displayName, "Babu Reddy Kanala")
        XCTAssertEqual(account.avatarURL, url)
        account.applyProfile(email: nil, displayName: nil, avatarURL: nil)
        XCTAssertNil(account.displayName)
        XCTAssertNil(account.avatarURL)
    }
}
