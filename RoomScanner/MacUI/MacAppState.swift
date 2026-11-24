import SwiftUI

import SwiftUI

/// Distinct item selectable in the macOS sidebar.
enum MacItem: Hashable, Identifiable {
    case house(HouseRecord)
    case room(RoomRecord)
    case technicalRoom(TechnicalRoomManifest)
    case design(SceneEditDocument)

    var id: String {
        switch self {
        case .house(let h): "house-\(h.id.uuidString)"
        case .room(let r): "room-\(r.id.uuidString)"
        case .technicalRoom(let t): "tech-\(t.id.uuidString)"
        case .design(let d): "design-\(d.source.rawValue)-\(d.sourceID.uuidString)"
        }
    }

    var name: String {
        switch self {
        case .house(let h): h.name
        case .room(let r): r.name
        case .technicalRoom(let t): t.name
        case .design(let d): d.title
        }
    }
}

/// Shared Mac window state: selected room, house, technical room or design, and actions requested by
/// menus (`MacMenuCommands`), executed by `MacRootView`.
@Observable
@MainActor
final class MacAppState {
    enum Action: Equatable { case export(ExportFormat?), exportOrganised(Bool), print, revealInFinder, importPackage, openLibraryFolder }
    var selected: MacItem?
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
