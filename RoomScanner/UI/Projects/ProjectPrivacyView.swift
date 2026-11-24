import SwiftUI

struct ProjectPrivacyView: View {
    @Environment(RoomStore.self) private var store
    @State private var workspace = RenovationWorkspace()
    @State private var confirming = false
    @State private var selected: UUID?
    @State private var busy = false
    @State private var result: String?
    var body: some View {
        List {
            Section("Project data") {
                Text("Deletion permanently removes indexed scans, their photos, designs and generated project exports in connected libraries. Files you shared elsewhere, legacy export folders, backups and provider-held data are not removed.")
                ForEach(workspace.index.projects) { project in
                    Button(role:.destructive) { selected = project.id; confirming = true } label: { Label(project.isUnsorted ? String(localized:"Unsorted") : project.name,systemImage:"trash") }
                }
                Button("Delete all project data",role:.destructive) { selected = nil; confirming = true }.disabled(workspace.index.projects.isEmpty)
            }.disabled(busy || workspace.loading)
            if busy { ProgressView("Deleting project data…") }
            if let result { Text(result) }
            if let error = workspace.error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Project privacy").task { await workspace.reload(location:store.location) }
            .confirmationDialog("Permanently delete project data?",isPresented:$confirming,titleVisibility:.visible) {
                Button("Delete permanently",role:.destructive) { remove() }
                Button("Cancel",role:.cancel) {}
            } message: { Text("This cannot be undone. Referenced data needed by another project is retained. Offline libraries must be connected first.") }
    }
    private func remove() {
        busy = true
        let index = workspace.index, selected = selected
        let local = RootView.hasForcedRoot ? store.location.documentsURL : StorageLocation.local().documentsURL
        var roots = ["local":local]
        if store.isCloud { roots["icloud"] = store.location.documentsURL }
        let connectedRoots = roots
        Task {
            defer { busy = false }
            do {
                _ = try await Task.detached(priority:.userInitiated) { try ProjectPrivacyStore.delete(index:index,roots:connectedRoots,catalogueRoot:local,projectID:selected) }.value
                store.reload(); await workspace.reload(location:store.location)
                result = AppLanguage.text("Indexed project data deleted. Shared copies and provider-held data are unaffected.")
            } catch { result = error.localizedDescription+" "+AppLanguage.text("Some files may already have been deleted. Refresh and review unavailable items before retrying.") }
        }
    }
}
