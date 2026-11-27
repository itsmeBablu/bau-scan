import SwiftUI
import QuickLook
import UniformTypeIdentifiers

struct ProjectDeliverablesView: View {
    let projectID: UUID
    @Environment(RenovationWorkspace.self) private var workspace
    @Environment(RoomStore.self) private var store
    @Environment(\.locale) private var locale
    @State private var files: [ProjectArtifactFile] = []
    @State private var records:[ProjectArtifactIndex.Record] = []
    @State private var reloadRequest = UUID()
    @State private var editOperation = OperationLifetime()
    @State private var visible = false
    private var busy: Bool { editOperation.isRunning || generationTask != nil }
    @State private var includeDetails = false
    @AppStorage(PDFPhotoPolicy.preferenceKey) private var pdfPhotos = PDFPhotoPolicy.defaultValue
    @State private var error: String?
    @State private var scanExport:ProjectLibraryEntry?
    @State private var output = ProjectExportKind.report
    @State private var generationMessage: String?
    @State private var generatedURL: URL?
    @Environment(\.projectPreferences) private var projectPreferences
    @State private var preview: URL?
    @State private var savingFile = false
    @State private var fileToSave: URL?
    @State private var renaming: ProjectArtifactFile?
    @State private var deleting: ProjectArtifactFile?
    @State private var newName = ""
    @State private var requestID = UUID()
    @State private var generationTask: Task<Void,Never>?
    private var root: URL { RootView.hasForcedRoot ? store.location.documentsURL : StorageLocation.local().documentsURL }

    var body: some View {
        List {
            Section("Create a report") {
                Picker("Output", selection: $output) { ForEach(ProjectExportKind.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) } }.disabled(busy)
                if output == .complete { Toggle("Include project details in ZIP", isOn: $includeDetails).disabled(busy) }
                if output == .report || output == .complete { Toggle("Include photos in PDF reports", isOn: $pdfPhotos).disabled(busy) }
                Button("Generate or reuse", systemImage: "arrow.down.doc") { generate(output) }.disabled(busy)
                if let generationMessage { Text(generationMessage).font(.caption).foregroundStyle(.secondary) }
                if let generatedURL { ShareLink(item:generatedURL) { Label("Open or share export",systemImage:"square.and.arrow.up") } }
                if busy {
                    ProgressView("Working…")
                    if generationTask != nil { Button("Cancel") { cancelGeneration() } }
                }
                Text("Reports include available source scans. Missing items are listed, never silently omitted.").font(.caption)
            }
            Section("Individual scans") {
                ForEach(workspace.project(projectID)?.references.compactMap(workspace.entry).filter { !$0.isDesign } ?? []) { entry in
                    Button { scanExport = entry } label: { Label(workspace.title(entry,locale:locale),systemImage:"square.and.arrow.up") }
                }
            }
            ForEach(ProjectArtifactCategory.allCases.filter { $0 != .all }) { category in
            Section(LocalizedStringKey(category.rawValue)) {
                ForEach(files.filter { $0.category == category }) { file in
                    HStack {
                        Button { preview = file.url } label: {
                            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                                Text(file.url.lastPathComponent).lineLimit(2)
                                Text(file.url.pathExtension.uppercased()+" · "+ByteCountFormatter.string(fromByteCount:file.bytes,countStyle:.file)).font(.caption).foregroundStyle(.secondary)
                                Text(file.modified, style: .date).font(.caption).foregroundStyle(.secondary)
                                if file.legacy { Text("Legacy filename").font(.caption).foregroundStyle(.secondary) }
                                if let record = records.first(where:{ $0.filename == file.url.lastPathComponent }) {
                                    Text(LocalizedStringKey(record.request.kind.rawValue)).font(.caption).foregroundStyle(.secondary)
                                    Text(String(record.request.sourceRevision.prefix(12))).font(.caption2).monospaced().foregroundStyle(.secondary)
                                }
                            }
                        }.buttonStyle(.plain)
                        Spacer()
                        Menu {
                            Button("Preview", systemImage: "eye") { preview = file.url }
                            ShareLink(item: file.url) { Label("Share", systemImage: "square.and.arrow.up") }
                            Button("Save to Files", systemImage: "folder") { fileToSave = file.url; savingFile = true }
                            Button("Rename", systemImage: "pencil") { newName = file.url.deletingPathExtension().lastPathComponent; renaming = file }
                            if let record = records.first(where:{ $0.filename == file.url.lastPathComponent }) {
                                Button("Generate current revision",systemImage:"arrow.clockwise") {
                                    includeDetails = record.request.includeDetails; output = record.request.kind
                                    generate(record.request.kind)
                                }
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = file }
                        } label: { Image(systemName:"ellipsis.circle").frame(minWidth:DS.Size.minimumTouchTarget,minHeight:DS.Size.minimumTouchTarget) }
                            .accessibilityLabel("Export actions")
                    }
                }
                if !files.contains(where:{ $0.category == category }) { Text("No exports yet").foregroundStyle(.secondary) }
            }.disabled(busy)
            }
        }.navigationTitle("Exports")
            .task(id: projectID.uuidString+root.path) { await reload() }
            .onAppear { visible = true }
            .onDisappear { visible = false; reloadRequest = UUID(); cancelGeneration() }
            .onChange(of:workspace.catalogueRevision) { _,_ in cancelGeneration(); generatedURL = nil; generationMessage = nil }
            .sheet(item:$scanExport) { entry in ProjectScanExportSheet(entry:entry) }
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
        let root = root,projectID = projectID,request = UUID()
        reloadRequest = request
        do {
            let result = try await BackgroundWork.run(priority:.utility) {
                (try ProjectArtifacts.inspect(root:root,projectID:projectID),try ProjectArtifactIndex.records(root:root,projectID:projectID))
            }
            guard !Task.isCancelled,root == self.root,reloadRequest == request else { return }; files = result.0; records = result.1
        } catch { if !Task.isCancelled,root == self.root,reloadRequest == request { self.error = error.localizedDescription } }
    }
    private func edit(_ work:@escaping () throws -> Void) {
        guard !busy,let request = editOperation.begin() else { return }
        let root = root,project = projectID
        Task { @MainActor in
            defer { editOperation.finish(request) }
            do {
                // Durable rename/delete finishes even when the screen closes.
                try await Task.detached(priority:.utility,operation:work).value
                guard visible,root == self.root,project == projectID else { return }
                generatedURL = nil; generationMessage = nil
                await reload()
            }
            catch {
                guard visible,root == self.root,project == projectID else { return }
                self.error = error.localizedDescription
            }
        }
    }
    private func cancelGeneration() { requestID = UUID(); generationTask?.cancel(); generationTask = nil }
    private func runGeneration(_ work:@escaping @Sendable () async throws -> ProjectArtifactGenerator.Result) {
        guard !busy else { return }
        let request = UUID(); requestID = request; error = nil; generationMessage = nil; generatedURL = nil
        generationTask = Task {
            do {
                let result = try await BackgroundWork.run(work)
                guard !Task.isCancelled,requestID == request else { return }
                generatedURL = result.url
                generationMessage = AppLanguage.text(result.reused ? "Reused unchanged export" : "Created a new export revision",locale:locale)
                generationTask = nil; await reload()
            } catch {
                guard !Task.isCancelled,requestID == request else { return }
                self.error = error.localizedDescription; generationTask = nil
            }
        }
    }
    private func generate(_ kind:ProjectExportKind) {
        guard let project = workspace.project(projectID) else { return }
        let entries = workspace.entries.map { workspace.localizedEntry($0,locale:self.locale) }
        let root = root,locale = locale,index = workspace.index,details = includeDetails,photos = pdfPhotos
        let appUnit = MeasurementUnit(rawValue:UserDefaults.standard.string(forKey:"measurementUnit") ?? "") ?? .both
        let unit = ProjectPreferenceResolution.unit(projectPreferences,appDefault:appUnit)
        let rawWaste = UserDefaults.standard.object(forKey:"renovation.wastePercent") as? Double ?? 10
        let waste = rawWaste.isFinite ? min(100,max(0,rawWaste)) : 10
        runGeneration {
            try await ProjectArtifactGenerator.generate(kind:kind,project:project,index:index,entries:entries,locale:locale,unit:unit,includeDetails:details,wastePercent:waste,root:root,includePhotos:photos)
        }
    }
}
