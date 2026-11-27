#if DEBUG && os(iOS) && targetEnvironment(simulator)
import Foundation

/// Opt-in entry points for screenshots of the hosted test fixture.
@MainActor enum ScreenshotDestination: String {
    case projects, dashboard, scanSetup, gallery

    static var requested: Self? {
        let defaults = UserDefaults.standard
        guard let root = defaults.string(forKey: "RoomScannerStorageRoot"),
              URL(fileURLWithPath: root).lastPathComponent == "RoomScannerDemo",
              let name = defaults.string(forKey: "RoomScannerScreenshot") else { return nil }
        return Self(rawValue: name)
    }

    func appeared() {
        guard Self.requested == self else { return }
        let marker = RootView.initialLocation().documentsURL.appendingPathComponent("screenshot-ready")
        try? Data(rawValue.utf8).write(to: marker, options: .atomic)
    }
}
#endif
