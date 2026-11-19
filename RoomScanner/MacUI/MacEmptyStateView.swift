import SwiftUI

/// Empty state on Mac: capture is done on iPhone, rooms sync via iCloud Drive
/// or by importing a `.roomscan` package.
struct MacEmptyStateView: View {
    @Environment(RoomStore.self) private var store
    var onImport: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("mac.empty.title", systemImage: "iphone.gen3.radiowaves.left.and.right")
        } description: {
            Text(store.isCloud ? "mac.empty.description.icloud" : "mac.empty.description.local")
        } actions: {
            Button("mac.menu.import", action: onImport)
        }
    }
}
