import SwiftUI

/// Shared Mac window state: selected room or house and actions requested by
/// menus (`MacMenuCommands`), executed by `MacRootView`.
@Observable
@MainActor
final class MacAppState {
    enum Action: Equatable { case export(ExportFormat?), print, revealInFinder, importPackage, openLibraryFolder }
    var selected: LibraryItem?
    /// Export formats available for selected item (USDZ availability depends on bundle contents).
    var availableFormats: [ExportFormat] = []
    var pendingAction: Action?
    var hasSelection: Bool { selected != nil }
    func request(_ action: Action) { pendingAction = action }
}

struct MacAppStateKey: FocusedValueKey { typealias Value = MacAppState }
extension FocusedValues {
    var macAppState: MacAppState? {
        get { self[MacAppStateKey.self] }
        set { self[MacAppStateKey.self] = newValue }
    }
}
