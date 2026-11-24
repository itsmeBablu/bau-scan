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
                Button("Quantities · CSV",systemImage:"tablecells") { generatePDF(csv:true) }.disabled(busy)
                Button("Everything · organised ZIP",systemImage:"archivebox") { generateBundle() }.disabled(busy)
                Button("Photos · ZIP",systemImage:"photo.on.rectangle") { generateBundle(photosOnly:true) }.disabled(busy)
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
    private func generatePDF(csv: Bool = false) {
        guard let project = workspace.project(projectID) else { return }
        busy = true
        let entries = workspace.entries, root = root, locale = locale, pins = workspace.index.pins ?? [], checks = workspace.index.distanceChecks ?? []
        Task {
            defer { busy = false }
            do {
                _ = try await Task.detached(priority:.userInitiated) {
                    let waste = UserDefaults.standard.object(forKey:"renovation.wastePercent") as? Double ?? 10
                    let report = try ProjectReportLoader.load(project:project,entries:entries,locale:locale,pins:pins,checks:checks,wastePercent:waste)
                    let data: Data
                    if csv { data = ProjectQuantitiesCSV.data(report,locale:locale) }
                    else { data = try ProjectReportRenderer.pdf(report,locale:locale) }
                    return try ProjectArtifacts.save(data,extension:csv ? "csv" : "pdf",root:root,projectID:projectID)
                }.value
                reload()
            } catch { self.error = error.localizedDescription }
        }
    }
    private func generateBundle(photosOnly: Bool = false) {
        guard let project = workspace.project(projectID) else { return }
        busy = true
        let entries = workspace.entries,index = workspace.index,root = root,locale = locale
        Task {
            defer { busy = false }
            do {
                _ = try await Task.detached(priority:.userInitiated) {
                    let directory = ProjectArtifacts.directory(root:root,projectID:projectID)
                    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
                    let file = directory.appendingPathComponent(ArchivePath.component(project.name)+(photosOnly ? "-Photos-" : "-Complete-")+UUID().uuidString.prefix(8)+".zip")
                    if photosOnly { try SurveyPhotoArchiveWriter.archive(project:project,entries:entries,locale:locale,to:file) }
                    else { try await ProjectBundleExporter.write(project:project,index:index,entries:entries,locale:locale,to:file) }
                    return file
                }.value
                reload()
            } catch { self.error = error.localizedDescription }
        }
    }
}
