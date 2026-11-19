import Foundation
import Sparkle

/// Sparkle 2 (macOS): daily check, 'Check for Updates...' menu item.
/// Updater only starts if `SUPublicEDKey` is present in Info.plist (added
/// with EdDSA key): without key, Sparkle
/// would reject feed and display an error at launch.
/// Observed properties are stored mirror states of Sparkle: `@Observable`
/// requires stored properties for SwiftUI view invalidation.
@Observable
@MainActor
final class UpdaterController {
    private let controller: SPUStandardUpdaterController
    private let delegate = Delegate()
    /// `false` in development (no key): menu item is disabled.
    let isConfigured: Bool
    private(set) var canCheckForUpdates = false
    private(set) var lastUpdateCheckDate: Date?
    var automaticallyChecksForUpdates: Bool {
        didSet { if isConfigured { controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates } }
    }

    init() {
        isConfigured = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String).map { !$0.isEmpty } ?? false
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: delegate, userDriverDelegate: nil)
        automaticallyChecksForUpdates = true
        if isConfigured { controller.startUpdater() }
        delegate.onCycleFinished = { [weak self] in self?.refresh() }
        refresh()
    }

    func checkForUpdates() {
        guard isConfigured else { return }
        controller.checkForUpdates(nil)
        refresh()
    }

    /// Reads Sparkle state into observable mirror properties.
    func refresh() {
        guard isConfigured else { canCheckForUpdates = false; return }
        canCheckForUpdates = controller.updater.canCheckForUpdates
        lastUpdateCheckDate = controller.updater.lastUpdateCheckDate
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
    }

    /// Relays Sparkle update cycle events to the main thread.
    private final class Delegate: NSObject, SPUUpdaterDelegate {
        var onCycleFinished: (() -> Void)?
        func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
            let cb = onCycleFinished
            Task { @MainActor in cb?() }
        }
    }
}
