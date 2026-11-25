import SwiftUI
import AppKit

/// macOS menus: File › Import... (⌘O), Export... (⌘E) format submenu,
/// Print... (⌘P), Reveal in Finder (⇧⌘R), Open dWalkScan Folder.
struct MacMenuCommands: Commands {
    @FocusedValue(\.macAppState) private var state
    @FocusedValue(\.studioSession) private var session
    @FocusedValue(\.studioViewportSession) private var viewportSession
    let updater: UpdaterController

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("mac.menu.checkForUpdates") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
        CommandGroup(replacing: .saveItem) {
            Button("mac.menu.save") { session?.onSave?() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(session == nil || !session!.dirty)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("common.undo") { session?.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(session?.canUndo != true)
            Button("common.redo") { session?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(session?.canRedo != true)
        }
        CommandGroup(after: .pasteboard) {
            Button("studio.selectAllOnFloor") {
                if let viewportSession { viewportSession.selectAllOnFloor?() }
                else { NSApp.sendAction(NSSelectorFromString("selectAll:"),to:nil,from:nil) }
            }
                .keyboardShortcut("a", modifiers: .command)
        }
        CommandGroup(replacing: .newItem) {
            Button("mac.menu.import") { state?.request(.importPackage) }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(state == nil)
        }
        CommandGroup(replacing: .importExport) {
            Button("mac.menu.export") { state?.request(.export(nil)) }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(state?.hasSelection != true)
            Menu("mac.menu.exportAs") {
                ForEach(ExportFormat.Group.allCases) { group in
                    Section(LocalizedStringKey(group.titleKey)) {
                        ForEach((state?.availableFormats ?? []).filter { $0.group == group }) { format in
                            Button(LocalizedStringKey(format.titleKey)) { state?.request(.export(format)) }
                        }
                    }
                }
                Divider()
                Button("mac.menu.exportOrganised") { state?.request(.exportOrganised(false)) }
                Button("mac.menu.exportPhotosOnly") { state?.request(.exportOrganised(true)) }
            }
            .disabled(state?.hasSelection != true)
            Divider()
            Button("mac.menu.revealInFinder") { state?.request(.revealInFinder) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(state?.hasSelection != true)
            Button("mac.menu.openLibraryFolder") { state?.request(.openLibraryFolder) }
                .disabled(state == nil)
        }
        CommandGroup(replacing: .printItem) {
            Button("mac.menu.print") { state?.request(.print) }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(state?.hasSelection != true)
        }
    }
}
