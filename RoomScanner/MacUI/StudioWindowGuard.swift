import SwiftUI
import AppKit

@MainActor final class StudioTerminationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let guards = StudioWindowGuard.Coordinator.active.values.filter { $0.dirty() }
        guard !guards.isEmpty else { return .terminateNow }
        Task { @MainActor in
            for guardWindow in guards where guardWindow.dirty() {
                guard await guardWindow.approve() else { sender.reply(toApplicationShouldTerminate:false); return }
            }
            sender.reply(toApplicationShouldTerminate:true)
        }
        return .terminateLater
    }
}

struct StudioWindowGuard: NSViewRepresentable {
    var dirty: () -> Bool
    var save: () async throws -> Void
    func makeCoordinator() -> Coordinator { Coordinator(dirty:dirty,save:save) }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView,context: Context) {
        context.coordinator.dirty = dirty; context.coordinator.save = save
        DispatchQueue.main.async { [weak coordinator = context.coordinator,weak view] in
            if let window = view?.window { coordinator?.attach(window) }
        }
    }
    static func dismantleNSView(_ view: NSView,coordinator: Coordinator) { coordinator.detach() }
    @MainActor final class Coordinator: NSObject, NSWindowDelegate {
        static var active: [ObjectIdentifier:Coordinator] = [:]
        weak var window: NSWindow?
        weak var previous: (any NSWindowDelegate)?
        var dirty: () -> Bool
        var save: () async throws -> Void
        var deciding = false
        init(dirty: @escaping () -> Bool,save: @escaping () async throws -> Void) { self.dirty = dirty; self.save = save }
        func attach(_ window: NSWindow) {
            if self.window !== window {
                detach(); self.window = window; previous = window.delegate; window.delegate = self
                Self.active[ObjectIdentifier(self)] = self
            }
            window.isDocumentEdited = dirty()
        }
        func detach() {
            if window?.delegate === self { window?.delegate = previous; window?.isDocumentEdited = false }
            Self.active.removeValue(forKey:ObjectIdentifier(self)); window = nil
        }
        override func responds(to selector: Selector!) -> Bool { super.responds(to:selector) || previous?.responds(to:selector) == true }
        override func forwardingTarget(for selector: Selector!) -> Any? { previous?.responds(to:selector) == true ? previous : super.forwardingTarget(for:selector) }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard dirty() else { return previous?.windowShouldClose?(sender) ?? true }
            guard !deciding else { return false }
            deciding = true
            Task { @MainActor in
                if await approve() { sender.close() }
                deciding = false
            }
            return false
        }
        func approve() async -> Bool {
            let alert = NSAlert()
            alert.messageText = AppLanguage.text("Save this design before closing?")
            for label in ["Save and close","Discard unsaved edits","Cancel"] { alert.addButton(withTitle:AppLanguage.text(label)) }
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                do { try await save(); return true }
                catch { NSAlert(error:error).runModal(); return false }
            case .alertSecondButtonReturn: return true
            default: return false
            }
        }
    }
}
