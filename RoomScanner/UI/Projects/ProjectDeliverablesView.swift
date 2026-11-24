import SwiftUI

struct ProjectDeliverablesView: View {
    let projectID: UUID
    @Environment(RenovationWorkspace.self) private var workspace
    @Environment(RoomStore.self) private var store
    @State private var files: [URL] = []
    @State private var busy = false
    @State private var error: String?
    @Environment(\.locale) private var locale
    private var root: URL { RootView.hasForcedRoot ? store.location.documentsURL : StorageLocation.local().documentsURL }
    var body: some View {
        List {
            Section("Create a report") {
                Button("Project report · PDF",systemImage:"doc.richtext") { generatePDF() }.disabled(busy)
                if busy { ProgressView("Generating report…") }
                Text("Reports include available source scans. Missing items are listed, never silently omitted.").font(.caption)
            }
            Section("Exports") {
                ForEach(files,id:\.self) { file in ShareLink(item:file) { Label(file.lastPathComponent,systemImage:"square.and.arrow.up") } }
                if files.isEmpty { Text("No exports yet") }
            }
        }.navigationTitle("Exports").task { reload() }
            .alert("Report",isPresented:Binding(get:{ error != nil },set:{ if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private func reload() { do { files = try ProjectArtifacts.files(root:root,projectID:projectID) } catch { self.error = error.localizedDescription } }
    private func generatePDF() {
        guard let project = workspace.project(projectID) else { return }
        busy = true
        let entries = workspace.entries, root = root, locale = locale
        Task {
            defer { busy = false }
            do {
                _ = try await Task.detached(priority:.userInitiated) {
                    let report = try ProjectReportLoader.load(project:project,entries:entries,locale:locale)
                    return try ProjectArtifacts.save(ProjectReportRenderer.pdf(report,locale:locale),extension:"pdf",root:root,projectID:projectID)
                }.value
                reload()
            } catch { self.error = error.localizedDescription }
        }
    }
}
