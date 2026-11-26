import SwiftUI
import QuickLook
import UniformTypeIdentifiers

struct ProjectDeliverablesView: View {
    let projectID: UUID
    @Environment(RenovationWorkspace.self) private var workspace
    @Environment(RoomStore.self) private var store
    @Environment(\.locale) private var locale
    @State private var files: [ProjectArtifactFile] = []
    @State private var busy = false
    @State private var includeDetails = false
    @State private var error: String?
    @State private var category = ProjectArtifactCategory.all
    @State private var output = Output.report
    @State private var preview: URL?
    @State private var savingFile = false
    @State private var fileToSave: URL?
    @State private var renaming: ProjectArtifactFile?
    @State private var deleting: ProjectArtifactFile?
    @State private var newName = ""
    @State private var requestID = UUID()
    @State private var generationTask: Task<Void,Never>?
    private enum Output: String, CaseIterable, Identifiable {
        case report = "Project report · PDF", quantities = "Quantities · CSV", complete = "Everything · organised ZIP", photos = "Photos · ZIP"
        var id: String { rawValue }
    }
    private var root: URL { RootView.hasForcedRoot ? store.location.documentsURL : StorageLocation.local().documentsURL }
    private var filtered: [ProjectArtifactFile] { files.filter { category == .all || $0.category == category } }
    var body: some View {
        List {
            Section("Create a report") {
                Picker("Output", selection: $output) { ForEach(Output.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) } }.disabled(busy)
                if output == .complete { Toggle("Include project details in ZIP", isOn: $includeDetails).disabled(busy) }
                Button("Generate", systemImage: "arrow.down.doc") {
                    switch output {
                    case .report: generatePDF()
                    case .quantities: generatePDF(csv: true)
                    case .complete: generateBundle()
                    case .photos: generateBundle(photosOnly: true)
                    }
                }.disabled(busy)
                if busy {
                    ProgressView("Working…")
                    if generationTask != nil { Button("Cancel") { cancelGeneration() } }
                }
                Text("Reports include available source scans. Missing items are listed, never silently omitted.").font(.caption)
            }
            Section("Exports") {
                Picker("Category", selection: $category) { ForEach(ProjectArtifactCategory.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) } }
                ForEach(filtered) { file in
                    HStack {
                        Button { preview = file.url } label: {
                            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                                Text(file.url.lastPathComponent).lineLimit(2)
                                Text(file.url.pathExtension.uppercased()+" · "+ByteCountFormatter.string(fromByteCount:file.bytes,countStyle:.file)).font(.caption).foregroundStyle(.secondary)
                                Text(file.modified, style: .date).font(.caption).foregroundStyle(.secondary)
                                if file.legacy { Text("Legacy filename").font(.caption).foregroundStyle(.secondary) }
                            }
                        }.buttonStyle(.plain)
                        Spacer()
                        Menu {
                            Button("Preview", systemImage: "eye") { preview = file.url }
                            ShareLink(item: file.url) { Label("Share", systemImage: "square.and.arrow.up") }
                            Button("Save to Files", systemImage: "folder") { fileToSave = file.url; savingFile = true }
                            Button("Rename", systemImage: "pencil") { newName = file.url.deletingPathExtension().lastPathComponent; renaming = file }
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = file }
                        } label: { Image(systemName:"ellipsis.circle").frame(minWidth:DS.Size.minimumTouchTarget,minHeight:DS.Size.minimumTouchTarget) }
                            .accessibilityLabel("Export actions")
                    }
                }
                if filtered.isEmpty { Text("No exports yet") }
            }.disabled(busy)
        }.navigationTitle("Exports")
            .task(id: projectID.uuidString+root.path) { await reload() }
            .onDisappear { cancelGeneration() }
            .quickLookPreview($preview)
            .fileExporter(isPresented:$savingFile,items:fileToSave.map { [$0] } ?? [],contentTypes:[fileToSave.flatMap { UTType(filenameExtension:$0.pathExtension) } ?? .data]) { result in
                if case .failure(let failure) = result { error = failure.localizedDescription }
            }
            .alert("Rename export",isPresented:Binding(get:{ renaming != nil },set:{ if !$0 { renaming = nil } })) {
                TextField("Name without extension",text:$newName)
                Button("Save") {
                    guard let file = renaming else { return }; renaming = nil
                    let root = root,name = newName
                    edit { _ = try ProjectArtifacts.rename(file.url,to:name,root:root,projectID:projectID) }
                }
                Button("Cancel",role:.cancel) { renaming = nil }
            }
            .confirmationDialog("Delete exported file?",isPresented:Binding(get:{ deleting != nil },set:{ if !$0 { deleting = nil } }),titleVisibility:.visible) {
                Button("Delete",role:.destructive) {
                    guard let file = deleting else { return }; deleting = nil
                    let root = root
                    edit { try ProjectArtifacts.remove(file.url,root:root,projectID:projectID) }
                }
                Button("Cancel",role:.cancel) { deleting = nil }
            } message: { Text("Only this exported file is removed. Source scans and shared copies remain.") }
            .alert("Report",isPresented:Binding(get:{ error != nil },set:{ if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private func reload() async {
        let root = root
        do {
            let result = try await Task.detached(priority:.utility) { try ProjectArtifacts.inspect(root:root,projectID:projectID) }.value
            guard !Task.isCancelled,root == self.root else { return }; files = result
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func edit(_ work:@escaping () throws -> Void) {
        guard !busy else { return }; busy = true
        Task {
            defer { busy = false }
            do { try await Task.detached(priority:.utility,operation:work).value; await reload() }
            catch { self.error = error.localizedDescription }
        }
    }
    private func cancelGeneration() { requestID = UUID(); generationTask?.cancel(); generationTask = nil; busy = false }
    private func runGeneration(_ work:@escaping () async throws -> URL) {
        guard !busy else { return }
        let request = UUID(); requestID = request; busy = true; error = nil
        generationTask = Task {
            let worker = Task.detached(priority:.userInitiated,operation:work)
            do {
                _ = try await withTaskCancellationHandler(operation:{ try await worker.value },onCancel:{ worker.cancel() })
                guard !Task.isCancelled,requestID == request else { return }
                busy = false; generationTask = nil; await reload()
            } catch {
                guard !Task.isCancelled,requestID == request else { return }
                self.error = error.localizedDescription; busy = false; generationTask = nil
            }
        }
    }
    private func generatePDF(csv: Bool = false) {
        guard let project = workspace.project(projectID) else { return }
        let entries = workspace.entries.map { workspace.localizedEntry($0,locale:self.locale) },root = root,locale = locale,pins = workspace.index.pins ?? [],checks = workspace.index.distanceChecks ?? []
        runGeneration {
            let waste = UserDefaults.standard.object(forKey:"renovation.wastePercent") as? Double ?? 10
            let report = try ProjectReportLoader.load(project:project,entries:entries,locale:locale,pins:pins,checks:checks,wastePercent:waste)
            let data:Data
            if csv { data = ProjectQuantitiesCSV.data(report,locale:locale) }
            else { data = try ProjectReportRenderer.pdf(report,locale:locale) }
            try Task.checkCancellation()
            return try ProjectArtifacts.save(data,extension:csv ? "csv" : "pdf",root:root,projectID:projectID)
        }
    }
    private func generateBundle(photosOnly: Bool = false) {
        guard let project = workspace.project(projectID) else { return }
        let entries = workspace.entries.map { workspace.localizedEntry($0,locale:self.locale) },index = workspace.index,root = root,locale = locale,details = includeDetails
        runGeneration {
            let directory = ProjectArtifacts.directory(root:root,projectID:projectID)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let file = directory.appendingPathComponent(ArchivePath.component(project.name)+(photosOnly ? "-Photos-" : "-Complete-")+UUID().uuidString.prefix(8)+".zip")
            if photosOnly { try SurveyPhotoArchiveWriter.archive(project:project,entries:entries,locale:locale,to:file) }
            else { try await ProjectBundleExporter.write(project:project,index:index,entries:entries,locale:locale,to:file,includeDetails:details) }
            return file
        }
    }
}
