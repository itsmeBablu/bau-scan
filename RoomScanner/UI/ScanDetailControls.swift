import SwiftUI

/// Shared presentation only. Details retain their own loading, package and viewer.
enum ScanDetailTab: Hashable { case plan, viewer, measures, photos }

struct ScanDetailTabPicker: View {
    @Binding var selection: ScanDetailTab
    var body: some View {
        Picker("Model view",selection:$selection) {
            Text("detail.tab.plan").tag(ScanDetailTab.plan)
            Text("detail.tab.viewer").tag(ScanDetailTab.viewer)
            Text("detail.tab.measures").tag(ScanDetailTab.measures)
            Text("detail.tab.photos").tag(ScanDetailTab.photos)
        }.pickerStyle(.segmented)
    }
}

struct ScanDetailToolbar: ToolbarContent {
    let ready: Bool
    let export: () -> Void
    let design: () -> Void
    let rename: () -> Void
    var radiators: (() -> Void)? = nil
    var body: some ToolbarContent {
        ToolbarItem(placement:.primaryAction) {
            Button(action:export) { Label("detail.export",systemImage:"square.and.arrow.up") }
                .disabled(!ready)
                #if os(iOS)
                .keyboardShortcut("e",modifiers:.command)
                #endif
        }
        ToolbarItem(placement:.primaryAction) {
            Menu {
                Button(action:design) { Label("Open in Design",systemImage:"square.stack.3d.up") }.disabled(!ready)
                if let radiators { Button(action:radiators) { Label("Radiators",systemImage:"radiator") }.disabled(!ready) }
                Button(action:rename) { Label("detail.rename",systemImage:"pencil") }
            } label: { Label("Options",systemImage:"ellipsis.circle") }
        }
    }
}

#if os(macOS)
struct ScanDetailKeyboardShortcuts: View {
    @Binding var selection: ScanDetailTab
    var body: some View {
        Group {
            Button("") { selection = .plan }.keyboardShortcut("1",modifiers:.command)
            Button("") { selection = .viewer }.keyboardShortcut("2",modifiers:.command)
            Button("") { selection = .measures }.keyboardShortcut("3",modifiers:.command)
            Button("") { selection = .photos }.keyboardShortcut("4",modifiers:.command)
        }
    }
}
#endif
